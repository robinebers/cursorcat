import AppKit
import Combine
import Foundation

/// Observes `UsageStore` snapshots and drives the cat's behaviour in
/// 5-minute windows that match the poll cadence. Each snapshot resets the
/// window: comparing the previous `todaySpend` to the new one places the
/// cat in one of three phases:
///
/// - `plain`   — first poll or a day rollover (new < old). Pure breathing.
/// - `active`  — today's imputed spend increased. Cat cycles through
///               scratch / run animations roughly once a minute.
/// - `resting` — today's imputed spend unchanged. Cat cycles through
///               yawn / short nap roughly once a minute.
///
/// Pre-schedules N random event times per non-plain window and a 1 Hz
/// ticker pops them into `CatAnimator.play(_:)`.
@MainActor
final class CatBehavior {
    private let animator: CatAnimator
    private let store: UsageStore

    private let pollWindow: TimeInterval = 300
    private let eventsPerWindow = 5

    private enum Phase {
        case plain
        case active
        case resting
    }

    private var previousToday: Int?
    private var phase: Phase = .plain
    private var queue: [Date] = []
    private var ticker: Timer?
    private var cancellable: AnyCancellable?

    init(animator: CatAnimator, store: UsageStore) {
        self.animator = animator
        self.store = store
    }

    func start() {
        cancellable = store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snap in
                MainActor.assumeIsolated { self?.onSnapshot(snap) }
            }
        scheduleTicker()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        cancellable = nil
        queue.removeAll()
    }

    // MARK: - Phase selection

    private func onSnapshot(_ snapshot: UsageSnapshot) {
        guard snapshot.isLoggedIn else {
            queue.removeAll()
            previousToday = nil
            Log.ui.info("CatBehavior: logged out — scheduling paused")
            return
        }

        guard let today = snapshot.todaySpend else {
            return
        }

        let previous = previousToday
        defer { previousToday = today }

        let newPhase: Phase
        if let prev = previous {
            if today > prev {
                newPhase = .active
            } else if today == prev {
                newPhase = .resting
            } else {
                newPhase = .plain
            }
        } else {
            newPhase = .plain
        }

        phase = newPhase
        Log.ui.info("CatBehavior: phase=\(self.describe(newPhase)) prev=\(previous ?? -1) today=\(today)")
        FileLog.shared.write(
            "behavior phase=\(describe(newPhase)) prev=\(previous ?? -1) today=\(today)",
            category: "cat"
        )

        rescheduleEvents()
    }

    private func rescheduleEvents() {
        queue.removeAll()
        guard phase != .plain else { return }

        let now = Date()
        let offsets = (0..<eventsPerWindow).map { _ in
            TimeInterval.random(in: 0..<pollWindow)
        }
        queue = offsets.map { now.addingTimeInterval($0) }.sorted()
    }

    // MARK: - Ticking

    private func scheduleTicker() {
        ticker?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard !queue.isEmpty else { return }
        let now = Date()
        while let next = queue.first, next <= now {
            queue.removeFirst()
            let pick = pickForCurrentPhase()
            Log.ui.info("CatBehavior: firing \(self.describe(pick))")
            animator.play(pick)
        }
    }

    private func pickForCurrentPhase() -> CatAnimation {
        switch phase {
        case .active:
            return [CatAnimation.scratchUp, .scratchDown, .scratchHead, .runAround]
                .randomElement()!
        case .resting:
            return [CatAnimation.yawn, .sleepBrief].randomElement()!
        case .plain:
            // Shouldn't be reached — plain has no queued events — but fall
            // back to the gentlest animation just in case.
            return .yawn
        }
    }

    // MARK: - Logging helpers

    private func describe(_ phase: Phase) -> String {
        switch phase {
        case .plain:   return "plain"
        case .active:  return "active"
        case .resting: return "resting"
        }
    }

    private func describe(_ animation: CatAnimation) -> String {
        switch animation {
        case .scratching:  return "scratching"
        case .scratchUp:   return "scratchUp"
        case .scratchDown: return "scratchDown"
        case .scratchHead: return "scratchHead"
        case .sleeping:    return "sleeping"
        case .sleepBrief:  return "sleepBrief"
        case .yawn:        return "yawn"
        case .alert:       return "alert"
        case .runAround:   return "runAround"
        }
    }
}
