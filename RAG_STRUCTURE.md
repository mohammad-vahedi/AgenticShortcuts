# RAG architecture for Agentic Shortcuts

This document describes how Cherri code generation works after the sanitizer
was removed in favor of retrieval-augmented prompting plus a compile/retry
feedback loop.

## Why this exists

Before, `ShortcutGenerator.swift` carried ~20 regex passes that tried to
patch up bad LLM output (`fixWebpageFetchPattern`, `hoistNestedActionCalls`,
`rewriteRegexQuantifiers`, …). Each new failure spawned a new pass; the
passes interacted; the model never got a chance to do better because we
masked its mistakes instead of telling it about them.

The new design:

1. Give the model **concrete examples** of what good Cherri looks like for the
   user's specific task (RAG).
2. Try to compile.
3. If it fails, **show the model the error** and ask it to fix the code (one
   retry).
4. Stop. No regex rewriting in between.

## Data flow

```
User prompt
    │
    ▼
┌────────────────────────────┐
│ extractSchedule (LLM)      │   Pulls "every day at 7am for 10 days"
│ → optional Schedule        │   out of the prompt as JSON.
└────────────────────────────┘
    │
    ▼
┌────────────────────────────┐
│ CherriExamples.relevant    │   Score the corpus by keyword overlap with
│ → top-3 snippets           │   the prompt. Reuses ActionCatalog.tokenize
└────────────────────────────┘   so synonyms are shared.
    │
    ▼
┌────────────────────────────┐
│ callModel (1st pass)       │   System prompt: full Cherri guide (.txt).
│ → Cherri code              │   User prompt:   description + examples.
└────────────────────────────┘
    │
    ▼
┌────────────────────────────┐    success
│ CherriCompiler.compile     │ ────────────► return GenerationResult
└────────────────────────────┘
    │ failure
    ▼
┌────────────────────────────┐
│ callModel (retry)          │   User prompt now also includes:
│ → fixed Cherri code        │     - the failed code
└────────────────────────────┘     - the compiler error
    │
    ▼
┌────────────────────────────┐    success / failure
│ CherriCompiler.compile     │ ────────────► return GenerationResult
└────────────────────────────┘
```

## File layout

```
AgenticShortcuts/
├── Resources/
│   └── CherriLLMGuide.txt          ← full language reference (system prompt)
│
├── Services/
│   ├── ActionCatalog.swift         ← every Cherri action + tokenizer + synonyms
│   ├── CherriExamples.swift        ← curated corpus of working snippets (RAG corpus)
│   ├── CherriCompiler.swift        ← shells out to /opt/homebrew/bin/cherri
│   ├── OllamaService.swift         ← /api/chat client
│   ├── ScheduleService.swift       ← launchd plist install/uninstall
│   └── ShortcutGenerator.swift     ← orchestrator (generate → compile → retry)
│
├── Models/                          ← plain data: ShortcutProject, Schedule, GenerationResult
├── Views/                           ← SwiftUI views
└── Intents/                         ← App Intents for Siri
```

## The two retrieval surfaces

### 1. `ActionCatalog.swift` — actions

One `ActionEntry` per Cherri action (`getWebpageContents`, `matchText`, `openApp`, …).
Used today only by the synonym/tokenizer helpers; the catalog itself is
not yet injected into prompts. `score(for:)` is camelCase-aware so
`"open"` in a prompt scores `openApp`.

If you ever want to inject relevant action signatures alongside examples,
the API is already there:

```swift
let actions = ActionCatalog.relevant(for: prompt, topK: 18)
```

### 2. `CherriExamples.swift` — full snippets

`CherriExample` is `{ id, description, keywords, code }`. The corpus is
hand-curated working programs covering the patterns we expect: fetch +
extract, weather, clipboard, menu, repeat, OCR, shell, …

```swift
let examples = CherriExamples.relevant(for: prompt, topK: 3)
```

Scoring: keyword intersection (×2.0) + description-token intersection (×0.5).

## How the prompt is assembled

`ShortcutGenerator.callModel` builds a single user message:

