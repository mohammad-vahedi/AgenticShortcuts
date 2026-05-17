import Foundation

/// One curated, working Cherri snippet. The corpus is retrieved by keyword
/// scoring against the user's prompt and the top-K examples are injected
/// directly into the LLM user message as concrete few-shot anchors.
struct CherriExample {
    let id: String
    let description: String
    let keywords: [String]
    let code: String
}

enum CherriExamples {

    /// Score each example against the user prompt and return the top-K matches.
    /// Reuses `ActionCatalog.tokenize` so synonym expansion ("fetch" → "download" etc.)
    /// is shared with action retrieval.
    static func relevant(for prompt: String, topK: Int = 3) -> [CherriExample] {
        let tokens = ActionCatalog.tokenize(prompt)
        let scored: [(CherriExample, Double)] = all.map { ($0, $0.score(for: tokens)) }
        return scored
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
    }

    static let all: [CherriExample] = [
        // ─── Output / interaction ───────────────────────────────────────────
        .init(
            id: "show_text",
            description: "Show plain text output.",
            keywords: ["show", "display", "print", "output", "text", "message"],
            code: #"show("Hello, world!")"#
        ),
        .init(
            id: "alert_dialog",
            description: "Show an alert dialog with title.",
            keywords: ["alert", "dialog", "popup", "warning", "title"],
            code: #"alert("Operation complete", "Status")"#
        ),
        .init(
            id: "notification",
            description: "Send a system notification.",
            keywords: ["notification", "notify", "banner", "remind", "push"],
            code: """
            #include 'actions/scripting'
            showNotification("Battery is low", "Warning", true)
            """
        ),
        .init(
            id: "prompt_input",
            description: "Ask user for text input and greet them.",
            keywords: ["ask", "prompt", "input", "user", "name", "type", "enter"],
            code: """
            #include 'actions/scripting'
            @name = prompt("What is your name?")
            alert("Hello, {name}!")
            """
        ),

        // ─── Web / fetch / extract (the high-value patterns) ────────────────
        .init(
            id: "fetch_webpage",
            description: "Fetch a webpage and show its readable contents.",
            keywords: ["fetch", "download", "get", "webpage", "website", "url", "http", "scrape", "content"],
            code: """
            #include 'actions/web'
            @page = getWebpageContents("https://example.com")
            show("{page}")
            """
        ),
        .init(
            id: "fetch_extract_between",
            description: "Fetch a webpage and extract the section between two literal markers using regex.",
            keywords: ["fetch", "download", "extract", "between", "regex", "match", "pattern", "scrape", "webpage", "website", "url", "section", "parse"],
            code: """
            #include 'actions/web'
            #include 'actions/text'
            @page = getWebpageContents("https://example.com/page")
            @matches = matchText("StartWord([\\\\s\\\\S]*?)EndWord", @page, false)
            @section = getMatchGroup(@matches, 1)
            show("{section}")
            """
        ),
        .init(
            id: "fetch_split_lines_random",
            description: "Fetch a section of a webpage, split it into lines, show a random one.",
            keywords: ["fetch", "split", "lines", "random", "pick", "choose", "menu", "scrape"],
            code: """
            #include 'actions/web'
            #include 'actions/text'
            #include 'actions/scripting'
            @page = getWebpageContents("https://example.com/menu")
            @matches = matchText("StartWord([\\\\s\\\\S]*?)EndWord", @page, false)
            @section = getMatchGroup(@matches, 1)
            @lines = splitText(@section, "\\n")
            @pick = getRandomItem(@lines)
            show("{pick}")
            """
        ),
        .init(
            id: "json_post",
            description: "Send a JSON POST request and show the response.",
            keywords: ["json", "post", "api", "request", "send", "submit", "rest", "endpoint"],
            code: """
            #include 'actions/web'
            @body = {"key": "value"}
            @response = jsonRequest("https://api.example.com/data", "POST", @body)
            show("{response}")
            """
        ),
        .init(
            id: "search_web",
            description: "Search the web with a query.",
            keywords: ["search", "web", "google", "duckduckgo", "find", "query"],
            code: """
            #include 'actions/web'
            searchWeb("DuckDuckGo", "Swift tutorials")
            """
        ),
        .init(
            id: "rss_feed",
            description: "Fetch an RSS feed.",
            keywords: ["rss", "feed", "news", "articles", "subscribe"],
            code: """
            #include 'actions/web'
            @items = getRSS(5, "https://example.com/feed.xml")
            show("{items}")
            """
        ),

        // ─── Text manipulation ──────────────────────────────────────────────
        .init(
            id: "regex_extract",
            description: "Extract a section between two markers from existing text.",
            keywords: ["extract", "between", "regex", "match", "pattern", "parse", "section"],
            code: """
            #include 'actions/text'
            @matches = matchText("Start([\\\\s\\\\S]*?)End", @text, false)
            @section = getMatchGroup(@matches, 1)
            show("{section}")
            """
        ),
        .init(
            id: "replace_text",
            description: "Replace one substring with another.",
            keywords: ["replace", "substitute", "swap", "change", "text"],
            code: """
            #include 'actions/text'
            @clean = replaceText("old", "new", @input, false, false)
            show("{clean}")
            """
        ),
        .init(
            id: "split_text",
            description: "Split text on a separator into a list.",
            keywords: ["split", "separator", "lines", "tokens", "divide"],
            code: """
            #include 'actions/text'
            @parts = splitText(@input, ",")
            for part in @parts {
                show("{part}")
            }
            """
        ),
        .init(
            id: "uppercase",
            description: "Convert text to uppercase.",
            keywords: ["uppercase", "upper", "case", "capital"],
            code: """
            #include 'actions/text'
            @upper = uppercase(@input)
            show("{upper}")
            """
        ),
        .init(
            id: "ocr_image",
            description: "Extract text from an image (OCR).",
            keywords: ["ocr", "image", "photo", "text", "extract", "scan", "read"],
            code: """
            #include 'actions/photos'
            #include 'actions/text'
            @photos = selectPhotos(false)
            @text = getTextFromImage(@photos)
            show("{text}")
            """
        ),

        // ─── Clipboard / sharing ────────────────────────────────────────────
        .init(
            id: "get_clipboard",
            description: "Read the clipboard and show it.",
            keywords: ["clipboard", "paste", "read", "copy", "current"],
            code: """
            #include 'actions/sharing'
            @clip = getClipboard()
            show("{clip}")
            """
        ),
        .init(
            id: "set_clipboard",
            description: "Copy a string to the clipboard.",
            keywords: ["clipboard", "copy", "paste", "set", "write"],
            code: """
            #include 'actions/sharing'
            setClipboard("Hello, world!")
            """
        ),
        .init(
            id: "send_message",
            description: "Send an iMessage/SMS to a contact.",
            keywords: ["send", "message", "sms", "imessage", "text", "chat"],
            code: """
            #include 'actions/sharing'
            sendMessage("Mom", "On my way!", false)
            """
        ),
        .init(
            id: "send_email",
            description: "Send an email.",
            keywords: ["send", "email", "mail", "subject", "body"],
            code: """
            #include 'actions/sharing'
            sendEmail("user@example.com", "me@example.com", "Hello", "Body text", false)
            """
        ),

        // ─── Device / settings ──────────────────────────────────────────────
        .init(
            id: "battery_level",
            description: "Get battery level.",
            keywords: ["battery", "charge", "level", "power"],
            code: """
            #include 'actions/device'
            @level = getBatteryLevel()
            alert("Battery: {level}%")
            """
        ),
        .init(
            id: "dark_mode_toggle",
            description: "Enable dark mode.",
            keywords: ["dark", "mode", "appearance", "night", "theme"],
            code: """
            #include 'actions/settings'
            darkMode()
            """
        ),
        .init(
            id: "set_volume",
            description: "Set system volume to half.",
            keywords: ["volume", "sound", "audio", "loud", "set"],
            code: """
            #include 'actions/settings'
            setVolume(0.5)
            """
        ),
        .init(
            id: "do_not_disturb",
            description: "Turn on Do Not Disturb.",
            keywords: ["dnd", "do", "not", "disturb", "focus", "silent"],
            code: """
            #include 'actions/settings'
            DNDOn()
            """
        ),
        .init(
            id: "lock_screen",
            description: "Lock the screen.",
            keywords: ["lock", "screen", "secure"],
            code: """
            #include 'actions/device'
            lockScreen()
            """
        ),

        // ─── Apps / shortcuts ───────────────────────────────────────────────
        .init(
            id: "open_app",
            description: "Open an app by bundle ID.",
            keywords: ["open", "launch", "start", "app", "application"],
            code: """
            #include 'actions/scripting'
            openApp("com.apple.podcasts")
            """
        ),
        .init(
            id: "menu_choice",
            description: "Show a menu of options and run the chosen action.",
            keywords: ["menu", "choose", "pick", "select", "options", "list"],
            code: """
            #include 'actions/scripting'
            menu "Choose app:" {
                item "Podcasts":
                    openApp("com.apple.podcasts")
                item "Music":
                    openApp("com.apple.Music")
            }
            """
        ),

        // ─── Date / time / calendar ─────────────────────────────────────────
        .init(
            id: "current_date_formatted",
            description: "Format and show the current date.",
            keywords: ["date", "time", "today", "now", "format", "current"],
            code: """
            #include 'actions/calendar'
            @today = currentDate()
            @formatted = formatDate(@today, "Long", "")
            alert("{formatted}")
            """
        ),
        .init(
            id: "start_timer",
            description: "Start a 5 minute timer.",
            keywords: ["timer", "countdown", "minute", "wait", "alarm"],
            code: """
            #include 'actions/calendar'
            startTimer(qty(5, "min"))
            """
        ),
        .init(
            id: "add_reminder",
            description: "Add a quick reminder.",
            keywords: ["reminder", "todo", "task"],
            code: """
            #include 'actions/calendar'
            addQuickReminder("Buy groceries")
            """
        ),

        // ─── Location / weather ─────────────────────────────────────────────
        .init(
            id: "current_weather",
            description: "Get current temperature and conditions.",
            keywords: ["weather", "temperature", "forecast", "rain", "condition"],
            code: """
            #include 'actions/location'
            @weather = getCurrentWeather("Current Location")
            @temp = getWeatherDetail(@weather, "Temperature")
            @cond = getWeatherDetail(@weather, "Condition")
            alert("{cond}, {temp}°")
            """
        ),
        .init(
            id: "current_location",
            description: "Get the current location.",
            keywords: ["location", "gps", "where", "address", "place"],
            code: """
            #include 'actions/location'
            @loc = getCurrentLocation()
            @city = getLocationDetail(@loc, "City")
            show("{city}")
            """
        ),

        // ─── Media ──────────────────────────────────────────────────────────
        .init(
            id: "screenshot",
            description: "Take a screenshot.",
            keywords: ["screenshot", "screen", "capture"],
            code: """
            #include 'actions/media'
            takeScreenshot(true)
            """
        ),
        .init(
            id: "speak_text",
            description: "Speak text aloud (TTS).",
            keywords: ["speak", "say", "voice", "tts", "audio", "read"],
            code: """
            #include 'actions/text'
            speak("Hello, world!", true)
            """
        ),

        // ─── Lists / control flow ───────────────────────────────────────────
        .init(
            id: "random_from_list",
            description: "Pick a random item from a list of strings.",
            keywords: ["random", "pick", "choose", "list", "items", "select"],
            code: """
            #include 'actions/scripting'
            @cities = ["New York", "Tokyo", "London", "Sydney"]
            @pick = getRandomItem(@cities)
            alert("Go to: {pick}")
            """
        ),
        .init(
            id: "repeat_n",
            description: "Repeat an action N times.",
            keywords: ["repeat", "loop", "times", "count"],
            code: """
            repeat 3 {
                show("count: {RepeatIndex}")
            }
            """
        ),
        .init(
            id: "for_each_item",
            description: "Loop over each item in a list.",
            keywords: ["for", "each", "loop", "iterate", "list"],
            code: """
            @items = ["a", "b", "c"]
            for item in @items {
                show("{item}")
            }
            """
        ),
        .init(
            id: "if_else",
            description: "Branch on a numeric condition.",
            keywords: ["if", "else", "condition", "branch", "check", "compare"],
            code: """
            #include 'actions/device'
            @level = getBatteryLevel()
            if @level < 20 {
                alert("Low battery")
            } else {
                alert("Battery OK")
            }
            """
        ),

        // ─── macOS shell ────────────────────────────────────────────────────
        .init(
            id: "shell_script",
            description: "Run a shell command on macOS.",
            keywords: ["shell", "bash", "terminal", "script", "command", "cli", "run"],
            code: """
            #include 'actions/mac'
            @output = runShellScript("echo Hello", "")
            show("{output}")
            """
        ),
    ]
}

// MARK: - Scoring

extension CherriExample {
    func score(for tokens: Set<String>) -> Double {
        var s = 0.0

        let kw = Set(keywords.map { $0.lowercased() })
        s += Double(tokens.intersection(kw).count) * 2.0

        let descTokens = Set(
            description.lowercased()
                .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                .filter { $0.count > 2 }
        )
        s += Double(tokens.intersection(descTokens).count) * 0.5

        return s
    }
}

// MARK: - Prompt rendering

extension CherriExample {
    var asPromptBlock: String {
        """
        // \(description)
        \(code)
        """
    }
}
