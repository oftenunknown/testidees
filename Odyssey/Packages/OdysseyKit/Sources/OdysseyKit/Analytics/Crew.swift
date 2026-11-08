import Foundation

/// Finds training partners.
///
/// Strava's API tells us *how many* athletes were in a group activity
/// (`athlete_count`) but not *who* they were. So companions come from two
/// places: names you tag in the app, and names written in titles and
/// descriptions ("Long run with Maya & Leo", "w/ @sam").
public enum CrewDetector {
    static let triggers: Set<String> = ["with", "w/", "feat", "feat.", "ft", "ft.", "featuring", "alongside", "avec", "mit", "con", "met", "med"]
    static let joiners: Set<String> = ["and", "&", "+", "y", "und", "et", "en", "og", "e"]
    static let notNames: Set<String> = [
        "the", "a", "an", "my", "our", "some", "friends", "friend", "club", "team", "crew", "group", "everyone",
        "strava", "garmin", "zwift", "mates", "buddies", "colleagues", "work", "family", "kids", "dogs", "legs",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "morning", "afternoon", "evening", "night", "lunch", "intervals", "hills", "strides", "rain", "wind", "snow", "sun", "heat",
        "parkrun", "headwind", "tailwind", "music", "podcast", "podcasts", "pain", "joy", "style",
    ]
    static let titles: Set<String> = ["coach", "uncle", "aunt", "auntie", "cousin", "captain", "dr", "dr."]

    /// Names mentioned in a title or description.
    public static func names(in text: String) -> [String] {
        var found: [String] = []
        // Split keeping separators as their own tokens.
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        for ch in text {
            if ch == "," || ch == "&" || ch == "+" || ch == "!" || ch == "?" || ch == "." || ch == ";" || ch == ":" || ch == "(" || ch == ")" || ch == "|" || ch == "–" || ch == "—" {
                // Keep "w/" and abbreviations like "ft." intact.
                if ch == ".", ["ft", "feat", "dr"].contains(current.lowercased()) { current.append(ch); continue }
                flush()
                tokens.append(String(ch))
            } else if ch.isWhitespace {
                flush()
            } else {
                current.append(ch)
            }
        }
        flush()

        func isCapitalisedWord(_ t: String) -> Bool {
            guard let first = t.first, first.isLetter, first.isUppercase else { return false }
            return t.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }
        }
        func clean(_ name: String) -> String {
            var n = name
            for suffix in ["'s", "’s"] where n.hasSuffix(suffix) { n.removeLast(2) }
            return n
        }

        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            // @mentions anywhere.
            if t.hasPrefix("@"), t.count > 1 {
                let handle = t.dropFirst().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                if !handle.isEmpty {
                    found.append(handle.prefix(1).uppercased() + handle.dropFirst())
                }
                i += 1
                continue
            }
            guard triggers.contains(t.lowercased()) else { i += 1; continue }
            i += 1
            // Collect "Name (Name)*" groups separated by joiners.
            while i < tokens.count {
                var words: [String] = []
                while i < tokens.count, words.count < 3 {
                    let w = tokens[i]
                    if w.hasPrefix("@"), w.count > 1, words.isEmpty {
                        let handle = w.dropFirst().filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                        if !handle.isEmpty { words.append(handle.prefix(1).uppercased() + handle.dropFirst()) }
                        i += 1
                        break
                    }
                    if titles.contains(w.lowercased()), words.isEmpty { i += 1; continue }
                    guard isCapitalisedWord(w), !notNames.contains(w.lowercased()) else { break }
                    words.append(clean(w))
                    i += 1
                }
                if !words.isEmpty { found.append(words.joined(separator: " ")) }
                guard i < tokens.count, joiners.contains(tokens[i].lowercased()) || tokens[i] == "," else { break }
                i += 1
                // Allow ", and" / ", &".
                if i < tokens.count, joiners.contains(tokens[i].lowercased()) { i += 1 }
            }
        }
        // De-duplicate, keeping order.
        var seen = Set<String>()
        return found.filter { seen.insert($0.lowercased()).inserted }
    }

    static func build(activities: [Activity], tags: [Int64: [String]], hidden: Set<String>) -> Crew {
        struct Acc {
            var display: [String: Int] = [:]
            var count = 0
            var distance = 0.0
            var time = 0.0
            var first: LocalDay
            var last: LocalDay
            var families: [SportFamily: Int] = [:]
            var ids: [Int64] = []
            var confirmed = false
        }
        let hiddenKeys = Set(hidden.map { $0.lowercased() })
        var byName: [String: Acc] = [:]
        var groupCount = 0, groupDistance = 0.0, groupTime = 0.0
        var untagged: [Int64] = []
        var biggest: Activity?

        for a in activities {
            let tagged = tags[a.id]
            let names = (tagged ?? (names(in: a.name) + names(in: a.notes ?? "")))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !hiddenKeys.contains($0.lowercased()) }
            var unique: [String] = []
            var seen = Set<String>()
            for n in names where seen.insert(n.lowercased()).inserted { unique.append(n) }

            if a.isGroup || !unique.isEmpty {
                groupCount += 1
                groupDistance += a.distance
                groupTime += a.movingTime
            }
            if a.isGroup, unique.isEmpty, tagged == nil { untagged.append(a.id) }
            if a.athleteCount >= 3, a.athleteCount > (biggest?.athleteCount ?? 0) { biggest = a }

            for n in unique {
                let key = n.lowercased()
                var acc = byName[key] ?? Acc(first: a.day, last: a.day)
                acc.display[n, default: 0] += 1
                acc.count += 1
                acc.distance += a.distance
                acc.time += a.movingTime
                acc.first = min(acc.first, a.day)
                acc.last = max(acc.last, a.day)
                acc.families[a.sport.family, default: 0] += 1
                acc.ids.append(a.id)
                acc.confirmed = acc.confirmed || tagged != nil
                byName[key] = acc
            }
        }

        let companions = byName.values.map { acc in
            Companion(
                name: acc.display.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? "",
                count: acc.count, distance: acc.distance, movingTime: acc.time,
                firstDay: acc.first, lastDay: acc.last,
                families: acc.families.sorted { $0.value > $1.value }.map(\.key),
                activityIDs: acc.ids, confirmed: acc.confirmed
            )
        }
        .sorted { ($0.count, $0.distance, $1.name) > ($1.count, $1.distance, $0.name) }

        let biggestGroup = biggest.map {
            Highlight(kind: .biggestGroup, day: $0.day, activityID: $0.id, name: $0.name, sport: $0.sport, value: Double($0.athleteCount))
        }
        return Crew(
            groupCount: groupCount,
            groupDistance: groupDistance,
            groupTime: groupTime,
            share: activities.isEmpty ? 0 : Double(groupCount) / Double(activities.count),
            biggestGroup: biggestGroup,
            companions: companions,
            untaggedGroupIDs: untagged
        )
    }
}