```text
Create a Cherri shortcut that does the following:

<user description>

Below are working Cherri snippets for similar tasks. Adapt them; do not copy
URLs or text verbatim — substitute the real values from the user request.

// <example 1 description>
<example 1 code>

// <example 2 description>
<example 2 code>

// <example 3 description>
<example 3 code>

[only on retry:]
Your previous attempt FAILED to compile. Here is the failed code and the
compiler error. Re-emit the FULL corrected program. Do not explain — just code.

Failed code:
```
<previous attempt>
```

Compiler error:
```
<cherri stderr>
```

Output ONLY raw Cherri source code. No markdown fences, no commentary.
The code must compile as-is.
```

The system prompt is the entire `CherriLLMGuide.txt` (action reference + syntax
rules + common mistakes section).

## Retry loop

Exactly one retry. The retry prompt always carries:

- The original task description.
- The same retrieved examples.
- The previous attempt's full code.
- The verbatim compiler error from `cherri`.

We don't loop forever — if the retry also fails, we surface the error to
the user. They can edit the code in the UI and click Recompile.

## How to extend

### Add a new example

Open `CherriExamples.swift`, add an entry to `all`:

```swift
.init(
    id: "qr_code",
    description: "Generate a QR code from text.",
    keywords: ["qr", "barcode", "code", "generate"],
    code: """
    #include 'actions/documents'
    @qr = makeQRCode("Hello", "Medium")
    show("{qr}")
    """
),
```

That's it. No registration, no plumbing. Make sure `keywords` are the words
a user would actually type in their request (and English variants — synonym
expansion in `ActionCatalog.tokenize` handles a few common ones already).

### Improve retrieval

If a request consistently retrieves the wrong examples:

1. Add the missing trigger words to that example's `keywords`.
2. Or add a synonym to `ActionCatalog.synonyms` so the user's word maps to
   words your example already has.

Don't add a new sanitizer pass. That's the rule we just bought.

### Change the retry budget

Today: one retry. If you find the model often fixes itself only on a third
attempt, change `generate()` in `ShortcutGenerator.swift` — there's only
one place to look. Keep it bounded; uncapped retry loops will burn tokens
on hopeless prompts.

### Tune for a different model

Larger models (`qwen3:8b`, `qwen3.5:9b`) need fewer examples; small models
(`mistral:7b`, `qwen2.5-coder:7b`) benefit from more. The number is the
`topK` argument to `CherriExamples.relevant(for:topK:)`. Default is 3.

## What was deleted

For history — these all lived in the old `ShortcutGenerator.swift` and are
gone now:

- `sanitizeCherriCode` (dispatcher)
- `fixWebpageFetchPattern`, `promoteBareMatchTextCalls`
- `fixUndefinedVariables`, `fixMultilineExtractionRegexes`
- `escapeInnerQuotesInRegexArguments`, `quoteBareRegexArguments`
- `rewriteRegexQuantifiers`, `rewriteQuantifiers`, `quantifierReplacement`
- `workaroundCherriCompilerBug`
- `rewriteStringConcatenation`
- `hoistInterpolatedActionCalls`, `hoistNestedActionCalls`, `hoistConditionActionCalls`
- `coerceCountAssignments`, `replaceUnsupportedCollectionHelpers`
- `normalizeJoinTextGlue`, `normalizeLoopVariableDeclarations`
- `fixInvalidLoopSyntax`, `removeUndefinedActionCalls`
- `validateCherriCode`, `addMissingIncludes`
- `rewritePromptIfNeeded` (the action-translation pre-pass)

The `relevantFewShotExamples` inline helper (added during the
intermediate pass) became `CherriExamples`.

## When to put logic back

If the **same** failure mode shows up across many different prompts and
the model never recovers from it on retry — that is the only signal that
warrants new logic. And even then, prefer fixing it via:

1. A new example that demonstrates the correct pattern, OR
2. A new sentence in `CherriLLMGuide.txt` warning against the mistake.

Only after both fail should you consider a sanitizer. If you do add one,
add a comment pointing to the prompt that triggered it, so the next
person can decide whether it's still earning its keep.
