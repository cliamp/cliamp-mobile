import Foundation

/// What one prev/next tap should cause. An isolated tap applies immediately;
/// a burst coalesces and settles on the final target after the debounce
/// window, the same leading-edge scheme Android uses.
public enum RadioNavDecision: Equatable, Sendable {
    case play(Station)
    case schedule
    case ignore
}

/// Session navigation for radio: the ring prev/next walks before an explicit
/// source list exists (recent history, or favourites when history is empty),
/// plus the log of what was actually heard. A port of the fallback half of
/// Android's `PlayerConnection` `recordPlay` / `prev` / `next` / `step`,
/// including the 180 ms burst debounce and the 100-entry cap.
public struct RadioNavigator: Sendable {
    /// A burst of taps within this window settles on the last one.
    public static let debounceWindowMs: Int64 = 180
    /// Session log cap; the persisted recents list owns real depth.
    public static let pastCapacity = 100

    private var past: [Station] = []
    private var pastIndex = -1
    private var pendingIndex: Int?
    private var lastTapMs: Int64?

    public init() {}

    public var canGoBack: Bool { pastIndex > 0 }
    public var canGoForward: Bool { pastIndex >= 0 && pastIndex < past.count - 1 }

    /// Records the audible item: consecutive duplicates no-op, a fresh play
    /// after stepping back drops the redo tail, and the log stays capped.
    public mutating func recordPlay(_ station: Station) {
        if past.indices.contains(pastIndex), past[pastIndex].url == station.url { return }
        while past.count - 1 > pastIndex { past.removeLast() }
        past.append(station)
        pastIndex = past.count - 1
        while past.count > Self.pastCapacity {
            past.removeFirst()
            pastIndex -= 1
        }
    }

    /// Next follows the redo tail first, then the fallback ring.
    public mutating func next(
        stations: [Station], current: Station?, nowMs: Int64
    ) -> RadioNavDecision {
        if canGoForward {
            pastIndex += 1
            cancelPending()
            return .play(past[pastIndex])
        }
        return step(+1, stations: stations, current: current, nowMs: nowMs)
    }

    /// Previous walks what was actually heard, falling back to the ring only
    /// at the bottom of the stack.
    public mutating func previous(
        stations: [Station], current: Station?, nowMs: Int64
    ) -> RadioNavDecision {
        if canGoBack {
            pastIndex -= 1
            cancelPending()
            return .play(past[pastIndex])
        }
        return step(-1, stations: stations, current: current, nowMs: nowMs)
    }

    /// The coalesced target once a burst's timer fires, or nil when nothing
    /// is pending.
    public mutating func takePending(stations: [Station]) -> Station? {
        guard let index = pendingIndex, !stations.isEmpty else {
            pendingIndex = nil
            return nil
        }
        pendingIndex = nil
        return stations[Self.wrap(index, count: stations.count)]
    }

    /// A fresh explicit play supersedes any coalescing burst still waiting.
    public mutating func cancelPending() {
        pendingIndex = nil
    }

    private mutating func step(
        _ delta: Int, stations: [Station], current: Station?, nowMs: Int64
    ) -> RadioNavDecision {
        guard !stations.isEmpty else { return .ignore }
        let here: Int
        let target: Int
        if let pendingIndex {
            here = pendingIndex
            target = Self.wrap(pendingIndex + delta, count: stations.count)
        } else if let current,
                  let index = stations.firstIndex(where: { $0.url == current.url }) {
            here = index
            target = Self.wrap(index + delta, count: stations.count)
        } else {
            // Nothing audible in the ring yet: walk from its first item.
            here = 0
            target = min(max(delta, 0), stations.count - 1)
        }
        if target == here, pendingIndex == nil { return .ignore }

        let leadingEdge = lastTapMs.map { nowMs - $0 > Self.debounceWindowMs } ?? true
        lastTapMs = nowMs
        if leadingEdge {
            pendingIndex = nil
            return .play(stations[target])
        }
        pendingIndex = target
        return .schedule
    }

    private static func wrap(_ index: Int, count: Int) -> Int {
        ((index % count) + count) % count
    }
}
