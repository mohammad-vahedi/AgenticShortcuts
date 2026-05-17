# Agentic Shortcuts

A macOS app that lets users describe Apple Shortcuts in natural language — via Siri voice or a GUI — and get a ready-to-install signed .shortcut file back. Fully local: powered by Ollama + Cherri.

## Architecture

```
┌─────────────────────────────────────┐
│           User Input                │
│  ┌───────────┐  ┌────────────────┐  │
│  │ Siri Voice │  │ macOS Window   │  │
│  │ (⌘⌘ → speak)│  │ (text editor)  │  │
│  └─────┬─────┘  └───────┬────────┘  │
│        └──────┬──────────┘           │
│               ▼                      │
│     AppIntent / Direct Call          │
└───────────────┬─────────────────────┘
                ▼
┌─────────────────────────────────────┐
│        ShortcutGenerator Service    │
│  1. Send prompt + Cherri LLM guide  │
│     to Ollama (local, port 11434)   │
│  2. Receive generated .cherri code  │
│  3. Validate syntax                 │
│  4. Compile via `cherri` CLI        │
│  5. Return signed .shortcut file    │
└───────────────┬─────────────────────┘
                ▼
┌─────────────────────────────────────┐
│          Output                     │
│  • Open in Shortcuts app            │
│  • Siri dialog confirmation         │
│  • Save to ~/Shortcuts/             │
└─────────────────────────────────────┘
```

## Two Interfaces

1. **Siri (voice/quick)** — User double-taps ⌘, says "Create a shortcut that...", gets result via Siri dialog. Uses App Intents + App Shortcuts framework (macOS 14+).
2. **macOS window (visual)** — Browse history, preview/edit generated Cherri code, manage shortcuts, configure model selection. SwiftUI-based.

## Tech Stack

- **Language**: Swift 5.9+
- **UI**: SwiftUI (macOS 14+ Sonoma)
- **AI**: Ollama (local inference, REST API at http://localhost:11434)
- **Models available** (selectable in Settings):
  - `mistral:7b` — fast, excellent for code generation, lightweight (recommended for M-series Macs with 16GB RAM)
  - `qwen2.5-coder:7b` — optimized for code generation, balanced performance
  - `qwen3:8b` — general purpose, good for understanding intent
  - `qwen3.5:9b` — larger, higher quality reasoning (best overall, needs more resources)
- **Compiler**: Cherri CLI v2.1.1 (`/opt/homebrew/bin/cherri`)
- **Frameworks**: App Intents, AppKit (for system integration)
- **Minimum deployment**: macOS 14.0 (required for AppShortcutsProvider)

## Ollama API

Base URL: `http://localhost:11434`

Generate endpoint:
```bash
curl http://localhost:11434/api/generate -d '{
  "model": "qwen2.5-coder:7b",
  "prompt": "...",
  "system": "...",
  "stream": false
}'
```

Chat endpoint (preferred — supports system + user messages):
```bash
curl http://localhost:11434/api/chat -d '{
  "model": "qwen2.5-coder:7b",
  "messages": [
    {"role": "system", "content": "You are a Cherri code generator..."},
    {"role": "user", "content": "Create a shortcut that..."}
  ],
  "stream": false
}'
```

Response: `{ "message": { "content": "..." }, "done": true }`

## Key Resources

- Cherri docs: https://cherrilang.org/
- Cherri LLM guide (system prompt foundation): https://gist.github.com/charignon/6be70dfac22cb3a68bce8676f68f0560
- Cherri GitHub: https://github.com/electrikmilk/cherri
- Ollama API docs: https://github.com/ollama/ollama/blob/main/docs/api.md
- App Intents docs: https://developer.apple.com/documentation/appintents
- Cherri action categories: Accessibility, Apple Intelligence, Basic, Calendar, Contacts, Cryptography, Device, Documents, Images, Location, Math, Media, Music, Network, PDF, Photos, Scripting, Settings, Sharing, Shortcuts, Text, Translation, Web

## Cherri Quick Reference

```cherri
// Variables
@name = "value"
const pi = 3.14

// String interpolation
show("{name}")

// Control flow
if condition { } else { }
repeat 5 { }
for item in list { }

// Menus — use colon after item name, NOT curly braces
menu "Choose:" {
    item "Option 1":
        alert("Selected")
}

// Includes for action categories
#include 'actions/shortcuts'
#include 'actions/device'
#include 'actions/scripting'
```

Compile: `cherri file.cherri` (signed) or `cherri file.cherri --skip-sign` (dev)

## Project Structure

```
Agentic Shortcuts/
├── CLAUDE.md
├── AgenticShortcuts.xcodeproj
├── AgenticShortcuts/
│   ├── AgenticShortcutsApp.swift       # @main entry point
│   ├── Info.plist
│   │
│   ├── Intents/                        # Siri / App Intents
│   │   ├── CreateShortcutIntent.swift  # The core AppIntent
│   │   └── AppShortcuts.swift          # Phrase definitions for Siri
│   │
│   ├── Views/
│   │   ├── MainView.swift              # Primary window layout
│   │   ├── PromptView.swift            # Text input + generate button
│   │   ├── CodePreviewView.swift       # Shows generated Cherri code
│   │   ├── HistoryView.swift           # Past generations
│   │   └── SettingsView.swift          # Model selection, cherri path, preferences
│   │
│   ├── Models/
│   │   ├── ShortcutProject.swift       # A generated shortcut (prompt, code, status)
│   │   └── GenerationResult.swift      # Result of a generation attempt
│   │
│   ├── Services/
│   │   ├── OllamaService.swift         # Ollama REST API client
│   │   ├── CherriCompiler.swift        # Wraps `cherri` CLI execution
│   │   └── ShortcutGenerator.swift     # Orchestrates: prompt → code → compile
│   │
│   └── Resources/
│       ├── Assets.xcassets
│       └── CherriLLMGuide.txt          # The Cherri LLM guide (system prompt)
│
└── README.md
```

## Development Setup

1. **Xcode 15+** required (for macOS 14 SDK, App Intents)
2. **Cherri CLI**: already installed at `/opt/homebrew/bin/cherri` v2.1.1
3. **Ollama**: already installed v0.20.4 with qwen3:8b, qwen2.5-coder:7b, qwen3.5:9b
4. Open `.xcodeproj` in Xcode, set signing team, build & run

## Build & Run

```bash
# Verify tools
ollama list
cherri --version

# Ensure Ollama is running
ollama serve   # or it may already be running as a service

# Compile a shortcut (for testing)
cherri output.cherri              # signed
cherri output.cherri --skip-sign  # faster, for dev

# Build app from CLI (optional)
xcodebuild -project AgenticShortcuts.xcodeproj -scheme AgenticShortcuts -configuration Debug build
```

## Design Decisions

- **Ollama over cloud API**: Fully local, no API key, no costs, offline-capable, privacy-first
- **qwen2.5-coder:7b as default model**: Optimized for code generation; user can switch to qwen3:8b or qwen3.5:9b in settings
- **Cherri over shortcuts-js**: Active maintenance, broad action coverage, built-in signing, raw action escape hatch, proven LLM compatibility
- **macOS-only**: Cherri compiler requires macOS; keeps v1 scope tight
- **App Intents over SiriKit**: Modern framework, simpler API, supports App Shortcuts phrases
- **SwiftUI over AppKit**: Faster development, sufficient for this UI complexity
