import Foundation
import Testing

@testable import CliampCore

@Suite("radio navigator")
struct RadioNavigatorTests {
    private let a = Station(id: "a", name: "A", url: "https://a.example/stream", source: .directory)
    private let b = Station(id: "b", name: "B", url: "https://b.example/stream", source: .directory)
    private let c = Station(id: "c", name: "C", url: "https://c.example/stream", source: .directory)

    private var ring: [Station] { [a, b, c] }

    private func name(_ decision: RadioNavDecision) -> String? {
        if case .play(let station) = decision { return station.name }
        return nil
    }

    @Test("next steps forward and prev wraps the ring backwards")
    func ringWrap() {
        var navigator = RadioNavigator()
        #expect(name(navigator.next(stations: ring, current: a, nowMs: 0)) == "B")
        #expect(name(navigator.previous(stations: ring, current: a, nowMs: 300)) == "C")
    }

    @Test("a single-item ring has nowhere to go")
    func singleItem() {
        var navigator = RadioNavigator()
        #expect(navigator.next(stations: [a], current: a, nowMs: 0) == .ignore)
        #expect(navigator.previous(stations: [a], current: a, nowMs: 100) == .ignore)
        #expect(navigator.next(stations: [], current: nil, nowMs: 200) == .ignore)
    }

    @Test("a burst coalesces on the last tap and a later tap applies at once")
    func burstDebounce() {
        var navigator = RadioNavigator()
        // Isolated tap: applies immediately, so next feels instant.
        #expect(name(navigator.next(stations: ring, current: a, nowMs: 0)) == "B")
        // Follow-ups inside 180 ms only update the pending target.
        #expect(navigator.next(stations: ring, current: b, nowMs: 50) == .schedule)
        #expect(navigator.next(stations: ring, current: b, nowMs: 120) == .schedule)
        #expect(navigator.takePending(stations: ring)?.name == "A")
        #expect(navigator.takePending(stations: ring) == nil)
        // Past the window a tap is leading-edge again.
        #expect(name(navigator.next(stations: ring, current: a, nowMs: 400)) == "B")
    }

    @Test("prev walks the session log and next redoes it before the ring")
    func sessionPast() {
        var navigator = RadioNavigator()
        navigator.recordPlay(a)
        navigator.recordPlay(b)
        navigator.recordPlay(c)

        #expect(name(navigator.previous(stations: ring, current: c, nowMs: 0)) == "B")
        navigator.recordPlay(b)
        #expect(name(navigator.previous(stations: ring, current: b, nowMs: 0)) == "A")
        navigator.recordPlay(a)
        // Next redoes what was stepped back rather than restarting the ring.
        #expect(name(navigator.next(stations: ring, current: a, nowMs: 0)) == "B")
        navigator.recordPlay(b)
        #expect(name(navigator.next(stations: ring, current: b, nowMs: 0)) == "C")
        navigator.recordPlay(c)
        // At the top of the log the ring takes over again.
        #expect(name(navigator.next(stations: ring, current: c, nowMs: 0)) == "A")
    }

    @Test("prev at the bottom of the log wraps the ring")
    func bottomWrap() {
        var navigator = RadioNavigator()
        navigator.recordPlay(a)
        navigator.recordPlay(b)
        #expect(name(navigator.previous(stations: ring, current: b, nowMs: 0)) == "A")
        #expect(name(navigator.previous(stations: ring, current: a, nowMs: 300)) == "C")
    }

    @Test("a fresh play after stepping back forks the redo tail")
    func forkDropsRedo() {
        var navigator = RadioNavigator()
        navigator.recordPlay(a)
        navigator.recordPlay(b)
        #expect(name(navigator.previous(stations: ring, current: b, nowMs: 0)) == "A")
        navigator.recordPlay(c)
        #expect(!navigator.canGoForward)
        #expect(name(navigator.next(stations: ring, current: c, nowMs: 200)) == "A")
    }

    @Test("the session log is capped at 100")
    func pastCap() {
        var navigator = RadioNavigator()
        for index in 0..<130 {
            navigator.recordPlay(
                Station(
                    id: "s\(index)", name: "S\(index)",
                    url: "https://s\(index).example/stream", source: .directory
                )
            )
        }
        var back = 0
        while navigator.canGoBack {
            _ = navigator.previous(stations: ring, current: nil, nowMs: Int64(back) * 1000)
            back += 1
        }
        #expect(back == RadioNavigator.pastCapacity - 1)
    }
}
