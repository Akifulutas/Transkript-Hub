import Foundation
import Compression

public struct PostProcessorOptions: Sendable {
    public var removeNoiseTags: Bool
    public var deduplicateRepetitions: Bool
    public var insertTimestamps: Bool
    public var paragraphSilenceThreshold: Double
    public var maxParagraphLength: Int
    public var maxCompressionRatio: Double
    public var filterStandaloneBoilerplate: Bool

    public init(
        removeNoiseTags: Bool = true,
        deduplicateRepetitions: Bool = true,
        insertTimestamps: Bool = false,
        paragraphSilenceThreshold: Double = 2.5,
        maxParagraphLength: Int = 650,
        maxCompressionRatio: Double = 2.4,
        filterStandaloneBoilerplate: Bool = true
    ) {
        self.removeNoiseTags = removeNoiseTags
        self.deduplicateRepetitions = deduplicateRepetitions
        self.insertTimestamps = insertTimestamps
        self.paragraphSilenceThreshold = paragraphSilenceThreshold
        self.maxParagraphLength = maxParagraphLength
        self.maxCompressionRatio = maxCompressionRatio
        self.filterStandaloneBoilerplate = filterStandaloneBoilerplate
    }
}

public final class TranscriptPostProcessor: Sendable {
    public init() {}

    /// Tier A: Pure hallucination phrases that are NEVER legitimate speech and can be
    /// safely stripped at both segment and sentence level.
    private static let pureHallucinationPhrases: Set<String> = [
        "es heilt die göttliche kraft",
        "ich hoffe es hilft es heilt die göttliche kraft",
        "göttliche kraft",
        "altyazı mk",
        "altyazı m k",
        "amara.org",
        "amaraorg",
        "amara org",
        "subtitles by the amaraorg community",
        "teksting av nicolai winther",
        "hvað er það",
        "það er það er það",
        "norske skogsforskning"
    ]

    private static let pureHallucinationMaxWords: Int = {
        pureHallucinationPhrases.map { $0.split(separator: " ").count }.max() ?? 0
    }()

