# Agentic Shortcuts

> A macOS app that turns natural-language descriptions into installable Apple Shortcuts — fully local.

Describe what you want by voice through Siri or by typing in the app window, and get back a ready-to-install `.shortcut` file. Everything runs on your Mac: [Ollama](https://ollama.com) for the LLM, [Cherri](https://cherrilang.org/) for compilation. No cloud calls, no API keys, no usage costs.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![SwiftUI](https://img.shields.io/badge/SwiftUI-native-purple) ![Local](https://img.shields.io/badge/AI-local-green)

---

## What it does

1. You describe a shortcut — *"fetch the weather and show me the temperature."*
2. The app sends your description, plus a Cherri language reference and a few curated working examples retrieved by keyword match, to a local Ollama model.
3. The model returns Cherri source code.
4. The Cherri CLI compiles that source into a `.shortcut` bundle (unsigned, for speed).
5. If compilation fails, the compiler error is fed back to the model for one repair attempt. If that also fails, the broken code is shown in the UI so you can edit it and recompile.
6. When you're ready to install, press **Sign & Open in Shortcuts** — the app re-runs `cherri` with signing enabled and opens the signed `.shortcut` in the Shortcuts app. A **Save Signed File…** button is also available if you want to write the signed bundle to a custom location.

Schedules embedded in the prompt — *"every morning at 7am for 10 days"* — are extracted as a separate LLM pass and installed as `launchd` jobs when you sign & open.

---

## Two ways to use it

| Interface | How to invoke | When it's right |
|---|---|---|
| **Siri / App Intents** | *"Create a shortcut with Agentic Shortcuts"* | Quick one-off requests. The result opens in the Shortcuts app and Siri confirms via dialog. |
| **macOS window** | Launch the app | Watch live pipeline progress, preview and edit the generated Cherri code, browse history and schedules, change the active model, sign and export. |

---

## User interfaces

The app ships with two SwiftUI front-ends that share every service and model:

### Preview UI (default)

Three-column layout — sidebar / main work area / inspector — with:

- A horizontal pipeline stepper showing each stage live
- A dark, syntax-highlighted code preview with line numbers
- A Compile Result card with explicit signing actions
- A bottom log pane with time-stamped pipeline events and an inline callout for the first-attempt compiler error during retry

### Legacy UI

The original single-pane window. Still available via **View → Open Legacy UI** (⌥⌘L) for comparison or fallback. Both UIs talk to the same `ShortcutGenerator` and produce identical output.

---

## Tech stack

- **Swift 5.9, SwiftUI, macOS 14.0+** *(App Shortcuts framework requires Sonoma)*
- **App Intents** for the Siri integration
- **Ollama** at `http://localhost:11434` — chat endpoint
- **Cherri CLI v2.1.1** at `/opt/homebrew/bin/cherri` — compiles `.cherri` source to signed `.shortcut` bundles
- **launchd** for scheduling (via the `ScheduleService`)

### Supported models

Set in Settings; default is `qwen2.5-coder:7b`.

| Model | Notes |
|---|---|
| `mistral:7b` | Fast, lightweight |
| `qwen2.5-coder:7b` | **Default.** Optimized for code generation |
| `qwen3:8b` | General purpose, good intent understanding |
| `qwen3.5:9b` | Larger, best overall reasoning |

---

## Requirements

- macOS 14 Sonoma or later
- Xcode 15 or later (for the macOS 14 SDK and App Intents)
- Ollama installed and running, with at least one supported model pulled:
  ```bash
  ollama pull qwen2.5-coder:7b
  ```
- Cherri at `/opt/homebrew/bin/cherri` (installable via Homebrew)
- **XcodeGen** if you want to regenerate `AgenticShortcuts.xcodeproj` from `project.yml`:
  ```bash
  brew install xcodegen
  ```

---

## Project layout

```
AgenticShortcuts/
├── AgenticShortcutsApp.swift     # @main; scenes: PreviewMainView (default),
│                                 # SchedulesView, MainView (legacy), Settings
├── Info.plist
├── AgenticShortcuts.entitlements
│
├── Intents/                      # Siri / App Intents
│   ├── AppShortcuts.swift        # Siri phrase registration
│   └── CreateShortcutIntent.swift
│
├── Models/
│   ├── ShortcutProject.swift     # A generated shortcut (prompt, code, status)
│   ├── GenerationResult.swift    # Result of one generation attempt
│   └── Schedule.swift            # Schedule + ScheduleExtraction value types
│
├── Services/
│   ├── OllamaService.swift       # /api/chat client
│   ├── CherriCompiler.swift      # Shells out to the cherri binary
│   ├── ShortcutGenerator.swift   # Orchestrator: extract → generate → compile → retry
│   ├── CherriExamples.swift      # Curated working snippets (RAG corpus)
│   ├── ActionCatalog.swift       # Cherri actions + tokenizer/synonyms
│   └── ScheduleService.swift     # launchd plist install/uninstall
│
├── Views/                        # Legacy UI (opens via View → Open Legacy UI)
│   ├── MainView.swift
│   ├── PromptView.swift
│   ├── CodePreviewView.swift
│   ├── HistoryView.swift
│   ├── SchedulesView.swift       # also reused by the Preview UI
│   └── SettingsView.swift        # also reused by the Preview UI
│
├── PreviewUI/                    # New three-column UI (default)
│   ├── PreviewMainView.swift     # HSplitView / VSplitView shell + toolbar
│   ├── PreviewViewModel.swift    # @Observable state container; wraps ShortcutGenerator;
│   │                             # exposes signSelected / signAndOpen / signAndSaveAs
│   ├── PreviewSidebar.swift      # Nav + recent projects + Ollama status footer
│   ├── PreviewComponents.swift   # Cards, stepper, code block, compile-result card
│   ├── PreviewLogsPane.swift     # Messages / Raw Model Response tabs + error callout
│   └── PreviewInspector.swift    # Details / Logs tabs
│
└── Resources/
    ├── CherriLLMGuide.txt        # Full Cherri reference (system prompt)
    └── Assets.xcassets/

Tests/
├── fixtures.json                 # Prompt → required/forbidden substrings
└── run_fixtures.sh

project.yml                       # XcodeGen spec
AgenticShortcuts.xcodeproj/       # Generated from project.yml
CLAUDE.md                         # Architecture overview for Claude Code
RAG_STRUCTURE.md                  # Why the regex sanitizer was replaced by RAG + retry
README.md                         # This file
```

---

## How generation works

A user description flows through `ShortcutGenerator.generate(...)`:

### 1. `extractSchedule`

A small LLM call returns JSON describing any time component — *"every day at 7am for 10 days."* If found, the schedule words are stripped from the description before code generation. The Preview UI observes this via the **Extract Schedule** pipeline step.

### 2. `inferName` + `callModel` (in parallel)

A short title is inferred while the main code generation runs. The code call assembles a user prompt that includes:

- the description
- the top-3 most relevant `CherriExamples`
- a set of hard rules — *"every variable starts with `@`"*, *"no string concatenation, use interpolation"*, etc.

The system prompt is the entire `CherriLLMGuide.txt`.

### 3. Wrong-language smell test

If the response contains JavaScript or Python tells (`let`, `===`, `function(`, `def`, `print(`, trailing `;`), the generator immediately retries with a **WRONG LANGUAGE** hint before compiling.

### 4. `CherriCompiler.compile`

Writes the source to a temp dir, runs the `cherri` binary, and moves the resulting `.shortcut` to `~/Shortcuts`. The initial compile uses `--skip-sign` for speed; signing happens later via `signAndExport` when you click **Sign & Open** or **Save Signed File…**.

### 5. Compile-retry

On failure, the failed code plus the verbatim compiler error (and a translated repair hint when the error is recognizable) are fed back to the model for **exactly one** repair attempt. No further regex post-processing.

If both attempts fail, the code is surfaced in the UI for manual editing and **Recompile**. See [RAG_STRUCTURE.md](./RAG_STRUCTURE.md) for the design rationale.

---

## Signing & installing

The Compile Result card exposes three actions once a project compiles:

| Action | What it does |
|---|---|
| **Sign & Open in Shortcuts** | Re-runs `cherri` with signing enabled, overwrites the unsigned bundle at `~/Shortcuts/<name>.shortcut`, opens it in the Shortcuts app. If the prompt contained a schedule, the `launchd` plist is also installed. |
| **Save Signed File…** | Same sign step, then presents `NSSavePanel` so you can write the signed `.shortcut` anywhere on disk. |
| **Reveal in Finder** | Highlights the `.shortcut` bundle in Finder. |

Active schedules can be reviewed and removed from the **Schedules** pane (sidebar) or the standalone Schedules window.

---

## Setup

```bash
# 1. Verify dependencies
ollama list                 # confirm a supported model is present
cherri --version            # confirm v2.1.1+

# 2. Make sure Ollama is running
ollama serve                # or rely on the launchd service

# 3. (Re-)generate the Xcode project if you edited project.yml
xcodegen generate

# 4. Open and run
open AgenticShortcuts.xcodeproj
# Set the signing team in the target, then Build & Run.
```

### Build from the command line

```bash
xcodebuild -project AgenticShortcuts.xcodeproj \
           -scheme AgenticShortcuts \
           -configuration Debug build
```

---

## Testing

The `Tests/` directory holds prompt fixtures, not XCTest cases. Each fixture has a prompt and a list of substrings that must (or must not) appear in the generated code — a cheap regression check on the model + prompt + examples pipeline.

```bash
./Tests/run_fixtures.sh
```

---

## Settings

Open with **⌘,**. Lets you change:

- **Default model** — `mistral:7b`, `qwen2.5-coder:7b`, `qwen3:8b`, `qwen3.5:9b`
- **Ollama base URL** — default `http://localhost:11434`, with a Test Connection button
- **Cherri binary path** — default `/opt/homebrew/bin/cherri`
- **Skip-signing toggle** — currently informational; the Preview UI always produces an unsigned bundle on the initial compile and signs on demand via the Compile Result card
- **Apple Intelligence prompt-refinement toggle** — requires macOS Sequoia+

---

## Resources

- **Cherri language docs** — <https://cherrilang.org/>
- **Cherri on GitHub** — <https://github.com/electrikmilk/cherri>
- **Ollama API docs** — <https://github.com/ollama/ollama/blob/main/docs/api.md>
- **App Intents docs** — <https://developer.apple.com/documentation/appintents>

---

## License

Not yet specified. If you intend to share this publicly, add a `LICENSE` file (MIT and Apache-2.0 are common choices for permissive open source).
