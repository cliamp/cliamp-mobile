import Foundation

/// A compact fuzzy matcher in the style of fzf/iTerm: the query characters
/// must appear in order (as a subsequence) in the haystack, and a LOWER score
/// is better. Consecutive runs are cheaper than spread-out matches, and a
/// leading or word-boundary match is cheaper than mid-word, so "aln" ranks
/// above "ana" when searching for "Alan Walker". Ported from Android's
/// `Fuzzy.kt`.
public enum Fuzzy {
    /// Positions (in `haystack`) that form the match, or nil when no match.
    public static func match(query: String, haystack: String) -> [Int]? {
        guard !query.isEmpty else { return [] }
        let q = Array(query.lowercased())
        let h = Array(haystack.lowercased())
        guard q.count <= h.count else { return nil }

        var at: [Int] = []
        at.reserveCapacity(q.count)
        var qi = 0
        for ci in h.indices where qi < q.count {
            if h[ci] == q[qi] {
                at.append(ci)
                qi += 1
            }
        }
        return qi == q.count ? at : nil
    }

    /// Lower is better. `Int.max` means no match.
    public static func score(query: String, haystack: String) -> Int {
        guard let at = match(query: query, haystack: haystack), !at.isEmpty else {
            return query.isEmpty ? 0 : Int.max
        }
        var total = 0
        var previous = -2
        for (index, position) in at.enumerated() {
            if index > 0, position == previous + 1 {
                // Consecutive characters are free.
            } else {
                total += position - previous // gap cost
            }
            previous = position
        }
        if at[0] == 0 { total -= 4 } // reward a prefix match
        if at[0] > 0 {
            let characters = Array(haystack)
            let before = characters[at[0] - 1]
            if before == " " || before == "-" || before == "(" { total -= 2 }
        }
        if haystack.count <= 12 { total -= 1 }
        return total
    }

    /// Char positions that matched, for highlight rendering.
    public static func matchedPositions(query: String, haystack: String) -> Set<Int>? {
        match(query: query, haystack: haystack).map(Set.init)
    }
}