    /// Tier A dynamic credit regexes and case-aware structural validator helpers
    private static let creditEdgeTrimSet: CharacterSet = {
        CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,!?;:…\"'„“”«»()[]*♪-–—"))
    }()

    private static let creditNonDotEdgeTrimSet: CharacterSet = {
        CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",!?;:…\"'„“”«»()[]*♪-–—"))
    }()

    private static let knownCreditEntities: Set<String> = [
        "zdf", "ard", "wdr", "ndr", "br", "swr", "hr", "rbb", "mdr", "sr",
        "arte", "orf", "srf", "3sat", "pro7", "sat1", "sat.1",
        "amara", "amara.org", "deepl", "openai", "whisper", "chatgpt",
        "redaktion", "community"
    ]

    private static let creditOrgDesignators: Set<String> = [
        "studio", "studios", "gmbh", "ag", "ug", "kg", "ohg", "gbr",
        "inc", "ltd", "llc", "co", "corp", "verlag", "media", "medien",
        "produktion", "production", "productions", "film", "tv",
        "agentur", "agency", "institut", "institute", "stiftung",
        "foundation", "rundfunk", "fernsehen", "team"
    ]

    private static let knownGivenNames: Set<String> = [
        // German & international unambiguous given names (strictly excluding German common nouns/adjectives)
        "stephanie", "stefanie", "max", "carl", "karl", "finn", "hans", "peter",
        "anna", "maria", "julia", "laura", "lisa", "sarah", "lena", "thomas",
        "michael", "andreas", "stefan", "steffen", "christian", "christoph",
        "martin", "daniel", "tobias", "sebastian", "matthias", "markus", "jan",
        "lukas", "lucas", "jonas", "paul", "felix", "alexander", "florian",
        "fabian", "benjamin", "david", "simon", "philipp", "johannes", "jakob",
        "jacob", "niklas", "maximilian", "moritz", "julian", "tim", "tom",
        "leon", "noah", "elias", "ben", "emil", "anton", "oskar", "theo",
        "theodor", "henry", "luis", "liam", "sophie", "sofie", "sophia",
        "sofia", "hannah", "hanna", "mia", "emma", "lina", "clara", "klara",
        "lea", "marie", "johanna", "katharina", "katrin", "kathrin", "franziska",
        "sabine", "susanne", "petra", "claudia", "andrea", "nicole", "sandra",
        "christine", "anja", "kerstin", "birgit", "heike", "monika", "karin",
        "ursula", "gabriele", "wolfgang", "klaus", "jürgen", "uwe", "frank",
        "bernd", "ralf", "ralph", "dirk", "holger", "jörg", "sven", "oliver",
        "thorsten", "torsten", "carsten", "karsten", "stephan", "dieter",
        "manfred", "helmut", "werner", "günter", "günther", "heinrich",
        "wilhelm", "georg", "franz", "josef", "johann", "robert", "patrick",
        "dennis", "marcel", "marco", "nico", "niko", "kevin", "dominik",
        "elena", "nina", "vanessa", "melanie", "tanja", "nadine", "simone",
        "silke", "bettina", "britta", "antje", "ines", "anke", "ulrike",
        "veronika", "elisabeth", "theresa", "christina", "miriam", "eva",
        "waltraud", "friedhelm", "brigitte", "ingrid", "renate", "gisela",
        "christa", "elke", "angelika", "marion", "beate", "martina", "kirsten",
        "silvia", "cornelia", "helena", "katja", "sonja", "manuela", "annika",
        "anne", "mareike", "wiebke", "imke", "frauke", "meike", "maike",
        "svea", "antonia", "paula", "frida", "frieda", "greta", "ida", "lotte",
        "marlene", "mathilde", "therese", "emilia", "amanda", "rachel", "rebecca",
        "nicolas", "nikolas", "konstantin", "valentin", "vincent", "manuel",
        "olaf", "henrik", "bastian", "sascha", "mirko", "mirco", "ingo",
        "heiko", "lars", "nils", "niels", "jens", "maik", "meik", "rené",
        "rene", "andré", "andre", "marc", "eric", "erik", "henning", "björn",
        "sören", "malte", "hauke", "torben", "leif", "axel", "bernhard",
        "bruno", "clemens", "konrad", "conrad", "detlef", "edgar", "erich",
        "erwin", "eugen", "ferdinand", "friedrich", "gerhard", "gregor",
        "guido", "gunnar", "gustav", "hannes", "harald", "hartmut", "heiner",
        "helge", "herbert", "hermann", "hubert", "joachim", "jochen",
        "jonathan", "kaspar", "kilian", "klemens", "knut", "kurt", "lennart",
        "leopold", "lorenz", "lothar", "ludwig", "lutz", "marius", "matteo",
        "norbert", "otto", "pascal", "reinhold", "roland", "rolf", "ronald",
        "rüdiger", "siegfried", "steffen", "timo", "udo", "ulrich", "volker",
        "walter", "walther", "wilfried", "willi", "winfried", "yves",
        "john", "james", "william", "richard", "charles", "mary", "jennifer",
        "jessica", "lauren", "victoria", "natalie", "charlotte", "olivia",
        "emily", "alice", "bob", "chris", "sam", "george", "edward", "arthur",
        "harry", "jack", "ethan", "mason", "logan", "matthew", "andrew",
        "joshua", "ryan", "nathan", "aaron", "adam", "alan", "albert", "alex",
        "alfred"
    ]

    private static let nonCreditFunctionWords: Set<String> = [
        "ein", "eine", "einem", "einer", "eines",
        "der", "die", "das", "dem", "den", "des",
        "diesem", "dieser", "dieses", "diesen",
        "im", "in", "am", "an", "auf", "über", "unter", "mit", "für", "bei", "nach", "aus", "zu", "vom", "zum", "zur", "bis",
        "the", "a", "an", "into", "from", "by", "to", "of", "on", "at", "with",
        "default", "links", "rechts", "oben", "unten", "hand",
        "beide", "beiden", "beider", "beides", "alle", "mehrere", "mehreren", "einige", "einigen", "wenige", "wenigen", "etliche", "dutzend", "dutzende",
        "video", "version", "schritt", "teil", "absatz", "datei", "daten", "baugruppe",
        "algorithm", "algorithmus", "clicking", "export", "mesh", "cad",
        "auch", "noch", "dann", "mal", "nur", "sehr", "immer", "jetzt", "heute", "schon",
        "bereits", "etwa", "wohl", "doch", "gar", "hier", "dort", "vorn", "hinten",
        "mehr", "viel", "ganz", "voll", "weit", "nah", "oft", "nie", "stets", "fast", "kaum",
        "erst", "spät", "früh", "gleich", "bald", "gern", "zwar", "somit", "daher", "dabei",
        "damit", "dafür", "dagegen", "darauf", "daraus", "darin", "darüber", "darunter",
        "davon", "dazu", "wieder", "weiter", "zurück", "vorbei", "zusammen", "allein",
        "selbst", "selber", "man", "wir", "ihr", "sie", "ich", "du", "es", "uns", "euch",
        "ihm", "ihn", "was", "wer", "wie", "wo", "wann", "warum", "weshalb", "wieso",
        "weil", "ob", "als", "wenn", "dass", "daß", "aber", "oder", "und", "and", "denn", "sondern",
        "gut", "neu", "alt", "hoch", "tief", "fest", "frei", "klar", "rein", "fein", "grob",
        "klein", "groß", "lang", "kurz", "schnell", "stark", "schwach", "hart", "weich",
        "warm", "kalt", "leicht", "schwer", "recht", "echt", "falsch", "wahr",
        "per", "ohne", "pro", "via"
    ]

    private static let creditDomainRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^[a-z0-9-]+\.(?:org|com|net|de|tv|io|ch|at|eu)$"#)
    }()

    private static let creditSentenceVerbRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?<![\p{L}])(?:sind|werden|wurden|wurde|wird|ist|war|waren|hat|haben|kann|können|muss|müssen|soll|sollen|darf|dürfen|erfolgt|erfolgen|zeigen|zeigt|erscheinen|bleiben|ausgeblendet|eingeblendet|aktiviert|aktivieren|deaktiviert|deaktivieren|korrigiert|korrigieren|exportiert|exportieren|importiert|importieren|prüfen|geprüft|beachten|entfernen|stehen|läuft|erstellen|berechnen|are|is|were|was|will|would|can|could|should|must|disabled|enabled|shown|hidden|clicking|export|required|needed)(?![\p{L}])"#)
    }()

    private static let creditTechStemRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?:getriebe|zahnrad|zahnräd|baugrupp|turbin|schaufel|kurbelgehäuse|zylinder|kolben|rotor|stator|schnittstell|gitter|vernetz|netzgenerier|drehzahl|drehmoment|strömung|konvergenz|simulation|konstruktion|konverter|converter|algorithm|geometrie|bauteil|gehäuse|header|viewer|format)|(?<![\p{L}])(?:cad|step|iges|stl|mesh|netz)(?![\p{L}])"#)
    }()

    private static let germanProseParticleRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(?<![\p{L}])(?:ein|eine|einem|einer|eines|der|die|das|dem|den|des|im|in|am|an|auf|über|unter|mit|für|bei|nach|aus|zu|vom|zum|zur|und|oder|nicht|kein|keine)(?![\p{L}])"#)
    }()

    private static let untertitelDerRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^untertitel\s+der\s+(?:redaktion|amara(?:\.org)?|community|zdf|ard|wdr|ndr|br|swr|hr|rbb|mdr|sr|arte|orf|srf)(?:\b|$)"#, options: [.caseInsensitive])
    }()

    private static let untertitelAuftragRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^untertitel\s+im\s+auftrag\s+(?:des|der|von|für)\s+(.+)$"#, options: [.caseInsensitive])
    }()

    private static let copyrightPrefixRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^copyright(?:\s*:\s*|\s+)(.+)$"#, options: [.caseInsensitive])
    }()

    private static let copyrightSymbolParenRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^(?:\(c\)|©)\s*(?:\d{4}\b)?(?:\s+[\p{L}\p{N}.&_-]+){0,5}$"#, options: [.caseInsensitive])
    }()

    private static let copyrightByRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^by\s+(.+)$"#, options: [.caseInsensitive])
    }()

    private enum CreditHeaderMode: Sendable {
        case germanAmbiguous
        case germanSubtitleBy
        case englishCreditBy
    }

    private static let creditAttributionHeaderRegexes: [(regex: NSRegularExpression, mode: CreditHeaderMode)] = {
        let patterns: [(String, CreditHeaderMode)] = [
            (#"^untertitel\s+von\s+(.+)$"#, .germanSubtitleBy),
            (#"^untertitel\s*:\s*(.+)$"#, .germanAmbiguous),
            (#"^(?:deutsche\s+)?übersetzung\s+(?:von|durch)\s+(.+)$"#, .germanAmbiguous),
            (#"^(?:deutsche\s+)?übersetzung\s*:\s*(.+)$"#, .germanAmbiguous),
            (#"^subtitles\s+by\s+(.+)$"#, .englishCreditBy),
            (#"^translated\s+by\s+(.+)$"#, .englishCreditBy)
        ]
        return patterns.compactMap { pattern, mode in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return nil
            }
            return (regex: regex, mode: mode)
        }
    }()

    /// Tier B: Standalone conversational / outro boilerplate.
    /// STRICT invariant: Only pruned when the ENTIRE normalized segment equals an entry here.
    /// Never matched as a prefix or substring of legitimate speech.
    private static let standaloneBoilerplatePhrases: Set<String> = [
        "vielen dank",
        "danke",
        "danke schön",
        "dankeschön",
        "vielen dank fürs zuschauen",
        "danke fürs zuschauen",
        "danke fürs zusehen",
        "vielen dank für ihre aufmerksamkeit",
        "vielen dank für eure aufmerksamkeit",
        "amen",
        "thank you",
        "thank you very much",
        "thank you so much",
        "thank you for watching",
        "thanks for watching",
        "please subscribe",
        "please subscribe to the channel",
        "like and subscribe",
        "bis zum nächsten mal",
        "tschüss",
        "auf wiedersehen",
        "lütfen abone olun",
        "abone olmayı unutmayın",
        "izlediğiniz için teşekkürler",
        "izlediğiniz için teşekkür ederim",
        "altyazı",
        "subtitles by"
    ]

    private static let standaloneBoilerplateMaxWords: Int = {
        standaloneBoilerplatePhrases.map { $0.split(separator: " ").count }.max() ?? 1
    }()

    private static let standaloneBoilerplateFirstWords: Set<String> = {
        Set(standaloneBoilerplatePhrases.compactMap { $0.split(separator: " ").first.map(String.init) })
    }()

    private static let standaloneBoilerplateAllWords: Set<String> = {
        var words: Set<String> = []
        for phrase in standaloneBoilerplatePhrases {
            for token in phrase.split(separator: " ") {
                words.insert(String(token))
            }
        }
        return words
    }()

    private static let punctuationToStripSet: CharacterSet = {
        CharacterSet.punctuationCharacters.union(.symbols)
    }()

    private static func normalizeForMatching(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(folded.unicodeScalars.count)
        var lastWasSpace = true

        for scalar in folded.unicodeScalars {
            // Preserve © so dynamic copyright regex can detect it before general stripping
            if scalar == "©" {
                scalars.append(scalar)
                lastWasSpace = false
                continue
            }
            // Treat zero-width space as a word boundary
            if scalar == "\u{200B}" {
                if !lastWasSpace {
                    scalars.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            // Strip soft hyphens (\u{00AD}) and other invisible format characters without inserting spaces
            if scalar.properties.generalCategory == .format {
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || punctuationToStripSet.contains(scalar) {
                if !lastWasSpace {
                    scalars.append(" ")
                    lastWasSpace = true
                }
            } else {
                scalars.append(scalar)
                lastWasSpace = false
            }
        }

        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces)
    }

    private static func normalizeRemovingDots(_ text: String) -> String {
        normalizeForMatching(text.replacingOccurrences(of: ".", with: ""))
    }

    private static func matchesRegex(_ regex: NSRegularExpression?, _ string: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }

    private static func firstCaptureGroup(_ regex: NSRegularExpression?, _ string: String) -> String? {
        guard let regex else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges >= 2,
              let swiftRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return String(string[swiftRange])
    }

    private static func containsSentenceVerbOrTechTerm(_ lowerText: String) -> Bool {
        if matchesRegex(creditSentenceVerbRegex, lowerText) || matchesRegex(creditTechStemRegex, lowerText) {
            return true
        }
        let tokens = lowerText.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: creditEdgeTrimSet)
        }
        for w in tokens where !w.isEmpty {
            if w.count >= 6 && w.hasSuffix("ung") {
                return true
            }
            if w.hasSuffix("ierung") || w.hasSuffix("schaft") || w.hasSuffix("heit") || w.hasSuffix("keit") || w.hasSuffix("tät") {
                return true
            }
            if w.hasSuffix("tion") && w != "redaktion" {
                return true
            }
        }
        return false
    }

    private static func isGermanNumeral(_ lower: String) -> Bool {
        guard !lower.isEmpty else { return false }
        let irregulars: Set<String> = [
            "null", "eins", "eine", "einem", "einen", "einer", "eines",
            "erste", "ersten", "erster", "erstes", "erstem",
            "zweite", "zweiten", "zweiter", "zweites", "zweitem",
            "dritte", "dritten", "dritter", "drittes", "drittem",
            "sechste", "sechsten", "sechster", "sechstes", "sechstem",
            "siebte", "siebten", "siebter", "siebtes", "siebtem",
            "achte", "achten", "achter", "achtes", "achtem"
        ]
        if irregulars.contains(lower) { return true }

        // Strip optional German ordinal / multiplicative suffix
        var base = lower
        for suffix in ["fachen", "facher", "faches", "fachem", "fache", "fach", "mal",
                       "sten", "ster", "stes", "stem", "ste", "st",
                       "ten", "ter", "tes", "tem", "te"] {
            if base.count > suffix.count + 2 && base.hasSuffix(suffix) {
                base = String(base.dropLast(suffix.count))
                break
            }
        }

        // Greedy morpheme consumption over closed German number-word grammar
        let morphemes = [
            "milliarden", "milliarde", "millionen", "million",
            "tausend", "hundert",
            "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn",
            "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig",
            "zwölf", "sieben", "sechs", "fünf", "vier", "drei", "zwei", "zwo", "eins", "ein",
            "acht", "neun", "zehn", "elf", "und"
        ]
        var idx = base.startIndex
        var matchedCount = 0
        var lastWasUnd = false
        while idx < base.endIndex {
            var matched: String? = nil
            for m in morphemes {
                if base[idx...].hasPrefix(m) {
                    if m == "und" && matchedCount == 0 { continue }
                    matched = m
                    break
                }
            }
            guard let m = matched else { return false }
            lastWasUnd = (m == "und")
            idx = base.index(idx, offsetBy: m.count)
            matchedCount += 1
        }
        return matchedCount > 0 && !lastWasUnd
    }

    private static func isNumeralToken(_ lower: String) -> Bool {
        let englishNumerals: Set<String> = [
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
            "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
            "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
            "hundred", "thousand", "million", "billion",
            "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"
        ]
        if englishNumerals.contains(lower) { return true }
        if !lower.isEmpty && lower.allSatisfy(\.isNumber) { return true }
        return isGermanNumeral(lower)
    }

    private static func isMeasurementUnitToken(_ lower: String) -> Bool {
        let siPattern = #"^(?:femto|piko|nano|mikro|micro|milli|zenti|centi|dezi|kilo|mega|giga|tera)?(?:meter|metern|metres?|gramm|grams?|sekunde|sekunden|seconds?|watt|volt|ampere|hertz|joule|liter|litern|litres?|bar)$"#
        let prefixedOnlyPattern = #"^(?:hekto|kilo|mega|giga|milli)(?:pascal|newton)$"#
        let directUnits: Set<String> = [
            "grad", "prozent", "percent", "zahn", "zähne", "zähnen",
            "umdrehung", "umdrehungen", "millimetern", "zentimetern", "kilometern"
        ]
        if directUnits.contains(lower) { return true }
        return lower.range(of: siPattern, options: .regularExpression) != nil
            || lower.range(of: prefixedOnlyPattern, options: .regularExpression) != nil
    }

    private static func startsWithUppercaseLetter(_ token: String) -> Bool {
        guard let firstScalar = token.unicodeScalars.first else { return false }
        return CharacterSet.uppercaseLetters.contains(firstScalar)
    }

    private static func startsWithCompatibilityLigature(_ rawToken: String) -> Bool {
        guard let firstScalar = rawToken.unicodeScalars.first else { return false }
        return (0xFB00...0xFB06).contains(firstScalar.value) // ﬀ ﬁ ﬂ ﬃ ﬄ ﬅ ﬆ
    }

    private static func isPersonInitialToken(_ rawToken: String) -> Bool {
        let parts = rawToken.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            let scalars = Array(part.unicodeScalars)
            return scalars.count == 2
                && CharacterSet.uppercaseLetters.contains(scalars[0])
                && scalars[1] == "."
        }
    }

    private static func sharesCompoundNounSuffix(_ tokens: [String]) -> Bool {
        guard tokens.count >= 2 else { return false }
        let excludedSurnameSuffixes: Set<String> = [
            "mann", "berg", "stein", "feld", "haus", "holz", "bach", "dorf", "heim", "hoff", "wald"
        ]
        let lowers = tokens.map { $0.lowercased() }.filter { $0.count >= 5 && $0.allSatisfy(\.isLetter) }
        guard lowers.count >= 2 else { return false }
        for i in 0..<lowers.count {
            for j in (i + 1)..<lowers.count {
                let a = Array(lowers[i])
                let b = Array(lowers[j])
                var common = 0
                while common < min(a.count, b.count) && a[a.count - 1 - common] == b[b.count - 1 - common] {
                    common += 1
                }
                if common >= 5 {
                    let shared = String(a[(a.count - common)...])
                    if !excludedSurnameSuffixes.contains(shared) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private static func isTitleCaseNameOrOrg(_ token: String) -> Bool {
        let lt = token.lowercased()
        if knownCreditEntities.contains(lt) || creditOrgDesignators.contains(lt)
            || token == "KI" || token == "AI" || matchesRegex(creditDomainRegex, lt) {
            return true
        }
        guard startsWithUppercaseLetter(token) else { return false }
        let letterCount = token.filter(\.isLetter).count
        guard letterCount >= 2 else { return false }

        if token.contains("-") {
            let parts = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty else { return false }
            return parts.allSatisfy { part in
                startsWithUppercaseLetter(part)
                    && part.filter(\.isLetter).count >= 2
                    && part.contains(where: \.isLowercase)
            }
        }

        if !token.contains(where: \.isLowercase) {
            return token.count >= 2 && token.count <= 5 && token.allSatisfy(\.isLetter)
        }

        return true
    }

    private static func isRecognizedGivenName(_ token: String) -> Bool {
        let lower = token.lowercased()
        if knownGivenNames.contains(lower) {
            return true
        }
        if token.contains("-") {
            let parts = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            return parts.count >= 2 && parts.allSatisfy { knownGivenNames.contains($0.lowercased()) }
        }
        return false
    }

    private static func isCreditAttributionPayload(
        _ foldedPayload: String,
        rawPayload: String,
        mode: CreditHeaderMode,
        isAllCapsContext: Bool
    ) -> Bool {
        let trimmed = foldedPayload.trimmingCharacters(in: creditEdgeTrimSet)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        guard !containsSentenceVerbOrTechTerm(lower) else { return false }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: creditEdgeTrimSet)
        }
        guard !tokens.isEmpty, tokens.count <= 6, tokens.allSatisfy({ !$0.isEmpty }) else { return false }

        let rawTrimmed = rawPayload.trimmingCharacters(in: creditNonDotEdgeTrimSet)
        let rawSplit = rawTrimmed.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: creditNonDotEdgeTrimSet)
        }
        let rawTokens = (rawSplit.count == tokens.count && rawSplit.allSatisfy({ !$0.isEmpty })) ? rawSplit : tokens

        let allowedAlphanumericBroadcasters: Set<String> = ["3sat", "pro7", "sat1", "sat.1"]
        for t in tokens {
            if t.contains(where: \.isNumber) && !allowedAlphanumericBroadcasters.contains(t.lowercased()) {
                return false
            }
        }

        if tokens.count == 1 {
            let t = tokens[0]
            let lt = t.lowercased()
            return knownCreditEntities.contains(lt)
                || t == "KI"
                || t == "AI"
                || matchesRegex(creditDomainRegex, lt)
        }

        if tokens.count == 3 && ["und", "and"].contains(tokens[1].lowercased()) {
            return false
        }

        // Leading article exception: e.g. "Untertitel von der Redaktion", "Subtitles by the Amara.org community"
        let firstLower = tokens[0].lowercased()
        if firstLower == "der" || firstLower == "the" {
            let rest = Array(tokens.dropFirst())
            guard rest.allSatisfy({
                let lt = $0.lowercased()
                return !nonCreditFunctionWords.contains(lt) && !isNumeralToken(lt) && !isMeasurementUnitToken(lt)
            }) else {
                return false
            }
            return rest.contains {
                let lt = $0.lowercased()
                return knownCreditEntities.contains(lt)
                    || creditOrgDesignators.contains(lt)
                    || matchesRegex(creditDomainRegex, lt)
            }
        }

        let particles: Set<String> = ["von", "van", "de", "der", "&"]
        for (idx, t) in tokens.enumerated() {
            let lt = t.lowercased()
            if particles.contains(lt) {
                if idx == 0 || idx == tokens.count - 1 {
                    return false
                }
                continue
            }
            if idx < tokens.count - 1 && isPersonInitialToken(rawTokens[idx]) {
                continue
            }
            if nonCreditFunctionWords.contains(lt) || isNumeralToken(lt) || isMeasurementUnitToken(lt) {
                return false
            }
        }

        let last = tokens[tokens.count - 1]
        if last.count == 1 && last.allSatisfy(\.isLetter) {
            return false
        }

        if sharesCompoundNounSuffix(tokens) {
            return false
        }

        var hasPositiveCreditEvidence = false

        for (idx, t) in tokens.enumerated() {
            let lt = t.lowercased()
            if idx > 0 && idx < tokens.count - 1 && particles.contains(lt) {
                continue
            }

            let isEntityOrOrg = knownCreditEntities.contains(lt)
                || creditOrgDesignators.contains(lt)
                || t == "KI"
                || t == "AI"
                || matchesRegex(creditDomainRegex, lt)
            if isEntityOrOrg {
                hasPositiveCreditEvidence = true
                continue
            }

            if idx < tokens.count - 1 && isPersonInitialToken(rawTokens[idx]) {
                hasPositiveCreditEvidence = true
                continue
            }

            if isAllCapsContext {
                if t.filter(\.isLetter).count >= 2 && !t.contains("-") {
                    continue
                }
                return false
            }

            if startsWithCompatibilityLigature(rawTokens[idx]) {
                let isPureLetters = t.count >= 3 && t.allSatisfy(\.isLetter)
                let germanAdjSuffixes = ["e", "er", "es", "en", "em", "ig", "lich", "isch"]
                let hasGermanAdjSuffix = germanAdjSuffixes.contains { lt.hasSuffix($0) }
                if isPureLetters && !hasGermanAdjSuffix {
                    continue
                }
                return false
            }

            if startsWithUppercaseLetter(rawTokens[idx]) && isTitleCaseNameOrOrg(t) {
                continue
            }

            return false
        }

        if !hasPositiveCreditEvidence {
            var nameIdx = 0
            while nameIdx + 1 < tokens.count && ["dr", "prof"].contains(tokens[nameIdx].lowercased()) {
                nameIdx += 1
            }
            if isRecognizedGivenName(tokens[nameIdx]) {
                hasPositiveCreditEvidence = true
            }
        }

        if mode != .englishCreditBy && !hasPositiveCreditEvidence {
            return false
        }

        return true
    }

    private static func isFourDigitYear(_ token: String) -> Bool {
        guard token.count == 4, token.allSatisfy(\.isNumber), let year = Int(token) else {
            return false
        }
        return (1900...2099).contains(year)
    }

    private static func isValidCopyrightClause(_ rest: String, isAllCapsContext: Bool) -> Bool {
        let trimmed = rest.trimmingCharacters(in: creditEdgeTrimSet)
        guard !trimmed.isEmpty else { return false }
        let restLower = trimmed.lowercased()
        guard !containsSentenceVerbOrTechTerm(restLower) else { return false }

        if restLower.hasPrefix("©") || restLower.hasPrefix("(c)") {
            guard matchesRegex(copyrightSymbolParenRegex, restLower) else { return false }
            let afterPrefix: String
            if restLower.hasPrefix("(c)") {
                afterPrefix = String(trimmed.dropFirst(3)).trimmingCharacters(in: creditEdgeTrimSet)
            } else {
                afterPrefix = String(trimmed.dropFirst(1)).trimmingCharacters(in: creditEdgeTrimSet)
            }
            if afterPrefix.isEmpty {
                return true
            }
            if isValidCopyrightClause(afterPrefix, isAllCapsContext: isAllCapsContext) {
                return true
            }
            return isCreditAttributionPayload(
                afterPrefix,
                rawPayload: afterPrefix,
                mode: .germanAmbiguous,
                isAllCapsContext: isAllCapsContext
            )
        }

        if let afterBy = firstCaptureGroup(copyrightByRegex, trimmed) {
            return isCreditAttributionPayload(
                afterBy,
                rawPayload: afterBy,
                mode: .englishCreditBy,
                isAllCapsContext: isAllCapsContext
            )
        }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: creditEdgeTrimSet)
        }
        guard !tokens.isEmpty, tokens.count <= 6, tokens.allSatisfy({ !$0.isEmpty }) else { return false }

        let allowedCopyrightKeywords: Set<String> = [
            "all", "rights", "reserved", "alle", "rechte", "vorbehalten", "by", "gmbh", "ag", "inc", "ltd", "llc", "co"
        ]

        func isShortAllCapsAcronym(_ t: String) -> Bool {
            t.count >= 2 && t.count <= 5 && t.allSatisfy(\.isLetter) && !t.contains(where: \.isLowercase)
        }

        // Form 1: "<YYYY> [Holder ...]"
        if isFourDigitYear(tokens[0]) {
            if tokens.count == 1 { return true }
            let trailing = Array(tokens.dropFirst())
            if trailing[0].lowercased() == "by" {
                let afterBy = trailing.dropFirst().joined(separator: " ")
                return !afterBy.isEmpty && isCreditAttributionPayload(
                    afterBy,
                    rawPayload: afterBy,
                    mode: .englishCreditBy,
                    isAllCapsContext: isAllCapsContext
                )
            }

            let trailingLower = trailing.map { $0.lowercased() }.joined(separator: " ")
            guard !matchesRegex(germanProseParticleRegex, trailingLower) else { return false }
            guard trailing.allSatisfy({ t in
                let lt = t.lowercased()
                return allowedCopyrightKeywords.contains(lt)
                    || (!nonCreditFunctionWords.contains(lt) && !isNumeralToken(lt) && !isMeasurementUnitToken(lt))
            }) else {
                return false
            }

            if trailing.count == 1 {
                let t = trailing[0]
                let lt = t.lowercased()
                return knownCreditEntities.contains(lt)
                    || allowedCopyrightKeywords.contains(lt)
                    || matchesRegex(creditDomainRegex, lt)
                    || isShortAllCapsAcronym(t)
            }

            guard !sharesCompoundNounSuffix(trailing) else { return false }
            guard trailing.allSatisfy({ t in
                let lt = t.lowercased()
                return allowedCopyrightKeywords.contains(lt)
                    || knownCreditEntities.contains(lt)
                    || creditOrgDesignators.contains(lt)
                    || matchesRegex(creditDomainRegex, lt)
                    || isAllCapsContext
                    || startsWithUppercaseLetter(t)
            }) else {
                return false
            }

            return trailing.contains(where: { t in
                let lt = t.lowercased()
                return allowedCopyrightKeywords.contains(lt)
                    || knownCreditEntities.contains(lt)
                    || creditOrgDesignators.contains(lt)
                    || matchesRegex(creditDomainRegex, lt)
                    || isShortAllCapsAcronym(t)
            }) || isRecognizedGivenName(trailing[0])
        }

        // Form 2: "<Entity 1..3 tokens> <YYYY> [all rights reserved | alle rechte vorbehalten]"
        if let yearIdx = tokens.firstIndex(where: { isFourDigitYear($0) }), yearIdx >= 1, yearIdx <= 3 {
            let entityTokens = Array(tokens[0..<yearIdx])
            let entityLower = entityTokens.map { $0.lowercased() }.joined(separator: " ")
            guard !matchesRegex(germanProseParticleRegex, entityLower) else { return false }
            guard !sharesCompoundNounSuffix(entityTokens) else { return false }
            guard entityTokens.allSatisfy({ t in
                let lt = t.lowercased()
                return !nonCreditFunctionWords.contains(lt)
                    && !isNumeralToken(lt)
                    && !isMeasurementUnitToken(lt)
                    && (isAllCapsContext || startsWithUppercaseLetter(t) || knownCreditEntities.contains(lt) || creditOrgDesignators.contains(lt) || matchesRegex(creditDomainRegex, lt))
            }) else {
                return false
            }

            let hasHolderSignal: Bool
            if entityTokens.count == 1 {
                let t = entityTokens[0]
                let lt = t.lowercased()
                hasHolderSignal = knownCreditEntities.contains(lt)
                    || matchesRegex(creditDomainRegex, lt)
                    || isShortAllCapsAcronym(t)
            } else {
                hasHolderSignal = entityTokens.contains(where: { t in
                    let lt = t.lowercased()
                    return knownCreditEntities.contains(lt)
                        || creditOrgDesignators.contains(lt)
                        || matchesRegex(creditDomainRegex, lt)
                        || isShortAllCapsAcronym(t)
                }) || isRecognizedGivenName(entityTokens[0])
            }
            guard hasHolderSignal else { return false }

            let suffix = tokens[(yearIdx + 1)...].map { $0.lowercased() }
            return suffix.isEmpty || suffix == ["all", "rights", "reserved"] || suffix == ["alle", "rechte", "vorbehalten"]
        }

        return false
    }

    private static func cleanCreditText(_ text: String, trimSet: CharacterSet) -> String {
        var cleanScalars: [UnicodeScalar] = []
        cleanScalars.reserveCapacity(text.unicodeScalars.count)
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            if scalar == "\u{200B}" || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !lastWasSpace {
                    cleanScalars.append(" ")
                    lastWasSpace = true
                }
            } else if scalar.properties.generalCategory != .format {
                cleanScalars.append(scalar)
                lastWasSpace = false
            }
        }
        return String(String.UnicodeScalarView(cleanScalars))
            .trimmingCharacters(in: trimSet)
    }

    private static func isDynamicCredit(_ text: String) -> Bool {
        let cleaned = cleanCreditText(text.precomposedStringWithCompatibilityMapping, trimSet: creditEdgeTrimSet)
        guard !cleaned.isEmpty else { return false }
        let rawCleaned = cleanCreditText(text, trimSet: creditNonDotEdgeTrimSet)

        let lower = cleaned.lowercased()
        if lower == "all rights reserved" || lower == "alle rechte vorbehalten" {
            return true
        }

        let isAllCaps = !cleaned.contains(where: \.isLowercase) && cleaned.contains(where: \.isLetter)

        if cleaned.hasPrefix("©") {
            return !containsSentenceVerbOrTechTerm(lower)
        }

        if matchesRegex(untertitelDerRegex, cleaned) {
            return !containsSentenceVerbOrTechTerm(lower)
        }

        if let rest = firstCaptureGroup(untertitelAuftragRegex, cleaned) {
            let rawRest = firstCaptureGroup(untertitelAuftragRegex, rawCleaned) ?? rest
            return isCreditAttributionPayload(
                rest,
                rawPayload: rawRest,
                mode: .germanSubtitleBy,
                isAllCapsContext: isAllCaps
            )
        }

        if let rest = firstCaptureGroup(copyrightPrefixRegex, cleaned) {
            return isValidCopyrightClause(rest, isAllCapsContext: isAllCaps)
        }

        for (regex, mode) in creditAttributionHeaderRegexes {
            if let payload = firstCaptureGroup(regex, cleaned) {
                let rawPayload = firstCaptureGroup(regex, rawCleaned) ?? payload
                return isCreditAttributionPayload(
                    payload,
                    rawPayload: rawPayload,
                    mode: mode,
                    isAllCapsContext: isAllCaps
                )
            }
        }

        return false
    }

    private static func isCreditContinuationClause(_ clause: String) -> Bool {
        let cleaned = cleanCreditText(clause.precomposedStringWithCompatibilityMapping, trimSet: creditEdgeTrimSet)
        guard !cleaned.isEmpty else { return false }
        let lower = cleaned.lowercased()
        guard !containsSentenceVerbOrTechTerm(lower) else { return false }

        if isFourDigitYear(cleaned) {
            return true
        }
        if lower == "all rights reserved" || lower == "alle rechte vorbehalten" || lower == "©" || lower == "(c)" {
            return true
        }
        if knownCreditEntities.contains(lower) || matchesRegex(creditDomainRegex, lower) {
            return true
        }

        let isAllCaps = !cleaned.contains(where: \.isLowercase) && cleaned.contains(where: \.isLetter)
        if let rest = firstCaptureGroup(untertitelAuftragRegex, "untertitel " + cleaned) {
            return isCreditAttributionPayload(rest, rawPayload: rest, mode: .germanSubtitleBy, isAllCapsContext: isAllCaps)
        }

        guard !matchesRegex(germanProseParticleRegex, lower) else { return false }

        let tokens = cleaned.split(whereSeparator: \.isWhitespace).map {
            String($0).trimmingCharacters(in: creditEdgeTrimSet)
        }
        guard !tokens.isEmpty, tokens.count <= 4, tokens.allSatisfy({ !$0.isEmpty }) else { return false }
        guard tokens.allSatisfy({ t in
            let lt = t.lowercased()
            return !nonCreditFunctionWords.contains(lt)
                && !isNumeralToken(lt)
                && !isMeasurementUnitToken(lt)
                && (isAllCaps || startsWithUppercaseLetter(t) || knownCreditEntities.contains(lt) || creditOrgDesignators.contains(lt) || matchesRegex(creditDomainRegex, lt))
        }) else {
            return false
        }

        return tokens.contains { t in
            let lt = t.lowercased()
            return knownCreditEntities.contains(lt)
                || creditOrgDesignators.contains(lt)
                || matchesRegex(creditDomainRegex, lt)
        }
    }

    private static func isPureHallucination(_ text: String) -> Bool {
        if isDynamicCredit(text) { return true }
        let norm = normalizeForMatching(text)
        let normNoDots = normalizeRemovingDots(text)
        guard !norm.isEmpty else { return false }

        if pureHallucinationPhrases.contains(norm) || pureHallucinationPhrases.contains(normNoDots) {
            return true
        }
        for phrase in pureHallucinationPhrases {
            if norm.contains(phrase) || normNoDots.contains(phrase) {
                return true
            }
        }
        return false
    }

    private static func isStandaloneBoilerplateNormalized(_ norm: String) -> Bool {
        guard !norm.isEmpty else { return false }
        if standaloneBoilerplatePhrases.contains(norm) {
            return true
        }
        let tokens = norm.split(separator: " ").map(String.init)
        guard !tokens.isEmpty,
              let first = tokens.first,
              standaloneBoilerplateFirstWords.contains(first),
              tokens.allSatisfy({ standaloneBoilerplateAllWords.contains($0) }) else {
            return false
        }

        let n = tokens.count
        var dp = [Bool](repeating: false, count: n + 1)
        dp[0] = true

        for i in 0..<n where dp[i] {
            var candidate = tokens[i]
            if standaloneBoilerplatePhrases.contains(candidate) {
                dp[i + 1] = true
            }
            var len = 2
            while len <= standaloneBoilerplateMaxWords && (i + len) <= n {
                candidate.append(" ")
                candidate.append(tokens[i + len - 1])
                if standaloneBoilerplatePhrases.contains(candidate) {
                    dp[i + len] = true
                }
                len += 1
            }
            if dp[n] { return true }
        }

        return dp[n]
    }

    private static func isStandaloneBoilerplate(_ text: String) -> Bool {
        isStandaloneBoilerplateNormalized(normalizeForMatching(text))
    }

    private func isStandaloneBoilerplateSegment(_ text: String) -> Bool {
        let norm = Self.normalizeForMatching(text)
        if Self.isStandaloneBoilerplateNormalized(norm) {
            return true
        }
        let sentences = splitSentences(text)
        if sentences.count >= 2 {
            let nonEmptyNorms = sentences.map { Self.normalizeForMatching($0) }.filter { !$0.isEmpty }
            if !nonEmptyNorms.isEmpty && nonEmptyNorms.allSatisfy({ Self.isStandaloneBoilerplateNormalized($0) }) {
                return true
            }
        }
        return false
    }

    private static func isKnownHallucination(_ normalized: String) -> Bool {
        if isPureHallucination(normalized) { return true }
        return isStandaloneBoilerplateNormalized(normalized)
    }

    private static func evaluateCommaClauseStripMask(rawClauses: [String]) -> [Bool] {
        var stripMask = [Bool](repeating: false, count: rawClauses.count)
        var dynamicCreditMask = [Bool](repeating: false, count: rawClauses.count)

        for i in 0..<rawClauses.count {
            if rawClauses[i].isEmpty {
                stripMask[i] = true
                continue
            }
            if isDynamicCredit(rawClauses[i]) {
                stripMask[i] = true
                dynamicCreditMask[i] = true
                continue
            }
            if isPureHallucination(rawClauses[i]) {
                stripMask[i] = true
                continue
            }
            for j in (i + 1)..<rawClauses.count {
                guard !rawClauses[j].isEmpty else { continue }
                let spanText = rawClauses[i...j].joined(separator: " ")
                let spanNorm = normalizeForMatching(spanText)
                let spanNormNoDots = normalizeRemovingDots(spanText)
                guard !spanNorm.isEmpty else { continue }

                let isExactSpan = pureHallucinationPhrases.contains(spanNorm)
                    || pureHallucinationPhrases.contains(spanNormNoDots)
                let isAnchoredSuffixSpan = spanNorm.split(separator: " ").count >= 3
                    && pureHallucinationPhrases.contains { phrase in
                        phrase.contains(" ") && (phrase.hasSuffix(" " + spanNorm) || phrase.hasSuffix(" " + spanNormNoDots))
                    }
                    && pureHallucinationPhrases.contains { phrase in
                        spanNorm.contains(phrase) || spanNormNoDots.contains(phrase)
                    }
                if isExactSpan || isAnchoredSuffixSpan {
                    for k in i...j { stripMask[k] = true }
                } else if !stripMask[i] && isDynamicCredit(spanText) {
                    for k in i...j {
                        stripMask[k] = true
                        dynamicCreditMask[k] = true
                    }
                }
            }
        }

        if rawClauses.count >= 2 {
            for i in 1..<rawClauses.count {
                if !stripMask[i] && dynamicCreditMask[i - 1] && isCreditContinuationClause(rawClauses[i]) {
                    stripMask[i] = true
                    dynamicCreditMask[i] = true
                }
            }
        }

        return stripMask
    }

    private static func stripTierAHallucination(from sentence: String) -> String? {
        if isDynamicCredit(sentence) { return nil }
        let norm = normalizeForMatching(sentence)
        let normNoDots = normalizeRemovingDots(sentence)
        guard !norm.isEmpty else { return nil }

        if pureHallucinationPhrases.contains(norm) || pureHallucinationPhrases.contains(normNoDots) {
            return nil
        }

        // If a comma-delimited sentence mixes a Tier A hallucination clause or dynamic credit
        // with real speech, strip only the hallucinated clause(s)/span(s) and keep real speech.
        if sentence.contains(",") {
            let terminalPunct: Character? = sentence.last.flatMap { [".", "!", "?"].contains($0) ? $0 : nil }
            let rawClauses = sentence.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let stripMask = evaluateCommaClauseStripMask(rawClauses: rawClauses)

            if stripMask.contains(true) {
                let surviving = rawClauses.enumerated()
                    .filter { !stripMask[$0.offset] && !$0.element.isEmpty }
                    .map(\.element)
                guard !surviving.isEmpty else { return nil }
                var rejoined = surviving.joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
                if let punct = terminalPunct, let last = rejoined.last, ![".", "!", "?"].contains(last) {
                    rejoined.append(punct)
                }
                return rejoined.isEmpty ? nil : rejoined
            }
        }

        let containsPurePhrase = pureHallucinationPhrases.contains { phrase in
            norm.contains(phrase) || normNoDots.contains(phrase)
        }
        return containsPurePhrase ? nil : sentence
    }

    private static func endsWithPersonInitialOrTitle(_ sentence: String) -> Bool {
        guard let lastRaw = sentence.split(whereSeparator: \.isWhitespace).last.map(String.init) else {
            return false
        }
        let trimmed = lastRaw.trimmingCharacters(in: creditNonDotEdgeTrimSet)
        if isPersonInitialToken(trimmed) {
            return true
        }
        return ["dr.", "prof."].contains(trimmed.lowercased())
    }

    private static func mergeInitialCreditSentences(_ sentences: [String]) -> [String] {
        guard sentences.count >= 2 else { return sentences }
        var merged: [String] = []
        var i = 0
        while i < sentences.count {
            if endsWithPersonInitialOrTitle(sentences[i]) {
                var matchedEnd: Int? = nil
                let maxEnd = min(sentences.count - 1, i + 3)
                if i + 1 <= maxEnd {
                    for j in (i + 1)...maxEnd {
                        let candidate = sentences[i...j].joined(separator: " ")
                        if isDynamicCredit(candidate) {
                            matchedEnd = j
                        }
                    }
                }
                if let endIdx = matchedEnd {
                    merged.append(sentences[i...endIdx].joined(separator: " "))
                    i = endIdx + 1
                    continue
                }
            }
            merged.append(sentences[i])
            i += 1
        }
        return merged
    }

    private func filterHallucinations(from text: String, filterStandaloneBoilerplate: Bool) -> String {
        // Split into sentences preserving punctuation so embedded Tier A sentences/clauses can be stripped
        // without discarding adjacent legitimate speech in the same segment.
        let sentences = Self.mergeInitialCreditSentences(splitSentences(text))
        let filtered = sentences.compactMap { Self.stripTierAHallucination(from: $0) }
        let joined = filtered.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if joined.isEmpty {
            return ""
        }
        if filterStandaloneBoilerplate && isStandaloneBoilerplateSegment(joined) {
            return ""
        }
        return joined
    }

    private func splitSentences(_ text: String) -> [String] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(?:(?<=[.!?])\s+|\s*\n+\s*)"#) else {
            return [text]
        }
        var result: [String] = []
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            let range = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            let piece = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                result.append(piece)
            }
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < ns.length {
            let tail = ns.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                result.append(tail)
            }
        }
        return result.isEmpty ? [text] : result
    }

    /// Deduplicates intra-segment repetitive loops where phrases or sentences repeat.
    public func deduplicatePhrases(_ text: String) -> String {
        // Pass 1: Collapse duplicate multi-word sentences (> 3 words) within the same segment
        let sentenceDeduped = deduplicateSentences(text)

        let words = sentenceDeduped.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count >= 2 else { return sentenceDeduped }

        func normWord(_ w: String) -> String {
            let nw = Self.normalizeForMatching(w)
            return nw.isEmpty ? w.lowercased() : nw
        }
        let normWords = words.map { normWord($0) }

        var resultWords: [String] = []
        var i = 0
        let total = words.count

        while i < total {
            var foundRepeat = false
            let maxWindow = min(200, (total - i) / 2)
            if maxWindow >= 1 {
                for window in stride(from: maxWindow, through: 1, by: -1) {
                    if normWords[i] != normWords[i + window] {
                        continue
                    }
                    let currentSlice = normWords[i ..< (i + window)]
                    if window > 1 && Set(currentSlice).count <= 1 {
                        continue
                    }

                    var count = 1
                    while (i + (count + 1) * window) <= total {
                        let nextSlice = normWords[(i + count * window) ..< (i + (count + 1) * window)]
                        if currentSlice.elementsEqual(nextSlice) {
                            count += 1
                        } else {
                            break
                        }
                    }

                    let endsSentence = words[i + window - 1].last.map { [".", "?", "!"].contains(String($0)) } ?? false
                    let isTierBSlice = (window <= 3) && Self.isStandaloneBoilerplateNormalized(currentSlice.joined(separator: " "))

                    let shouldCollapse: Bool
                    if window == 1 {
                        shouldCollapse = (count >= 3) || (count >= 2 && isTierBSlice)
                    } else if window <= 3 {
                        shouldCollapse = (count >= 3) || (count >= 2 && (endsSentence || isTierBSlice))
                    } else {
                        shouldCollapse = (count >= 2)
                    }

                    // Primitive-period guard: if `window` is an exact multiple m >= 2 of a smaller
                    // subWindow >= 2 that also collapses, defer to the smaller primitive period so
                    // [P]^4 collapses to [P]^1 instead of [P]^2.
                    if shouldCollapse && window >= 4 {
                        var isNonPrimitiveMultiple = false
                        for subWindow in 2...(window / 2) where window % subWindow == 0 {
                            let m = window / subWindow
                            let subSlice = normWords[i ..< (i + subWindow)]
                            var allMatch = true
                            for rep in 1..<m {
                                let repSlice = normWords[(i + rep * subWindow) ..< (i + (rep + 1) * subWindow)]
                                if !subSlice.elementsEqual(repSlice) {
                                    allMatch = false
                                    break
                                }
                            }
                            if allMatch {
                                let totalSubCount = count * m
                                let subEndsSentence = words[i + subWindow - 1].last.map { [".", "?", "!"].contains(String($0)) } ?? false
                                let subIsTierBSlice = (subWindow <= 3) && Self.isStandaloneBoilerplateNormalized(subSlice.joined(separator: " "))
                                let subWouldCollapse = (subWindow <= 3)
                                    ? (totalSubCount >= 3 || (totalSubCount >= 2 && (subEndsSentence || subIsTierBSlice)))
                                    : (totalSubCount >= 2)
                                if subWouldCollapse {
                                    isNonPrimitiveMultiple = true
                                    break
                                }
                            }
                        }
                        if isNonPrimitiveMultiple {
                            continue
                        }
                    }

                    if shouldCollapse {
                        let keepCount = (window == 1 && count >= 3 && !isTierBSlice) ? 2 : 1
                        for k in 0 ..< (keepCount * window) {
                            resultWords.append(words[i + k])
                        }

                        let lastRepeatedWord = words[i + count * window - 1]
                        if let lastChar = lastRepeatedWord.last, [".", "?", "!"].contains(String(lastChar)) {
                            if let lastKept = resultWords.last, let keptChar = lastKept.last, ![".", "?", "!"].contains(String(keptChar)) {
                                var cleanedKept = lastKept.trimmingCharacters(in: CharacterSet(charactersIn: ",;:-"))
                                cleanedKept.append(lastChar)
                                resultWords[resultWords.count - 1] = cleanedKept
                            }
                        } else if i + count * window == total,
                                  let lastChar = lastRepeatedWord.last,
                                  ![",", ";", ":", "-"].contains(String(lastChar)),
                                  let lastKept = resultWords.last,
                                  let keptChar = lastKept.last,
                                  [",", ";", ":", "-"].contains(String(keptChar)) {
                            let cleanedKept = lastKept.trimmingCharacters(in: CharacterSet(charactersIn: ",;:-"))
                            if !cleanedKept.isEmpty {
                                resultWords[resultWords.count - 1] = cleanedKept
                            }
                        }

                        i += count * window
                        foundRepeat = true
                        break
                    }
                }
            }

            if !foundRepeat {
                resultWords.append(words[i])
                i += 1
            }
        }

        return resultWords.joined(separator: " ")
    }

    private func deduplicateSentences(_ text: String) -> String {
        let sentences = splitSentences(text)
        guard sentences.count >= 2 else { return text }

        var kept: [String] = []
        var seenMultiWordSentences: Set<String> = []
        var lastSingleWordNorm: String = ""
        var singleWordRepeatCount = 0

        for sentence in sentences {
            let norm = Self.normalizeForMatching(sentence)
            guard !norm.isEmpty else { continue }
            let wordCount = norm.split(separator: " ").count

            if wordCount >= 4 {
                if seenMultiWordSentences.contains(norm) {
                    continue
                }
                seenMultiWordSentences.insert(norm)
                kept.append(sentence)
                lastSingleWordNorm = ""
                singleWordRepeatCount = 0
            } else {
                if norm == lastSingleWordNorm {
                    singleWordRepeatCount += 1
                    let isTierBSingleWord = (wordCount == 1) && Self.standaloneBoilerplatePhrases.contains(norm)
                    if (wordCount >= 2 || isTierBSingleWord) && singleWordRepeatCount >= 2 {
                        continue
                    }
                } else {
                    lastSingleWordNorm = norm
                    singleWordRepeatCount = 1
                }
                kept.append(sentence)
            }
        }

        return kept.isEmpty ? "" : kept.joined(separator: " ")
    }

    // MARK: - Compression Ratio & N-Gram Entropy Collapse Check

    private static func zlibCompressionRatio(of text: String) -> Double {
        let data = Array(text.lowercased().utf8)
        guard !data.isEmpty else { return 1.0 }
        let dstCapacity = data.count + 64
        var dstBuffer = [UInt8](repeating: 0, count: dstCapacity)
        let compressedSize = data.withUnsafeBufferPointer { srcPtr -> Int in
            guard let srcBase = srcPtr.baseAddress else { return 0 }
            return dstBuffer.withUnsafeMutableBufferPointer { dstPtr -> Int in
                guard let dstBase = dstPtr.baseAddress else { return 0 }
                return compression_encode_buffer(
                    dstBase, dstCapacity,
                    srcBase, data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard compressedSize > 0 else { return 1.0 }
        return Double(data.count) / Double(compressedSize)
    }

    private static func ngramDiversity(words: [String], n: Int) -> Double {
        guard words.count >= n, n > 0 else { return 1.0 }
        let total = words.count - n + 1
        var seen: Set<String> = []
        seen.reserveCapacity(total)
        for i in 0..<total {
            let ngram = words[i..<(i + n)].joined(separator: "\u{001F}")
            seen.insert(ngram)
        }
        return Double(seen.count) / Double(total)
    }

    private static let collapseFillerTokens: Set<String> = [
        "__NUM__",
        // German closed-class conjunctions, particles, adverbs, pronouns, determiners, prepositions, auxiliaries
        "und", "oder", "aber", "denn", "doch", "noch", "auch", "schon", "mal", "ja", "nein",
        "so", "da", "hier", "dort", "vorn", "hinten", "oben", "unten",
        "dann", "nun", "jetzt", "eben", "halt", "wohl", "etwa", "gar", "sehr", "nur", "immer", "wieder",
        "es", "das", "die", "der", "dem", "den", "des", "ein", "eine", "einen", "einem", "einer", "eines",
        "ich", "du", "er", "sie", "wir", "ihr", "man", "sich", "mir", "mich", "dir", "dich", "ihm", "ihn", "uns", "euch",
        "dies", "diese", "dieser", "dieses", "diesem", "diesen",
        "ist", "sind", "war", "waren", "bin", "bist", "seid", "sei",
        "hat", "haben", "hatte", "hatten", "wird", "werden", "wurde", "wurden",
        "in", "im", "an", "am", "auf", "aus", "bei", "mit", "nach", "von", "vom", "vor", "zu", "zum", "zur", "für", "über", "unter",
        "wie", "wo", "was", "wer", "wann", "warum", "ob", "als", "wenn", "weil", "dass", "daß",
        "nicht", "kein", "keine", "keinen", "keinem", "keiner",
        // English closed-class equivalents
        "and", "or", "but", "then", "now", "so", "yes", "no", "just", "here", "there",
        "it", "this", "that", "the", "a", "an", "is", "are", "was", "were", "be", "have", "has", "had",
        "i", "you", "he", "she", "we", "they", "in", "on", "at", "to", "for", "of", "with", "by", "from"
    ]

    private static func rawNormalizedWords(for text: String) -> [String] {
        normalizeForMatching(text)
            .split(separator: " ")
            .map(String.init)
    }

    private static func collapseMetricWords(from rawWords: [String]) -> [String] {
        rawWords.map { s in
            (!s.isEmpty && s.allSatisfy(\.isNumber)) ? "__NUM__" : s
        }
    }

    private static func collapseMetricWords(for text: String) -> [String] {
        collapseMetricWords(from: rawNormalizedWords(for: text))
    }

    /// Protects valid short numbered enumerations (e.g. "Schritt 1. ... Schritt 6.",
    /// "Punkt 1. ... Punkt 8.", "Phase 1 fertig. ... Phase 6 fertig.") from being
    /// collapsed solely because `__NUM__` normalizes distinct numbers into one token.
    private static func isShortDistinctNumericEnumeration(rawWords: [String]) -> Bool {
        guard rawWords.count <= 30 else { return false }
        let rawNumbers = rawWords.filter { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        guard rawNumbers.count >= 4 && rawNumbers.count <= 10 else { return false }
        let distinctCount = Set(rawNumbers).count
        guard distinctCount >= rawNumbers.count - 1 else { return false }
        return ngramDiversity(words: rawWords, n: 1) > 0.41
    }

    private static func isCollapsedMetrics(_ words: [String]) -> Bool {
        guard words.count >= 12 else { return false }
        return ngramDiversity(words: words, n: 1) < 0.35
            || ngramDiversity(words: words, n: 2) < 0.45
            || ngramDiversity(words: words, n: 3) < 0.55
    }

    private static func findCollapseCutIndex(
        sentences: [String],
        maxCompressionRatio: Double,
        requireStrictPrefix: Bool
    ) -> Int? {
        let m = sentences.count
        guard m > 0 else { return nil }
        let sRaw = sentences.map { rawNormalizedWords(for: $0) }
        let sMetrics = sRaw.map { collapseMetricWords(from: $0) }

        var coreStart: Int? = nil
        for c in stride(from: m - 1, through: 0, by: -1) {
            let suffixSentences = sentences[c..<m]
            let suffixWords = sMetrics[c..<m].flatMap { $0 }
            guard suffixWords.count >= 12 else { continue }
            let suffixRawWords = sRaw[c..<m].flatMap { $0 }
            if isShortDistinctNumericEnumeration(rawWords: suffixRawWords) {
                continue
            }
            let suffixText = suffixSentences.joined(separator: " ")

            let cond1 = suffixText.utf8.count >= 80
                && zlibCompressionRatio(of: suffixText) > maxCompressionRatio
                && isCollapsedMetrics(suffixWords)
            let cond2 = suffixSentences.count >= 6
                && sMetrics[c..<m].allSatisfy({ $0.count <= 3 })
                && ngramDiversity(words: suffixWords, n: 1) < 0.35
            let cond3 = suffixSentences.count >= 8
                && sMetrics[c..<m].allSatisfy({ $0.count == 1 })
                && ngramDiversity(words: suffixWords, n: 1) <= 0.45

            if cond1 || cond2 || cond3 {
                coreStart = c
                break
            }
        }

        guard let startIdx = coreStart else { return nil }

        var tailVocab = Set(sMetrics[startIdx..<m].flatMap { $0 })
        var cut = startIdx

        if startIdx > 0 {
            let coreAllMultiWord = sMetrics[startIdx..<m].allSatisfy { $0.count >= 2 }
            let coreAllHaveNum = sMetrics[startIdx..<m].allSatisfy { $0.contains("__NUM__") }
            for i in stride(from: startIdx - 1, through: 0, by: -1) {
                let w = sMetrics[i]
                if w.isEmpty {
                    cut = i
                    continue
                }
                if w.count >= 4 && (ngramDiversity(words: w, n: 3) < 0.55 || (w.count >= 6 && ngramDiversity(words: w, n: 1) < 0.35)) {
                    cut = i
                    tailVocab.formUnion(w)
                    continue
                }
                if w.count == 1 && coreAllMultiWord {
                    break
                }
                let isPureFillerSentence = w.allSatisfy { collapseFillerTokens.contains($0) }
                if coreAllHaveNum && !w.contains("__NUM__") && !isPureFillerSentence {
                    break
                }

                let inTailCount = w.filter { tailVocab.contains($0) }.count
                let novelCount = w.count - inTailCount
                let overlap = Double(inTailCount) / Double(w.count)
                let fillerThreshold = (w.count == 4) ? 0.75 : 0.60
                let isPureFillerExtension = w.count >= 4
                    && overlap >= fillerThreshold
                    && isPureFillerSentence

                if (novelCount == 0 || isPureFillerExtension)
                    && isCollapsedMetrics(sMetrics[i..<m].flatMap { $0 }) {
                    cut = i
                    tailVocab.formUnion(w)
                    continue
                }
                break
            }
        }

        if requireStrictPrefix && cut == 0 {
            return nil
        }
        return cut
    }

    private func trimCollapsedTail(_ text: String, maxCompressionRatio: Double) -> String {
        let sentences = splitSentences(text)
        guard sentences.count >= 4 else { return text }
        if let cut = Self.findCollapseCutIndex(
            sentences: sentences,
            maxCompressionRatio: maxCompressionRatio,
            requireStrictPrefix: true
        ) {
            return sentences[0..<cut].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func filterEntropyCollapse(_ text: String, maxCompressionRatio: Double) -> String {
        let sentences = splitSentences(text)
        if sentences.count > 1,
           let cut = Self.findCollapseCutIndex(
               sentences: sentences,
               maxCompressionRatio: maxCompressionRatio,
               requireStrictPrefix: false
           ) {
            if cut == 0 {
                Log.warning("Entropy-collapsed multi-sentence hallucination segment pruned")
                return ""
            }
            return sentences[0..<cut].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard text.utf8.count >= 80 else { return text }
        let rawWords = Self.rawNormalizedWords(for: text)
        guard !Self.isShortDistinctNumericEnumeration(rawWords: rawWords) else { return text }
        let metricWords = Self.collapseMetricWords(from: rawWords)
        guard metricWords.count >= 12 else { return text }

        let ratio = Self.zlibCompressionRatio(of: text)
        guard ratio > maxCompressionRatio, Self.isCollapsedMetrics(metricWords) else { return text }

        let trigramDiv = Self.ngramDiversity(words: metricWords, n: 3)
        Log.warning("Entropy-collapsed hallucination segment pruned (zlib ratio: \(String(format: "%.2f", ratio)), trigramDiv: \(String(format: "%.2f", trigramDiv)))")
        return ""
    }

    // MARK: - Word Alignment Helper

    private static func wordMatches(_ orig: Word, targetToken: String, normTarget: String) -> Bool {
        if orig.text == targetToken {
            return true
        }
        guard !normTarget.isEmpty else {
            return false
        }
        return normalizeForMatching(orig.text) == normTarget
    }

    private static func computeStrippedTierAMask(originalWords: [Word]) -> [Bool] {
        var mask = [Bool](repeating: false, count: originalWords.count)
        guard !originalWords.isEmpty else { return mask }

        var sentenceRanges: [Range<Int>] = []
        var startIdx = 0
        for i in 0..<originalWords.count {
            let trimmed = originalWords[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = trimmed.last, [".", "!", "?"].contains(last) {
                sentenceRanges.append(startIdx..<(i + 1))
                startIdx = i + 1
            }
        }
        if startIdx < originalWords.count {
            sentenceRanges.append(startIdx..<originalWords.count)
        }

        // Merge sentence ranges split on a person initial or title (e.g. "A.", "H.-P.", "Dr.") inside a dynamic credit
        if sentenceRanges.count >= 2 {
            var mergedRanges: [Range<Int>] = []
            var rIdx = 0
            while rIdx < sentenceRanges.count {
                let firstText = originalWords[sentenceRanges[rIdx]].map(\.text).joined(separator: " ")
                if endsWithPersonInitialOrTitle(firstText) {
                    var matchedEnd: Int? = nil
                    let maxEnd = min(sentenceRanges.count - 1, rIdx + 3)
                    if rIdx + 1 <= maxEnd {
                        for j in (rIdx + 1)...maxEnd {
                            let mergedRange = sentenceRanges[rIdx].lowerBound..<sentenceRanges[j].upperBound
                            let candidate = originalWords[mergedRange].map(\.text).joined(separator: " ")
                            if isDynamicCredit(candidate) {
                                matchedEnd = j
                            }
                        }
                    }
                    if let endIdx = matchedEnd {
                        mergedRanges.append(sentenceRanges[rIdx].lowerBound..<sentenceRanges[endIdx].upperBound)
                        rIdx = endIdx + 1
                        continue
                    }
                }
                mergedRanges.append(sentenceRanges[rIdx])
                rIdx += 1
            }
            sentenceRanges = mergedRanges
        }

        for range in sentenceRanges {
            let sentenceText = originalWords[range].map(\.text).joined(separator: " ")
            if stripTierAHallucination(from: sentenceText) == nil {
                for i in range { mask[i] = true }
                continue
            }

            if sentenceText.contains(",") {
                var clauseRanges: [Range<Int>] = []
                var cStart = range.lowerBound
                for i in range {
                    let trimmed = originalWords[i].text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.hasSuffix(",") {
                        clauseRanges.append(cStart..<(i + 1))
                        cStart = i + 1
                    }
                }
                if cStart < range.upperBound {
                    clauseRanges.append(cStart..<range.upperBound)
                }

                let rawClauses = clauseRanges.map { cr -> String in
                    let joined = originalWords[cr].map(\.text).joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return joined.hasSuffix(",")
                        ? String(joined.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                        : joined
                }

                let stripClauseMask = evaluateCommaClauseStripMask(rawClauses: rawClauses)
                for (cIdx, shouldStrip) in stripClauseMask.enumerated() where shouldStrip {
                    for wordIdx in clauseRanges[cIdx] {
                        mask[wordIdx] = true
                    }
                }
            }
        }

        // Unpunctuated fallback: mark contiguous word spans matching pureHallucinationPhrases
        if pureHallucinationMaxWords > 0 {
            let origNorms = originalWords.map { normalizeForMatching($0.text) }
            for i in 0..<originalWords.count {
                var phrase = ""
                let upper = min(originalWords.count, i + pureHallucinationMaxWords)
                for j in i..<upper {
                    let nw = origNorms[j]
                    guard !nw.isEmpty else { break }
                    phrase = phrase.isEmpty ? nw : (phrase + " " + nw)
                    if pureHallucinationPhrases.contains(phrase) {
                        for k in i...j { mask[k] = true }
                    }
                }
            }
        }

        return mask
    }

    private struct AlignMatch: Sendable {
        let startOrigIdx: Int
        let endOrigIdx: Int
        let cost: Int
        let word: Word
    }

    private static func alignWords(originalWords: [Word], cleanedText: String, start: Double, end: Double) -> [Word] {
        guard !originalWords.isEmpty else { return [] }
        let targetTokens = cleanedText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !targetTokens.isEmpty else { return [] }

        let targetNorms = targetTokens.map { normalizeForMatching($0) }
        let strippedMask = computeStrippedTierAMask(originalWords: originalWords)

        let tierAPenalty = 1_000_000
        let gapPenalty = 1_000
        let infCost = Int.max / 4

        var allMatches: [[AlignMatch]] = []
        allMatches.reserveCapacity(targetTokens.count)

        for tIdx in 0..<targetTokens.count {
            let token = targetTokens[tIdx]
            let normToken = targetNorms[tIdx]
            var matchesForToken: [AlignMatch] = []

            for j in 0..<originalWords.count {
                let w0 = originalWords[j]
                if wordMatches(w0, targetToken: token, normTarget: normToken) {
                    let c = strippedMask[j] ? tierAPenalty : 0
                    matchesForToken.append(AlignMatch(
                        startOrigIdx: j,
                        endOrigIdx: j,
                        cost: c,
                        word: Word(text: token, start: w0.start, end: w0.end, confidence: w0.confidence)
                    ))
                }
                if !normToken.isEmpty && (j + 1) < originalWords.count {
                    let w1 = originalWords[j + 1]
                    let combined = w0.text + w1.text
                    if combined == token || normalizeForMatching(combined) == normToken {
                        let c = ((strippedMask[j] || strippedMask[j + 1]) ? tierAPenalty : 0) + 1
                        matchesForToken.append(AlignMatch(
                            startOrigIdx: j,
                            endOrigIdx: j + 1,
                            cost: c,
                            word: Word(
                                text: token,
                                start: w0.start,
                                end: w1.end,
                                confidence: min(w0.confidence, w1.confidence)
                            )
                        ))
                    }
                }
            }

            if matchesForToken.isEmpty {
                return Segment.interpolateWords(for: cleanedText, start: start, end: end)
            }
            allMatches.append(matchesForToken)
        }

        let m = targetTokens.count
        var prevCosts = allMatches[0].map(\.cost)
        var backPtr = [[Int]](repeating: [], count: m)
        backPtr[0] = [Int](repeating: -1, count: allMatches[0].count)

        for tIdx in 1..<m {
            let prevMatches = allMatches[tIdx - 1]
            let currMatches = allMatches[tIdx]

            let prevSortedIndices = (0..<prevMatches.count).sorted {
                if prevMatches[$0].endOrigIdx != prevMatches[$1].endOrigIdx {
                    return prevMatches[$0].endOrigIdx < prevMatches[$1].endOrigIdx
                }
                return prevMatches[$0].startOrigIdx < prevMatches[$1].startOrigIdx
            }

            var bestAtEnd: [Int: (cost: Int, prevPos: Int)] = [:]
            for pIdx in prevSortedIndices {
                let cost = prevCosts[pIdx]
                guard cost < infCost else { continue }
                let e = prevMatches[pIdx].endOrigIdx
                if let existing = bestAtEnd[e] {
                    if cost < existing.cost {
                        bestAtEnd[e] = (cost, pIdx)
                    }
                } else {
                    bestAtEnd[e] = (cost, pIdx)
                }
            }

            var currCosts = [Int](repeating: infCost, count: currMatches.count)
            var currBack = [Int](repeating: -1, count: currMatches.count)
            var ptr = 0
            var bestPrevCost = infCost
            var bestPrevPos = -1

            for cIdx in 0..<currMatches.count {
                let curr = currMatches[cIdx]
                while ptr < prevSortedIndices.count {
                    let pIdx = prevSortedIndices[ptr]
                    if prevMatches[pIdx].endOrigIdx < curr.startOrigIdx {
                        if prevCosts[pIdx] < bestPrevCost {
                            bestPrevCost = prevCosts[pIdx]
                            bestPrevPos = pIdx
                        }
                        ptr += 1
                    } else {
                        break
                    }
                }

                var chosenCost = infCost
                var chosenPrev = -1

                if bestPrevPos != -1 {
                    chosenCost = bestPrevCost + gapPenalty + curr.cost
                    chosenPrev = bestPrevPos
                }

                if let adj = bestAtEnd[curr.startOrigIdx - 1] {
                    let adjCost = adj.cost + curr.cost
                    if adjCost < chosenCost {
                        chosenCost = adjCost
                        chosenPrev = adj.prevPos
                    }
                }

                currCosts[cIdx] = chosenCost
                currBack[cIdx] = chosenPrev
            }

            prevCosts = currCosts
            backPtr[tIdx] = currBack
        }

        var bestFinalIdx = -1
        var bestFinalCost = infCost
        for cIdx in 0..<allMatches[m - 1].count {
            if prevCosts[cIdx] < bestFinalCost {
                bestFinalCost = prevCosts[cIdx]
                bestFinalIdx = cIdx
            }
        }

        guard bestFinalIdx != -1 else {
            return Segment.interpolateWords(for: cleanedText, start: start, end: end)
        }

        var aligned = [Word?](repeating: nil, count: m)
        var cur = bestFinalIdx
        for tIdx in stride(from: m - 1, through: 0, by: -1) {
            aligned[tIdx] = allMatches[tIdx][cur].word
            cur = backPtr[tIdx][cur]
        }

        return aligned.compactMap { $0 }
    }

    // MARK: - Public Segment & Text Processing

    public func processSegments(segments: [Segment], options: PostProcessorOptions = .init()) -> [Segment] {
        guard !segments.isEmpty else { return [] }

        var cleanedSegments: [Segment] = []
        var emittedConsecutiveCount = 0
        var lastEmittedNormalized = ""
        var recentIncoming: [String] = []

        for segment in segments {
            let originalTrimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var text = originalTrimmed

            // 1. Remove noise tags like [BLANK_AUDIO], [Music], (müzik)
            if options.removeNoiseTags {
                text = cleanNoiseTags(text)
            }
            guard !text.isEmpty else { continue }

            // 2. Two-tier hallucination & boilerplate filtering
            text = filterHallucinations(from: text, filterStandaloneBoilerplate: options.filterStandaloneBoilerplate)
            guard !text.isEmpty else { continue }

            // 3. Intra-segment tail-collapse trimming, phrase deduplication & entropy-collapse filtering
            if options.deduplicateRepetitions {
                text = trimCollapsedTail(text, maxCompressionRatio: options.maxCompressionRatio)
                guard !text.isEmpty else { continue }
                text = deduplicatePhrases(text)
                guard !text.isEmpty else { continue }
                text = filterEntropyCollapse(text, maxCompressionRatio: options.maxCompressionRatio)
                guard !text.isEmpty else { continue }
                // Re-apply hallucination & Tier B check in case deduplication collapsed repeated boilerplate
                text = filterHallucinations(from: text, filterStandaloneBoilerplate: options.filterStandaloneBoilerplate)
            }
            guard !text.isEmpty else { continue }

            // 4. Inter-segment repetition & ping-pong loop detection
            let processedNormalized = Self.normalizeForMatching(text)
            guard !processedNormalized.isEmpty else { continue }

            if options.deduplicateRepetitions {
                let wordCount = processedNormalized.split(separator: " ").count
                var shouldSkip = false

                // Consecutive identical check (must also be consecutive in incoming stream so skipped cycles don't bleed into stale state)
                if recentIncoming.last == processedNormalized && processedNormalized == lastEmittedNormalized {
                    let nextCount = emittedConsecutiveCount + 1
                    let maxAllowed = (wordCount <= 2 && !Self.isKnownHallucination(processedNormalized)) ? 2 : 1
                    if nextCount > maxAllowed {
                        Log.warning("Repetition loop skipped: '\(text)' (time: \(segment.start))")
                        shouldSkip = true
                    }
                }

                // Alternating known hallucination loop within last 4 incoming segments
                if !shouldSkip && !recentIncoming.isEmpty && recentIncoming.suffix(4).contains(processedNormalized) && Self.isKnownHallucination(processedNormalized) {
                    Log.warning("Alternating hallucination loop skipped: '\(text)' (time: \(segment.start))")
                    shouldSkip = true
                }

                // Strict 2-cycle ping-pong loop (A, B, A, B) on incoming stream
                if !shouldSkip && recentIncoming.count >= 3 {
                    let count = recentIncoming.count
                    if recentIncoming[count - 2] == processedNormalized,
                       recentIncoming[count - 1] != processedNormalized,
                       recentIncoming[count - 3] == recentIncoming[count - 1] {
                        Log.warning("Ping-pong loop skipped: '\(text)' (time: \(segment.start))")
                        shouldSkip = true
                    }
                }

                // Full-window periodic k-cycle loop (k = 2..4, e.g. A, B, C, A, B, C, A)
                if !shouldSkip {
                    let count = recentIncoming.count
                    for period in 2...4 {
                        if count >= 2 * period,
                           recentIncoming[count - period] == processedNormalized,
                           recentIncoming[(count - period) ..< count].elementsEqual(
                               recentIncoming[(count - 2 * period) ..< (count - period)]
                           ) {
                            Log.warning("Periodic \(period)-cycle loop skipped: '\(text)' (time: \(segment.start))")
                            shouldSkip = true
                            break
                        }
                    }
                }

                // Non-adjacent cyclic repetition check:
                // 1-2 word non-hallucination confirmations allow spaced 0,2,4 / 0,3,6 / 0,4,8 turns (>= 3 in suffix(5)),
                // while longer segments and known hallucinations use an 8-segment window (>= 2).
                if !shouldSkip {
                    let isKnown = Self.isKnownHallucination(processedNormalized)
                    if wordCount <= 2 && !isKnown {
                        if recentIncoming.suffix(5).filter({ $0 == processedNormalized }).count >= 3 {
                            Log.warning("Cyclic repetition loop skipped: '\(text)' (time: \(segment.start))")
                            shouldSkip = true
                        }
                    } else {
                        if recentIncoming.suffix(8).filter({ $0 == processedNormalized }).count >= 2 {
                            Log.warning("Cyclic repetition loop skipped: '\(text)' (time: \(segment.start))")
                            shouldSkip = true
                        }
                    }
                }

                recentIncoming.append(processedNormalized)
                if recentIncoming.count > 12 {
                    recentIncoming.removeFirst()
                }

                if shouldSkip {
                    continue
                }

                if processedNormalized == lastEmittedNormalized {
                    emittedConsecutiveCount += 1
                } else {
                    lastEmittedNormalized = processedNormalized
                    emittedConsecutiveCount = 1
                }
            }

            let preservedWords: [Word]
            if text == originalTrimmed {
                preservedWords = segment.words
            } else {
                preservedWords = Self.alignWords(
                    originalWords: segment.words,
                    cleanedText: text,
                    start: segment.start,
                    end: segment.end
                )
            }

            cleanedSegments.append(
                Segment(
                    start: segment.start,
                    end: segment.end,
                    text: text,
                    speaker: segment.speaker,
                    words: preservedWords,
                    noSpeechProb: segment.noSpeechProb
                )
            )
        }

        return cleanedSegments
    }

    public func process(segments: [Segment], options: PostProcessorOptions = .init()) -> String {
        let cleanedSegments = processSegments(segments: segments, options: options)
        guard !cleanedSegments.isEmpty else { return "" }

        // Paragraphing
        var paragraphs: [String] = []
        var currentParagraphWords: [String] = []
        var currentParagraphLength: Int = 0
        var currentParagraphStart: Double = cleanedSegments[0].start
        var lastSegmentEnd: Double = cleanedSegments[0].start

        for segment in cleanedSegments {
            let silence = segment.start - lastSegmentEnd
            let isSentenceEnding = segment.text.hasSuffix(".") || segment.text.hasSuffix("?") || segment.text.hasSuffix("!")

            let shouldBreak = !currentParagraphWords.isEmpty && (
                (silence >= options.paragraphSilenceThreshold && (currentParagraphLength >= 140 || isSentenceEnding)) ||
                (currentParagraphLength >= options.maxParagraphLength && isSentenceEnding)
            )

            if shouldBreak {
                let paragraphText = finalizeParagraph(
                    words: currentParagraphWords,
                    startTime: currentParagraphStart,
                    withTimestamp: options.insertTimestamps
                )
                paragraphs.append(paragraphText)
                currentParagraphWords.removeAll()
                currentParagraphLength = 0
                currentParagraphStart = segment.start
            }

            currentParagraphLength += currentParagraphWords.isEmpty ? segment.text.count : (segment.text.count + 1)
            currentParagraphWords.append(segment.text)
            lastSegmentEnd = segment.end
        }

        if !currentParagraphWords.isEmpty {
            let paragraphText = finalizeParagraph(
                words: currentParagraphWords,
                startTime: currentParagraphStart,
                withTimestamp: options.insertTimestamps
            )
            paragraphs.append(paragraphText)
        }

        return paragraphs.joined(separator: "\n\n")
    }

    private func cleanNoiseTags(_ text: String) -> String {
        let pattern = #"((\[|\(|\*|♪)\s*(blank_audio|music|applause|laughter|müzik|alkış|gülüş|gülüşmeler|kahkaha|sessizlik|silence|neşeli müzik|\.\.\.)\s*(\]|\)|\*|♪)|♪+)"#
        var cleaned = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func finalizeParagraph(words: [String], startTime: Double, withTimestamp: Bool) -> String {
        let text = words.joined(separator: " ")
        if withTimestamp {
            let timestamp = formatTimestamp(startTime)
            return "[\(timestamp)] \(text)"
        }
        return text
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
