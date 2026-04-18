import Foundation

/// Drives the cat at an elevated cadence while Screenshot Mode is active
/// so a short screen recording captures a broad sampler of animations.
/// Runs independently of `CatBehavior` — the controller pauses the
/// normal phase machine when the director starts so only one source is
/// feeding `CatAnimator.play(_:)` at a time.
@MainActor
final class ScreenshotDirector {
    private let animator: CatAnimator

    /// Min / max delay between successive animation picks. The actual
    /// interval is re-randomised on every tick so the cat never looks
    /// like it's on a metronome.
    private let minInterval: TimeInterval = 1.5
    private let maxInterval: TimeInterval = 3.5

    /// Weighted animation pool. Each entry is picked with probability
    /// proportional to its weight. `sleepBrief` stays in the pool (per
    /// user ask) with a low weight so it still shows up in a recording
    /// without dominating it.
    private let pool: [(CatAnimation, Int)] = [
        (.scratchHead, 3),
        (.scratchUp,   2),
        (.scratchDown, 2),
        (.yawn,        2),
        (.alert,       2),
        (.runAround,   2),
        (.sleepBrief,  1)
    ]

    private var timer: Timer?
    private var lastPick: CatAnimation?

    init(animator: CatAnimator) {
        self.animator = animator
    }

    func start() {
        guard timer == nil else { return }
        Log.ui.info("ScreenshotDirector: start")
        scheduleNextTick(initial: true)
    }

    func stop() {
        Log.ui.info("ScreenshotDirector: stop")
        timer?.invalidate()
        timer = nil
        lastPick = nil
    }

    // MARK: - Scheduling

    private func scheduleNextTick(initial: Bool = false) {
        timer?.invalidate()
        let delay = initial
            ? 0.2
            : TimeInterval.random(in: minInterval...maxInterval)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fire() {
        let pick = pickAnimation()
        lastPick = pick
        animator.play(pick)
        scheduleNextTick()
    }

    /// Weighted random pick that skips the immediately-previous animation
    /// so the recording doesn't stutter with two yawns in a row.
    private func pickAnimation() -> CatAnimation {
        let filtered = pool.filter { $0.0 != lastPick }
        let source = filtered.isEmpty ? pool : filtered

        let totalWeight = source.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<totalWeight)
        for (animation, weight) in source {
            roll -= weight
            if roll < 0 { return animation }
        }
        return source.last!.0 // defensive — should never hit
    }
}
