import Foundation
import Testing

@testable import CliampCore

@Suite("fuzzy matcher")
struct FuzzyTests {
    @Test("a subsequence matches and a gap does not")
    func matching() {
        #expect(Fuzzy.match(query: "aln", haystack: "Alan Walker") != nil)
        #expect(Fuzzy.match(query: "xyz", haystack: "Alan Walker") == nil)
        #expect(Fuzzy.match(query: "", haystack: "anything") == [])
        #expect(Fuzzy.match(query: "longer than hay", haystack: "short") == nil)
    }

    @Test("consecutive and boundary matches rank better")
    func ranking() {
        let consecutive = Fuzzy.score(query: "alan", haystack: "Alan Walker")
        let spread = Fuzzy.score(query: "aln", haystack: "Alan Walker")
        let boundary = Fuzzy.score(query: "walker", haystack: "Alan Walker")
        let midWord = Fuzzy.score(query: "walker", haystack: "Alanzwalker")
        #expect(consecutive < spread)
        #expect(boundary < midWord)
        #expect(Fuzzy.score(query: "zzz", haystack: "Alan Walker") == Int.max)
    }

    @Test("matched positions point at the characters that formed the match")
    func positions() {
        #expect(Fuzzy.matchedPositions(query: "aln", haystack: "Alan") == [0, 1, 3])
        #expect(Fuzzy.matchedPositions(query: "zzz", haystack: "Alan") == nil)
    }
}
