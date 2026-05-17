import Foundation

// One entry per Cherri action, sourced from https://github.com/electrikmilk/cherri/tree/main/actions
struct ActionEntry {
    let name: String
    let include: String?         // nil = no #include needed
    let signature: String
    let description: String
    let keywords: [String]
    let example: String?
}

// MARK: - Relevance scoring

extension ActionEntry {
    func score(for promptTokens: Set<String>) -> Double {
        var s = 0.0
        let nameLower = name.lowercased()

        // Exact name match in prompt is the strongest signal
        if promptTokens.contains(nameLower) { s += 5 }

        // Name word overlap (e.g. "open" in "openApp")
        let nameWords = tokenizeIdentifier(nameLower)
        s += Double(promptTokens.intersection(nameWords).count) * 2.5

        // Keyword overlap
        let kw = Set(keywords.map { $0.lowercased() })
        s += Double(promptTokens.intersection(kw).count) * 1.0

        // Description word overlap (weaker)
        let descWords = Set(description.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).filter { $0.count > 2 })
        s += Double(promptTokens.intersection(descWords).count) * 0.5

        return s
    }

    private func tokenizeIdentifier(_ id: String) -> Set<String> {
        // Split camelCase: "getWebpageContents" → ["get","webpage","contents"]
        var words: [String] = []
        var current = ""
        for ch in id {
            if ch.isUppercase && !current.isEmpty {
                words.append(current.lowercased())
                current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return Set(words)
    }
}

// MARK: - Catalog

enum ActionCatalog {

    static let all: [ActionEntry] = basic + scripting + text + web + sharing + settings + network + device + shortcuts + calendar + contacts + location + math + media + music + photos + images + documents + mac

    // Always include these regardless of score (foundational actions every shortcut might use)
    static let alwaysIncluded: [String] = [
        "show", "alert", "showNotification", "nothing", "stop", "output", "prompt"
    ]

    static func relevant(for prompt: String, topK: Int = 18) -> [ActionEntry] {
        let tokens = tokenize(prompt)
        let scored = all.map { ($0, $0.score(for: tokens)) }
        let sorted = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let top = Array(sorted.prefix(topK).map { $0.0 })

        // Always inject foundational actions not already in top
        let topNames = Set(top.map { $0.name })
        let extras = all.filter { alwaysIncluded.contains($0.name) && !topNames.contains($0.name) }

        return extras + top
    }

    static func tokenize(_ text: String) -> Set<String> {
        // Expand synonyms so "fetch" also matches "download" etc.
        let raw = text.lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { $0.count > 2 }
        var expanded = Set(raw)
        for word in raw {
            if let syns = synonyms[word] { expanded.formUnion(syns) }
        }
        return expanded
    }

    // Domain synonym map — expand user words to Cherri vocabulary
    static let synonyms: [String: [String]] = [
        "fetch":      ["download", "get", "retrieve", "load", "read", "request"],
        "download":   ["fetch", "get", "retrieve", "load", "request"],
        "get":        ["fetch", "download", "retrieve", "read", "obtain"],
        "read":       ["fetch", "get", "load", "open", "retrieve"],
        "open":       ["launch", "start", "run", "show", "display"],
        "launch":     ["open", "start", "run"],
        "start":      ["open", "launch", "begin", "run"],
        "show":       ["display", "alert", "notify", "print", "output"],
        "display":    ["show", "alert", "notify", "print"],
        "print":      ["show", "display", "output"],
        "send":       ["post", "submit", "share", "message", "email", "notify"],
        "post":       ["send", "submit", "request"],
        "search":     ["find", "look", "query", "filter", "seek"],
        "find":       ["search", "look", "query", "detect", "match"],
        "extract":    ["parse", "match", "find", "get", "pull", "retrieve"],
        "parse":      ["extract", "match", "find", "read"],
        "split":      ["divide", "separate", "chunk", "break"],
        "join":       ["combine", "merge", "concatenate", "glue"],
        "random":     ["pick", "choose", "select", "shuffle", "randomize"],
        "pick":       ["random", "choose", "select"],
        "choose":     ["pick", "random", "select"],
        "copy":       ["clipboard", "paste"],
        "paste":      ["clipboard", "copy"],
        "clipboard":  ["copy", "paste"],
        "notify":     ["notification", "alert", "show", "message"],
        "message":    ["send", "sms", "imessage", "text", "chat"],
        "email":      ["send", "mail", "smtp"],
        "weather":    ["temperature", "forecast", "rain", "cloud", "wind", "humidity"],
        "photo":      ["image", "picture", "camera", "screenshot"],
        "image":      ["photo", "picture", "screenshot", "graphic"],
        "music":      ["song", "audio", "playlist", "track", "play", "podcast"],
        "play":       ["music", "audio", "song", "podcast", "media"],
        "date":       ["time", "calendar", "today", "now", "schedule"],
        "time":       ["date", "clock", "hour", "minute", "schedule"],
        "alarm":      ["timer", "reminder", "clock", "wake"],
        "timer":      ["alarm", "countdown", "wait"],
        "file":       ["document", "folder", "save", "read", "write"],
        "save":       ["write", "store", "file", "export"],
        "location":   ["gps", "map", "coordinates", "address", "place", "where"],
        "map":        ["location", "directions", "address", "navigate"],
        "contact":    ["phone", "call", "person", "address"],
        "call":       ["phone", "facetime", "contact", "dial"],
        "battery":    ["charge", "power", "level"],
        "brightness": ["screen", "display", "dim"],
        "volume":     ["sound", "audio", "mute"],
        "wifi":       ["network", "internet", "connection", "wireless"],
        "dark":       ["night", "mode", "appearance", "theme"],
        "light":      ["day", "mode", "appearance", "theme"],
        "regex":      ["pattern", "match", "expression", "extract"],
        "url":        ["link", "web", "http", "website", "address"],
        "website":    ["url", "link", "web", "page", "site"],
        "webpage":    ["url", "website", "html", "page", "content"],
        "request":    ["http", "api", "fetch", "post", "get"],
        "api":        ["request", "http", "json", "rest"],
        "json":       ["api", "request", "data", "response"],
        "convert":    ["transform", "encode", "decode", "change", "format"],
        "encode":     ["convert", "url", "base64", "format"],
        "decode":     ["convert", "url", "base64", "parse"],
        "dict":       ["dictionary", "key", "value", "json", "object"],
        "dictionary": ["dict", "key", "value", "json", "object"],
        "list":       ["array", "items", "collection"],
        "array":      ["list", "items", "collection"],
        "shell":      ["terminal", "bash", "script", "command", "cli"],
        "script":     ["shell", "bash", "run", "execute", "command"],
        "screenshot": ["screen", "capture", "photo", "image"],
        "notification": ["alert", "notify", "show", "push"],
        "qr":         ["barcode", "code", "scan"],
        "podcast":    ["audio", "show", "episode", "subscribe"],
        "rss":        ["feed", "news", "articles", "subscribe"],
        "translate":  ["language", "foreign", "convert"],
        "speak":      ["voice", "tts", "audio", "say"],
        "dictate":    ["voice", "speech", "listen", "transcribe"],
        "shortcut":   ["automation", "run", "workflow"],
        "note":       ["notes", "write", "save", "document"],
        "calendar":   ["event", "meeting", "date", "schedule", "appointment"],
        "reminder":   ["task", "todo", "alarm", "calendar"],
        "countdown":  ["timer", "wait", "seconds"],
        "resize":     ["image", "scale", "width", "height"],
        "crop":       ["image", "trim", "cut"],
    ]
}

// MARK: - Action definitions

extension ActionCatalog {

    // MARK: Basic (no include)
    static let basic: [ActionEntry] = [
        .init(name: "show", include: nil, signature: "show(text input)", description: "Display text as output.", keywords: ["show","display","print","output","text","result"], example: #"show("Hello!")"#),
        .init(name: "alert", include: nil, signature: "alert(text message, text ?title)", description: "Show an alert dialog with a message and optional title.", keywords: ["alert","popup","dialog","message","notify","warn","show"], example: #"alert("Done!", "Status")"#),
        .init(name: "confirm", include: nil, signature: "confirm(text message, text ?title)", description: "Alert with OK and Cancel buttons. Cancel stops the shortcut.", keywords: ["confirm","ask","dialog","cancel","yes","no"], example: #"confirm("Are you sure?", "Confirm")"#),
        .init(name: "showNotification", include: nil, signature: "showNotification(text body, text ?title, bool ?playSound)", description: "Show a system notification banner.", keywords: ["notification","notify","banner","push","alert","remind","show"], example: #"showNotification("Battery low", "Warning")"#),
        .init(name: "prompt", include: nil, signature: "prompt(text question): text", description: "Ask the user to enter text input.", keywords: ["ask","input","user","enter","type","prompt","question","text"], example: #"@name = prompt("What is your name?")"#),
        .init(name: "output", include: nil, signature: "output(text value)", description: "Stop and output a value from the shortcut.", keywords: ["output","return","result","value","done","finish"], example: nil),
        .init(name: "nothing", include: nil, signature: "nothing()", description: "Clear the current output.", keywords: ["nothing","clear","empty","discard"], example: nil),
        .init(name: "stop", include: nil, signature: "stop()", description: "Stop the shortcut.", keywords: ["stop","exit","quit","end","terminate"], example: nil),
        .init(name: "count", include: nil, signature: "count(variable input, ?type): number", description: "Count items, characters, words, lines in input.", keywords: ["count","length","size","number","items","characters","words","lines","how many"], example: "@n = count(@list)"),
        .init(name: "wait", include: nil, signature: "wait(number seconds)", description: "Wait a number of seconds.", keywords: ["wait","pause","delay","sleep","seconds"], example: "wait(3)"),
        .init(name: "typeOf", include: nil, signature: "typeOf(variable input): text", description: "Get the type of a variable.", keywords: ["type","kind","class","check"], example: nil),
        .init(name: "quicklook", include: nil, signature: "quicklook(variable input)", description: "Preview input in Quick Look.", keywords: ["preview","quicklook","view","open","show"], example: nil),
    ]

    // MARK: Scripting
    static let scripting: [ActionEntry] = [
        .init(name: "openApp", include: "actions/scripting", signature: #"openApp(text bundleID)"#, description: "Open an app by its bundle ID.", keywords: ["open","launch","start","app","application","run"], example: #"openApp("com.apple.podcasts")"#),
        .init(name: "quitApp", include: "actions/scripting", signature: #"quitApp(text bundleID)"#, description: "Quit an app by its bundle ID.", keywords: ["quit","close","stop","app","kill","exit"], example: nil),
        .init(name: "getDictionary", include: "actions/scripting", signature: "getDictionary(variable input): dictionary", description: "Extract a dictionary from input.", keywords: ["dictionary","dict","json","object","parse","extract"], example: nil),
        .init(name: "getKeys", include: "actions/scripting", signature: "getKeys(dictionary): array", description: "Get all keys from a dictionary.", keywords: ["keys","dictionary","dict","list","fields"], example: nil),
        .init(name: "getValues", include: "actions/scripting", signature: "getValues(dictionary): array", description: "Get all values from a dictionary.", keywords: ["values","dictionary","dict","list"], example: nil),
        .init(name: "getValue", include: "actions/scripting", signature: "getValue(dictionary, text key)", description: "Get a value from a dictionary by key.", keywords: ["get","value","key","dictionary","dict","field","access","property"], example: #"@v = getValue(@dict, "name")"#),
        .init(name: "setValue", include: "actions/scripting", signature: "setValue(variable dict, text key, text value): dictionary", description: "Set a value in a dictionary.", keywords: ["set","value","key","dictionary","dict","update","store"], example: nil),
        .init(name: "chooseFromList", include: "actions/scripting", signature: "chooseFromList(variable list, ?prompt, ?selectMultiple)", description: "Show a list and let the user choose an item.", keywords: ["choose","pick","select","list","prompt","user","menu","option"], example: nil),
        .init(name: "getFirstItem", include: "actions/scripting", signature: "getFirstItem(variable list)", description: "Get the first item from a list.", keywords: ["first","item","list","top","head"], example: nil),
        .init(name: "getLastItem", include: "actions/scripting", signature: "getLastItem(variable list)", description: "Get the last item from a list.", keywords: ["last","item","list","end","tail"], example: nil),
        .init(name: "getListItem", include: "actions/scripting", signature: "getListItem(variable list, number index)", description: "Get item at a specific index from a list (index starts at 1).", keywords: ["item","index","list","get","nth","position","at"], example: "@item = getListItem(@list, 1)"),
        .init(name: "getListItems", include: "actions/scripting", signature: "getListItems(variable list, number start, number end): array", description: "Get a range of items from a list.", keywords: ["items","range","list","slice","from","to"], example: nil),
        .init(name: "getRandomItem", include: "actions/scripting", signature: "getRandomItem(variable list)", description: "Get a random item from a list.", keywords: ["random","pick","choose","item","list","shuffle","select","randomize"], example: "@pick = getRandomItem(@cities)"),
        .init(name: "randomNumber", include: "actions/scripting", signature: "randomNumber(number min, number max): number", description: "Generate a random number between min and max.", keywords: ["random","number","generate","between","range","int","integer"], example: "@n = randomNumber(1, 10)"),
        .init(name: "formatNumber", include: "actions/scripting", signature: "formatNumber(number, ?decimalPlaces): number", description: "Format a number to a given number of decimal places.", keywords: ["format","number","decimal","round","places"], example: nil),
        .init(name: "getName", include: "actions/scripting", signature: "getName(variable item)", description: "Get the name of an item.", keywords: ["name","title","label","file"], example: nil),
        .init(name: "setName", include: "actions/scripting", signature: "setName(variable item, text name)", description: "Set the name of an item.", keywords: ["name","rename","title","label","file"], example: nil),
        .init(name: "dismissSiri", include: "actions/scripting", signature: "dismissSiri()", description: "Dismiss Siri.", keywords: ["siri","dismiss","close"], example: nil),
    ]

    // MARK: Text
    static let text: [ActionEntry] = [
        .init(name: "matchText", include: "actions/text", signature: "matchText(text regex, text subject, ?caseSensitive)", description: "Use a regular expression to match or extract text.", keywords: ["match","regex","pattern","extract","find","search","text","parse","regular","expression","between"], example: #"@m = matchText("Start([\\s\\S]*?)End", @text, false)"#),
        .init(name: "getMatchGroup", include: "actions/text", signature: "getMatchGroup(variable matches, number index)", description: "Get a specific capture group from regex match results. Index 1 is the first group.", keywords: ["match","group","capture","regex","extract","index"], example: "@result = getMatchGroup(@matches, 1)"),
        .init(name: "getMatchGroups", include: "actions/text", signature: "getMatchGroups(variable matches)", description: "Get all capture groups from regex match results.", keywords: ["match","groups","capture","regex","all","extract"], example: nil),
        .init(name: "replaceText", include: "actions/text", signature: "replaceText(text find, text replace, text subject, ?caseSensitive, ?regExp): text", description: "Replace text within a string, optionally using regex.", keywords: ["replace","substitute","swap","text","find","regex","change"], example: #"@out = replaceText("old", "new", @text)"#),
        .init(name: "splitText", include: "actions/text", signature: "splitText(text, text separator): array", description: "Split text into a list using a separator.", keywords: ["split","divide","separate","lines","newline","delimiter","text","array","list"], example: #"@lines = splitText(@content, "\n")"#),
        .init(name: "joinText", include: "actions/text", signature: "joinText(variable list, text ?glue): text", description: "Join a list into a single string with an optional separator.", keywords: ["join","combine","merge","glue","text","list","concat","concatenate"], example: #"@out = joinText(@lines, ", ")"#),
        .init(name: "trimWhitespace", include: "actions/text", signature: "trimWhitespace(text): text", description: "Remove leading and trailing whitespace.", keywords: ["trim","whitespace","space","clean","strip"], example: nil),
        .init(name: "containsText", include: "actions/text", signature: "containsText(text subject, text search): bool", description: "Check whether text contains a substring.", keywords: ["contains","has","includes","find","search","check","text","substring"], example: nil),
        .init(name: "uppercase", include: "actions/text", signature: "uppercase(text): text", description: "Convert text to uppercase.", keywords: ["uppercase","upper","caps","text","convert"], example: nil),
        .init(name: "lowercase", include: "actions/text", signature: "lowercase(text): text", description: "Convert text to lowercase.", keywords: ["lowercase","lower","text","convert"], example: nil),
        .init(name: "capitalize", include: "actions/text", signature: "capitalize(text): text", description: "Capitalize the first letter of each sentence.", keywords: ["capitalize","title","text","format"], example: nil),
        .init(name: "titleCase", include: "actions/text", signature: "titleCase(text): text", description: "Capitalize every word.", keywords: ["title","case","capitalize","word","text"], example: nil),
        .init(name: "correctSpelling", include: "actions/text", signature: "correctSpelling(text): text", description: "Auto-correct spelling in text.", keywords: ["spell","spelling","correct","autocorrect","fix"], example: nil),
        .init(name: "getText", include: "actions/text", signature: "getText(variable input): text", description: "Extract text content from any input.", keywords: ["get","text","extract","convert","content"], example: nil),
        .init(name: "define", include: "actions/text", signature: "define(text word): text", description: "Look up the definition of a word.", keywords: ["define","definition","dictionary","word","meaning","lookup"], example: nil),
        .init(name: "speak", include: "actions/text", signature: "speak(text, ?waitUntilFinished)", description: "Speak text out loud using text-to-speech.", keywords: ["speak","say","voice","tts","speech","audio","read"], example: nil),
        .init(name: "listen", include: "actions/text", signature: "listen(): text", description: "Transcribe the user's speech to text.", keywords: ["listen","speech","voice","dictate","transcribe","microphone","siri"], example: nil),
        .init(name: "transcribeText", include: "actions/text", signature: "transcribeText(variable audio): text", description: "Transcribe an audio file to text.", keywords: ["transcribe","audio","speech","text","convert","voice","file"], example: nil),
        .init(name: "getTextFromImage", include: "actions/text", signature: "getTextFromImage(variable image): text", description: "Extract text from an image using OCR.", keywords: ["ocr","image","photo","text","extract","scan","read"], example: nil),
        .init(name: "makeHTML", include: "actions/text", signature: "makeHTML(text, ?fullDocument): text", description: "Convert rich text to HTML.", keywords: ["html","rich","text","convert","markup"], example: nil),
        .init(name: "makeMarkdown", include: "actions/text", signature: "makeMarkdown(text richText): text", description: "Convert rich text to Markdown.", keywords: ["markdown","rich","text","convert","md"], example: nil),
        .init(name: "getRichTextFromMarkdown", include: "actions/text", signature: "getRichTextFromMarkdown(text): text", description: "Convert Markdown to rich text.", keywords: ["markdown","rich","text","convert","md"], example: nil),
    ]

    // MARK: Web
    static let web: [ActionEntry] = [
        .init(name: "getWebpageContents", include: "actions/web", signature: "getWebpageContents(text url)", description: "Fetch the readable text content of a webpage (GET request).", keywords: ["fetch","get","webpage","website","url","content","html","read","web","page","site","http","download","retrieve","scrape","load"], example: #"@html = getWebpageContents("https://example.com")"#),
        .init(name: "downloadURL", include: "actions/web", signature: "downloadURL(text url, ?headers)", description: "Download raw data from a URL (GET request).", keywords: ["download","get","fetch","url","raw","data","binary","http","request","retrieve"], example: #"@data = downloadURL("https://api.example.com/data")"#),
        .init(name: "jsonRequest", include: "actions/web", signature: #"jsonRequest(text url, method, ?body, ?headers)"#, description: "Send a JSON HTTP request. Method must be POST, PUT, PATCH, or DELETE.", keywords: ["json","post","put","patch","delete","request","api","http","send","submit"], example: #"@res = jsonRequest("https://api.example.com", "POST", {"key": "value"})"#),
        .init(name: "formRequest", include: "actions/web", signature: "formRequest(text url, method, ?body, ?headers)", description: "Send a form-encoded HTTP request.", keywords: ["form","post","request","http","submit","data"], example: nil),
        .init(name: "openURL", include: "actions/web", signature: "openURL(text url)", description: "Open a URL in the default browser.", keywords: ["open","url","browser","link","safari","navigate","visit"], example: #"openURL("https://example.com")"#),
        .init(name: "showWebpage", include: "actions/web", signature: "showWebpage(text url, ?useReader)", description: "Show a webpage inside the app using Safari.", keywords: ["show","webpage","safari","browser","url","display","view"], example: nil),
        .init(name: "searchWeb", include: "actions/web", signature: #"searchWeb(engine, text query)"#, description: "Search the web using Google, Bing, DuckDuckGo, YouTube, etc.", keywords: ["search","web","google","bing","duckduckgo","youtube","query","find","lookup"], example: #"searchWeb("Google", "Swift tutorials")"#),
        .init(name: "getRSS", include: "actions/web", signature: "getRSS(number count, text url)", description: "Fetch items from an RSS feed.", keywords: ["rss","feed","news","articles","blog","subscribe","xml"], example: nil),
        .init(name: "getArticle", include: "actions/web", signature: "getArticle(text url)", description: "Extract a readable article from a webpage URL.", keywords: ["article","read","webpage","text","extract","content","news"], example: nil),
        .init(name: "getArticleDetail", include: "actions/web", signature: "getArticleDetail(variable article, text detail)", description: "Get a detail from an article (Title, Body, Author, etc.).", keywords: ["article","detail","title","body","author","content"], example: nil),
        .init(name: "urlEncode", include: "actions/web", signature: "urlEncode(text): text", description: "URL-encode a string for use in a URL.", keywords: ["encode","url","percent","escape","query","string"], example: nil),
        .init(name: "urlDecode", include: "actions/web", signature: "urlDecode(text): text", description: "Decode a URL-encoded string.", keywords: ["decode","url","percent","unescape","string"], example: nil),
        .init(name: "expandURL", include: "actions/web", signature: "expandURL(text url)", description: "Expand a shortened URL to its full destination.", keywords: ["expand","url","short","redirect","follow","link"], example: nil),
        .init(name: "getURLDetail", include: "actions/web", signature: "getURLDetail(text url, detail)", description: "Extract a component from a URL: Scheme, Host, Path, Query, etc.", keywords: ["url","detail","component","host","path","scheme","query","parse","extract"], example: nil),
        .init(name: "getURLs", include: "actions/web", signature: "getURLs(text input): array", description: "Extract all URLs from text.", keywords: ["urls","links","extract","find","text","detect"], example: nil),
        .init(name: "runJavaScriptOnWebpage", include: "actions/web", signature: "runJavaScriptOnWebpage(text js)", description: "Execute JavaScript on the current Safari webpage.", keywords: ["javascript","js","run","execute","safari","browser","script","webpage"], example: nil),
        .init(name: "getGifs", include: "actions/web", signature: "getGifs(text query, ?count)", description: "Search Giphy for GIFs.", keywords: ["gif","giphy","search","image","animation"], example: nil),
    ]

    // MARK: Sharing
    static let sharing: [ActionEntry] = [
        .init(name: "getClipboard", include: "actions/sharing", signature: "getClipboard()", description: "Get the current contents of the clipboard.", keywords: ["clipboard","copy","paste","get","content"], example: "@clip = getClipboard()"),
        .init(name: "setClipboard", include: "actions/sharing", signature: "setClipboard(variable value, ?local)", description: "Copy a value to the clipboard.", keywords: ["clipboard","copy","set","paste","save"], example: #"setClipboard("Hello!")"#),
        .init(name: "sendMessage", include: "actions/sharing", signature: "sendMessage(variable contact, text message, ?prompt)", description: "Send an SMS or iMessage to a contact.", keywords: ["message","sms","imessage","send","text","chat","contact"], example: #"sendMessage("Mom", "On my way!")"#),
        .init(name: "sendEmail", include: "actions/sharing", signature: "sendEmail(variable contact, text from, text subject, text body, ?prompt)", description: "Send an email to a contact.", keywords: ["email","send","mail","message","subject","body"], example: nil),
        .init(name: "share", include: "actions/sharing", signature: "share(variable input)", description: "Open the system share sheet for any input.", keywords: ["share","export","airdrop","send","save"], example: nil),
        .init(name: "airdrop", include: "actions/sharing", signature: "airdrop(variable input)", description: "Share content via AirDrop.", keywords: ["airdrop","share","send","transfer","nearby"], example: nil),
        .init(name: "findEmail", include: "actions/sharing", signature: "findEmail(text search)", description: "Search for emails in the Mail app.", keywords: ["email","find","search","mail","inbox"], example: nil),
        .init(name: "findMessage", include: "actions/sharing", signature: "findMessage(text search)", description: "Search for messages in the Messages app.", keywords: ["message","find","search","sms","imessage","chat"], example: nil),
    ]

    // MARK: Settings
    static let settings: [ActionEntry] = [
        .init(name: "darkMode", include: "actions/settings", signature: "darkMode()", description: "Switch the device to dark appearance.", keywords: ["dark","mode","appearance","theme","night","display"], example: "darkMode()"),
        .init(name: "lightMode", include: "actions/settings", signature: "lightMode()", description: "Switch the device to light appearance.", keywords: ["light","mode","appearance","theme","day","display"], example: nil),
        .init(name: "setBrightness", include: "actions/settings", signature: "setBrightness(float 0.0-1.0)", description: "Set screen brightness. 0.0 = off, 1.0 = full.", keywords: ["brightness","screen","display","dim","bright","light"], example: "setBrightness(0.5)"),
        .init(name: "setVolume", include: "actions/settings", signature: "setVolume(float 0.0-1.0)", description: "Set device volume. 0.0 = mute, 1.0 = max.", keywords: ["volume","sound","audio","mute","loud","quiet"], example: "setVolume(0.5)"),
        .init(name: "DNDOn", include: "actions/settings", signature: "DNDOn()", description: "Enable Do Not Disturb focus mode.", keywords: ["dnd","do not disturb","focus","quiet","silence","notification"], example: nil),
        .init(name: "DNDOff", include: "actions/settings", signature: "DNDOff()", description: "Disable Do Not Disturb focus mode.", keywords: ["dnd","do not disturb","focus","off","disable"], example: nil),
        .init(name: "toggleDND", include: "actions/settings", signature: "toggleDND()", description: "Toggle Do Not Disturb on/off.", keywords: ["dnd","do not disturb","focus","toggle"], example: nil),
        .init(name: "getFocusMode", include: "actions/settings", signature: "getFocusMode()", description: "Get the current focus mode.", keywords: ["focus","mode","dnd","status","current"], example: nil),
        .init(name: "setWallpaper", include: "actions/settings", signature: "setWallpaper(variable input)", description: "Set the device wallpaper.", keywords: ["wallpaper","background","desktop","image","photo"], example: nil),
    ]

    // MARK: Network
    static let network: [ActionEntry] = [
        .init(name: "getExternalIP", include: "actions/network", signature: "getExternalIP(?type): text", description: "Get the device's external/public IP address.", keywords: ["ip","address","external","public","internet","network"], example: nil),
        .init(name: "getLocalIP", include: "actions/network", signature: "getLocalIP(?type): text", description: "Get the device's local IP address on the network.", keywords: ["ip","address","local","private","network","wifi"], example: nil),
        .init(name: "isOnline", include: "actions/network", signature: "isOnline()", description: "Check whether the device has internet connectivity.", keywords: ["online","internet","connected","network","check","wifi"], example: nil),
        .init(name: "getWifiDetail", include: "actions/network", signature: "getWifiDetail(detail)", description: "Get details about the current Wi-Fi network (name, RSSI, etc.).", keywords: ["wifi","network","detail","name","ssid","signal","bssid"], example: nil),
        .init(name: "runSSHScript", include: "actions/network", signature: "runSSHScript(text script, variable input, text host, text port, text user, authType, text password)", description: "Run a script on a remote server via SSH.", keywords: ["ssh","remote","server","script","run","execute","terminal"], example: nil),
    ]

    // MARK: Device
    static let device: [ActionEntry] = [
        .init(name: "getBatteryLevel", include: "actions/device", signature: "getBatteryLevel()", description: "Get the current battery percentage.", keywords: ["battery","level","charge","power","percent"], example: "@level = getBatteryLevel()"),
        .init(name: "connectedToCharger", include: "actions/device", signature: "connectedToCharger(): bool", description: "Check if the device is connected to a charger.", keywords: ["charger","charging","connected","power","plugged"], example: nil),
        .init(name: "isCharging", include: "actions/device", signature: "isCharging(): bool", description: "Check if the device is currently charging.", keywords: ["charging","battery","power","charger","status"], example: nil),
        .init(name: "getDeviceDetail", include: "actions/device", signature: #"getDeviceDetail(detail)"#, description: "Get device info: name, model, system version, screen size, volume, brightness, appearance.", keywords: ["device","detail","name","model","version","screen","width","height","volume","brightness","appearance"], example: #"@name = getDeviceDetail("Device Name")"#),
        .init(name: "lockScreen", include: "actions/device", signature: "lockScreen()", description: "Lock the device screen.", keywords: ["lock","screen","sleep","power","security"], example: nil),
        .init(name: "reboot", include: "actions/device", signature: "reboot()", description: "Restart the device.", keywords: ["reboot","restart","reset","power"], example: nil),
        .init(name: "shutdown", include: "actions/device", signature: "shutdown()", description: "Shut down the device.", keywords: ["shutdown","power off","turn off","stop"], example: nil),
        .init(name: "getOrientation", include: "actions/device", signature: "getOrientation(): text", description: "Get the device's current screen orientation.", keywords: ["orientation","portrait","landscape","screen","rotate"], example: nil),
    ]

    // MARK: Shortcuts
    static let shortcuts: [ActionEntry] = [
        .init(name: "run", include: "actions/shortcuts", signature: "run(text name, variable input)", description: "Run another shortcut by name.", keywords: ["run","shortcut","execute","call","invoke","automation"], example: #"run("My Shortcut", "")"#),
        .init(name: "getShortcuts", include: "actions/shortcuts", signature: "getShortcuts(): array", description: "Get a list of all shortcuts on the device.", keywords: ["shortcuts","list","all","get","automation"], example: nil),
        .init(name: "makeShortcut", include: "actions/shortcuts", signature: "makeShortcut(text name, ?open)", description: "Create a new shortcut.", keywords: ["create","make","new","shortcut","automation"], example: nil),
        .init(name: "searchShortcuts", include: "actions/shortcuts", signature: "searchShortcuts(text query)", description: "Search for shortcuts by name.", keywords: ["search","find","shortcuts","query","look"], example: nil),
    ]

    // MARK: Calendar
    static let calendar: [ActionEntry] = [
        .init(name: "currentDate", include: "actions/calendar", signature: "currentDate()", description: "Get the current date and time.", keywords: ["date","time","today","now","current","clock"], example: "@today = currentDate()"),
        .init(name: "formatDate", include: "actions/calendar", signature: #"formatDate(text date, ?format, ?custom)"#, description: "Format a date. Formats: Short, Medium, Long, Relative, ISO 8601, RFC 2822, Custom.", keywords: ["format","date","time","display","string","iso","convert"], example: #"@s = formatDate(@today, "Long")"#),
        .init(name: "formatTime", include: "actions/calendar", signature: "formatTime(text, ?format)", description: "Format only the time portion of a date.", keywords: ["format","time","hour","minute","display","string"], example: nil),
        .init(name: "adjustDate", include: "actions/calendar", signature: "adjustDate(text date, operation, #unit)", description: "Add or subtract time from a date. Operations: Add, Subtract, Get Start of Day/Week/Month/Year.", keywords: ["adjust","add","subtract","date","time","days","weeks","months","years","offset","future","past","next","ago"], example: #"@next = adjustDate(@today, "Add", 7 days)"#),
        .init(name: "getDates", include: "actions/calendar", signature: "getDates(variable input): array", description: "Extract date values from text or other input.", keywords: ["extract","find","dates","parse","text"], example: nil),
        .init(name: "startTimer", include: "actions/calendar", signature: "startTimer(#duration)", description: "Start a countdown timer.", keywords: ["timer","countdown","start","minutes","seconds","alarm"], example: "startTimer(qty(5, \"min\"))"),
        .init(name: "getAlarms", include: "actions/calendar", signature: "getAlarms()", description: "Get all alarms on the device.", keywords: ["alarm","wake","clock","list","get"], example: nil),
        .init(name: "addCalendar", include: "actions/calendar", signature: "addCalendar(text name)", description: "Create a new calendar.", keywords: ["calendar","create","add","new"], example: nil),
        .init(name: "getEventDetail", include: "actions/calendar", signature: "getEventDetail(variable event, detail)", description: "Get a detail from a calendar event.", keywords: ["event","calendar","detail","date","time","location","title"], example: nil),
        .init(name: "addQuickReminder", include: "actions/calendar", signature: "addQuickReminder()", description: "Add a quick reminder.", keywords: ["reminder","add","quick","todo","task"], example: nil),
    ]

    // MARK: Contacts
    static let contacts: [ActionEntry] = [
        .init(name: "selectContact", include: "actions/contacts", signature: "selectContact(?multiple)", description: "Prompt the user to select a contact.", keywords: ["contact","select","pick","person","choose"], example: nil),
        .init(name: "getContacts", include: "actions/contacts", signature: "getContacts(variable input): array", description: "Find contacts matching the input.", keywords: ["contact","find","search","get","people"], example: nil),
        .init(name: "getContactDetail", include: "actions/contacts", signature: "getContactDetail(variable contact, detail)", description: "Get a detail from a contact (name, phone, email, etc.).", keywords: ["contact","detail","name","phone","email","address","birthday"], example: nil),
        .init(name: "call", include: "actions/contacts", signature: "call(variable contact)", description: "Call a contact.", keywords: ["call","phone","dial","contact","ring"], example: nil),
        .init(name: "facetimeCall", include: "actions/contacts", signature: "facetimeCall(variable contact, ?type)", description: "Start a FaceTime call with a contact.", keywords: ["facetime","call","video","audio","contact"], example: nil),
        .init(name: "getPhoneNumbers", include: "actions/contacts", signature: "getPhoneNumbers(variable): array", description: "Extract phone numbers from input.", keywords: ["phone","number","contact","extract","find"], example: nil),
        .init(name: "getEmails", include: "actions/contacts", signature: "getEmails(text): array", description: "Extract email addresses from input.", keywords: ["email","address","contact","extract","find"], example: nil),
    ]

    // MARK: Location
    static let location: [ActionEntry] = [
        .init(name: "getCurrentLocation", include: "actions/location", signature: "getCurrentLocation()", description: "Get the user's current GPS location.", keywords: ["location","gps","current","where","coordinates","position","here"], example: "@loc = getCurrentLocation()"),
        .init(name: "getLocationDetail", include: "actions/location", signature: "getLocationDetail(variable, detail)", description: "Get details about a location: city, state, country, lat, long, zip code.", keywords: ["location","detail","city","state","country","zip","address","latitude","longitude"], example: nil),
        .init(name: "openInMaps", include: "actions/location", signature: "openInMaps(variable location)", description: "Open a location in Maps.", keywords: ["map","open","navigate","directions","location","address"], example: nil),
        .init(name: "getMapsLink", include: "actions/location", signature: "getMapsLink(variable location)", description: "Get a maps link for a location.", keywords: ["map","link","url","location","directions","share"], example: nil),
        .init(name: "getCurrentWeather", include: "actions/location", signature: #"getCurrentWeather(?location)"#, description: "Get current weather conditions for a location.", keywords: ["weather","temperature","forecast","rain","cloud","wind","humidity","current","today","outside"], example: #"@w = getCurrentWeather("Current Location")"#),
        .init(name: "getWeatherForecast", include: "actions/location", signature: "getWeatherForecast(?type, ?location)", description: "Get a weather forecast (Daily or Hourly).", keywords: ["weather","forecast","daily","hourly","future","tomorrow","week"], example: nil),
        .init(name: "getWeatherDetail", include: "actions/location", signature: "getWeatherDetail(variable weather, detail)", description: "Get a weather property: Temperature, Feels Like, Condition, Humidity, Wind Speed, UV Index, Precipitation Chance, Sunrise, Sunset.", keywords: ["weather","temperature","condition","humidity","wind","rain","uv","sunrise","sunset","detail"], example: #"@temp = getWeatherDetail(@weather, "Temperature")"#),
        .init(name: "getHalfwayPoint", include: "actions/location", signature: "getHalfwayPoint(variable loc1, variable loc2)", description: "Get the halfway point between two locations.", keywords: ["halfway","midpoint","between","location","distance"], example: nil),
    ]

    // MARK: Math
    static let math: [ActionEntry] = [
        .init(name: "calculate", include: "actions/math", signature: "calculate(operation, number a, ?number b): number", description: "Perform math operations: square, sqrt, log, sin, cos, tan, abs, power.", keywords: ["calculate","math","compute","square","sqrt","root","log","sin","cos","tan","abs","power","exponent"], example: nil),
        .init(name: "statistic", include: "actions/math", signature: "statistic(operation, variable): number", description: "Statistical operations: Average, Minimum, Maximum, Sum, Median, Mode, Range, Standard Deviation.", keywords: ["average","mean","min","max","sum","median","statistics","total","aggregate"], example: nil),
        .init(name: "round", include: "actions/math", signature: "round(number, ?place)", description: "Round a number to the nearest place.", keywords: ["round","decimal","number","nearest","integer"], example: nil),
        .init(name: "ceil", include: "actions/math", signature: "ceil(number, ?place)", description: "Round a number up.", keywords: ["ceil","ceiling","round","up","number"], example: nil),
        .init(name: "floor", include: "actions/math", signature: "floor(number, ?place)", description: "Round a number down.", keywords: ["floor","round","down","number"], example: nil),
    ]

    // MARK: Media
    static let media: [ActionEntry] = [
        .init(name: "takePhoto", include: "actions/media", signature: "takePhoto(?count, ?showPreview)", description: "Open the camera to take a photo.", keywords: ["photo","camera","take","capture","picture","shoot"], example: nil),
        .init(name: "takeScreenshot", include: "actions/media", signature: "takeScreenshot(?mainMonitorOnly)", description: "Capture a screenshot of the screen.", keywords: ["screenshot","screen","capture","image","photo"], example: "takeScreenshot()"),
        .init(name: "recordAudio", include: "actions/media", signature: "recordAudio(?quality, ?start)", description: "Record audio using the microphone.", keywords: ["record","audio","microphone","voice","sound"], example: nil),
        .init(name: "playSound", include: "actions/media", signature: "playSound(variable input)", description: "Play a sound or audio file.", keywords: ["play","sound","audio","music","file"], example: nil),
        .init(name: "searchPodcasts", include: "actions/media", signature: "searchPodcasts(text query)", description: "Search for podcasts.", keywords: ["podcast","search","find","show","audio","subscribe"], example: nil),
        .init(name: "getPodcasts", include: "actions/media", signature: "getPodcasts()", description: "Get the user's podcast library.", keywords: ["podcasts","library","list","get","subscribed"], example: nil),
        .init(name: "playPodcast", include: "actions/media", signature: "playPodcast(variable podcast)", description: "Play a podcast.", keywords: ["play","podcast","audio","listen","episode"], example: nil),
        .init(name: "encodeVideo", include: "actions/media", signature: "encodeVideo(variable, ?size, ?speed)", description: "Encode or compress a video.", keywords: ["encode","video","compress","convert","size","format"], example: nil),
        .init(name: "trimVideo", include: "actions/media", signature: "trimVideo(variable video)", description: "Trim a video clip.", keywords: ["trim","video","cut","clip","edit"], example: nil),
        .init(name: "startShazam", include: "actions/media", signature: "startShazam(?show, ?showError)", description: "Identify a song using Shazam.", keywords: ["shazam","identify","song","music","recognize","audio"], example: nil),
    ]

    // MARK: Music
    static let music: [ActionEntry] = [
        .init(name: "getCurrentSong", include: "actions/music", signature: "getCurrentSong()", description: "Get the currently playing song.", keywords: ["current","song","playing","music","track","now"], example: "@song = getCurrentSong()"),
        .init(name: "play", include: "actions/music", signature: "play()", description: "Press play on the current media.", keywords: ["play","music","audio","resume","start"], example: nil),
        .init(name: "pause", include: "actions/music", signature: "pause()", description: "Pause the current media.", keywords: ["pause","music","audio","stop","hold"], example: nil),
        .init(name: "togglePlayPause", include: "actions/music", signature: "togglePlayPause()", description: "Toggle between play and pause.", keywords: ["toggle","play","pause","music","audio"], example: nil),
        .init(name: "skipFwd", include: "actions/music", signature: "skipFwd()", description: "Skip to the next track.", keywords: ["skip","next","forward","song","track","music"], example: nil),
        .init(name: "skipBack", include: "actions/music", signature: "skipBack()", description: "Go back to the previous track.", keywords: ["back","previous","rewind","song","track","music"], example: nil),
        .init(name: "playMusic", include: "actions/music", signature: "playMusic(variable music, ?shuffle, ?repeat)", description: "Play music with optional shuffle and repeat modes.", keywords: ["play","music","song","shuffle","repeat","queue"], example: nil),
        .init(name: "addToPlaylist", include: "actions/music", signature: "addToPlaylist(text playlistName, variable songs)", description: "Add songs to a playlist.", keywords: ["playlist","add","music","songs","library"], example: nil),
        .init(name: "getPlaylistSongs", include: "actions/music", signature: "getPlaylistSongs(variable name): array", description: "Get songs from a playlist.", keywords: ["playlist","songs","get","music","list"], example: nil),
        .init(name: "getMusicDetail", include: "actions/music", signature: "getMusicDetail(variable music, detail)", description: "Get details about a song: Title, Artist, Album, Genre, Duration, Lyrics, etc.", keywords: ["music","song","detail","title","artist","album","genre","lyrics"], example: nil),
    ]

    // MARK: Photos
    static let photos: [ActionEntry] = [
        .init(name: "selectPhotos", include: "actions/photos", signature: "selectPhotos(?selectMultiple)", description: "Prompt the user to select photos from their library.", keywords: ["select","photos","choose","pick","library","image"], example: nil),
        .init(name: "savePhoto", include: "actions/photos", signature: "savePhoto(variable image, ?album)", description: "Save a photo or image to the photo library.", keywords: ["save","photo","image","library","album","store"], example: nil),
        .init(name: "getLatestPhotos", include: "actions/photos", signature: "getLatestPhotos(number count, ?includeScreenshots)", description: "Get the most recent photos.", keywords: ["latest","recent","photos","last","get","library"], example: nil),
        .init(name: "getLatestScreenshots", include: "actions/photos", signature: "getLatestScreenshots(number count)", description: "Get the most recent screenshots.", keywords: ["screenshots","latest","recent","get","screen","capture"], example: nil),
        .init(name: "searchPhotos", include: "actions/photos", signature: "searchPhotos(text criteria): array", description: "Search the photo library.", keywords: ["search","photos","find","library","query","filter"], example: nil),
        .init(name: "deletePhotos", include: "actions/photos", signature: "deletePhotos(variable photos)", description: "Delete photos from the library.", keywords: ["delete","remove","photos","trash","library"], example: nil),
        .init(name: "createAlbum", include: "actions/photos", signature: "createAlbum(text name, ?images)", description: "Create a new photo album.", keywords: ["create","album","photos","new","organize"], example: nil),
    ]

    // MARK: Images
    static let images: [ActionEntry] = [
        .init(name: "resizeImage", include: "actions/images", signature: "resizeImage(variable image, text width, ?height)", description: "Resize an image to specific dimensions.", keywords: ["resize","image","width","height","scale","size"], example: nil),
        .init(name: "cropImage", include: "actions/images", signature: "cropImage(variable image, ?width, ?height, ?position)", description: "Crop an image.", keywords: ["crop","image","cut","trim","size"], example: nil),
        .init(name: "rotateMedia", include: "actions/images", signature: "rotateMedia(variable media, text degrees)", description: "Rotate an image or video.", keywords: ["rotate","image","video","degrees","turn","flip"], example: nil),
        .init(name: "flipImage", include: "actions/images", signature: "flipImage(variable image, direction)", description: "Flip an image horizontally or vertically.", keywords: ["flip","mirror","image","horizontal","vertical"], example: nil),
        .init(name: "convertImage", include: "actions/images", signature: "convertImage(variable image, format, ?quality)", description: "Convert an image to PNG, JPEG, HEIF, GIF, TIFF, BMP, or PDF.", keywords: ["convert","image","format","png","jpeg","heif","gif","tiff","export"], example: nil),
        .init(name: "convertToJPEG", include: "actions/images", signature: "convertToJPEG(variable image, ?quality)", description: "Convert an image to JPEG.", keywords: ["convert","jpeg","jpg","image","format","compress","quality"], example: nil),
        .init(name: "removeBackground", include: "actions/images", signature: "removeBackground(variable image, ?crop)", description: "Remove the background from an image.", keywords: ["background","remove","cutout","image","transparent"], example: nil),
        .init(name: "combineImages", include: "actions/images", signature: "combineImages(variable images, ?mode, ?spacing)", description: "Combine multiple images vertically or in a grid.", keywords: ["combine","merge","images","grid","collage","stack"], example: nil),
        .init(name: "makeGIF", include: "actions/images", signature: "makeGIF(variable input, ?delay, ?loops)", description: "Create an animated GIF from images.", keywords: ["gif","animated","create","images","animation"], example: nil),
        .init(name: "getImageDetail", include: "actions/images", signature: "getImageDetail(variable image, detail)", description: "Get image metadata: width, height, date taken, location, etc.", keywords: ["image","detail","width","height","date","metadata","exif"], example: nil),
        .init(name: "extractImageText", include: "actions/images", signature: "extractImageText(variable image): text", description: "OCR: extract text from an image.", keywords: ["ocr","text","image","extract","read","scan"], example: nil),
    ]

    // MARK: Documents
    static let documents: [ActionEntry] = [
        .init(name: "getFile", include: "actions/documents", signature: "getFile(text path)", description: "Get a file from the Shortcuts folder by path.", keywords: ["file","get","read","open","path","document"], example: nil),
        .init(name: "saveFile", include: "actions/documents", signature: "saveFile(text path, variable content, ?overwrite)", description: "Save content to a file at the given path.", keywords: ["save","file","write","store","path","document","export"], example: nil),
        .init(name: "selectFile", include: "actions/documents", signature: "selectFile(?selectMultiple)", description: "Prompt the user to select a file.", keywords: ["select","file","choose","pick","open","document"], example: nil),
        .init(name: "createFolder", include: "actions/documents", signature: "createFolder(text path)", description: "Create a folder at the given path.", keywords: ["create","folder","directory","path","new"], example: nil),
        .init(name: "deleteFiles", include: "actions/documents", signature: "deleteFiles(variable, ?immediately)", description: "Delete a file or files.", keywords: ["delete","remove","file","trash","clean"], example: nil),
        .init(name: "appendToFile", include: "actions/documents", signature: "appendToFile(text path, text text)", description: "Append text to the end of a file.", keywords: ["append","write","file","add","text","log"], example: nil),
        .init(name: "rename", include: "actions/documents", signature: "rename(variable file, text newName)", description: "Rename a file.", keywords: ["rename","file","name","change"], example: nil),
        .init(name: "getFileDetail", include: "actions/documents", signature: "getFileDetail(variable file, detail)", description: "Get file metadata: name, size, extension, creation date, path.", keywords: ["file","detail","name","size","date","extension","path","metadata"], example: nil),
        .init(name: "makeArchive", include: "actions/documents", signature: "makeArchive(variable files, ?format, ?name)", description: "Create a zip or other archive from files.", keywords: ["archive","zip","compress","tar","files","bundle"], example: nil),
        .init(name: "extractArchive", include: "actions/documents", signature: "extractArchive(variable file)", description: "Extract files from an archive.", keywords: ["extract","unzip","archive","decompress","files"], example: nil),
        .init(name: "openNote", include: "actions/documents", signature: "openNote(variable note)", description: "Open a note in the Notes app.", keywords: ["note","open","notes","view","show"], example: nil),
        .init(name: "appendNote", include: "actions/documents", signature: "appendNote(text note, text input)", description: "Append text to a note.", keywords: ["note","append","add","write","text","notes"], example: nil),
        .init(name: "makeQRCode", include: "actions/documents", signature: "makeQRCode(text input, ?errorCorrection)", description: "Generate a QR code image from text or a URL.", keywords: ["qr","code","barcode","generate","scan","link","url"], example: nil),
        .init(name: "print", include: "actions/documents", signature: "print(variable input)", description: "Print content to a printer.", keywords: ["print","printer","document","paper"], example: nil),
        .init(name: "reveal", include: "actions/documents", signature: "reveal(variable files)", description: "Reveal files in Finder.", keywords: ["reveal","finder","show","file","open","folder"], example: nil),
    ]

    // MARK: macOS
    static let mac: [ActionEntry] = [
        .init(name: "runShellScript", include: "actions/mac", signature: "runShellScript(text script, variable input, ?shell, ?inputMode)", description: "Run a shell script (bash/zsh) on macOS.", keywords: ["shell","bash","zsh","script","run","execute","terminal","command","cli","unix"], example: #"@out = runShellScript("echo Hello", "")"#),
        .init(name: "runAppleScript", include: "actions/mac", signature: "runAppleScript(variable input, text script)", description: "Run an AppleScript on macOS.", keywords: ["applescript","script","run","execute","macos","automation","osascript"], example: nil),
        .init(name: "runJSAutomation", include: "actions/mac", signature: "runJSAutomation(variable input, text script)", description: "Run JavaScript for Automation (JXA) on macOS.", keywords: ["javascript","jxa","automation","script","run","execute","macos"], example: nil),
        .init(name: "getApps", include: "actions/mac", signature: "getApps(): array", description: "Get a list of all installed applications.", keywords: ["apps","applications","installed","list","get"], example: nil),
        .init(name: "sleep", include: "actions/mac", signature: "sleep()", description: "Put the Mac to sleep.", keywords: ["sleep","mac","power","suspend"], example: nil),
        .init(name: "displaySleep", include: "actions/mac", signature: "displaySleep()", description: "Put the Mac display to sleep while keeping the system awake.", keywords: ["display","sleep","screen","off","mac"], example: nil),
        .init(name: "startScreensaver", include: "actions/mac", signature: "startScreensaver()", description: "Start the screen saver.", keywords: ["screensaver","screen","saver","idle","mac"], example: nil),
        .init(name: "moveWindow", include: "actions/mac", signature: "moveWindow(variable window, position, ?bringToFront)", description: "Move a window to a specific position on screen.", keywords: ["window","move","position","screen","arrange","layout"], example: nil),
        .init(name: "resizeWindow", include: "actions/mac", signature: "resizeWindow(variable window, configuration)", description: "Resize a window (full screen, half, quarter, etc.).", keywords: ["window","resize","size","full","half","screen","layout"], example: nil),
        .init(name: "takeInteractiveScreenshot", include: "actions/mac", signature: "takeInteractiveScreenshot(?selection)", description: "Take an interactive screenshot (window or custom area).", keywords: ["screenshot","interactive","window","capture","mac","screen"], example: nil),
    ]
}
