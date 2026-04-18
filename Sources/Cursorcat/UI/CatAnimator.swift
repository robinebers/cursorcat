import AppKit
import Foundation

/// One-shot animations the animator knows how to play. Each runs for a
/// fixed duration and the animator then returns to the default breathing
/// idle loop.
enum CatAnimation {
    /// Legacy alias used by the Interact menu — routed to `scratchHead`.
    case scratching
    /// Paws reaching up.
    case scratchUp
    /// Paws on the floor.
    case scratchDown
    /// Self-grooming head scratch (3-frame loop).
    case scratchHead
    /// Hard-lock long sleep (used by `setState(.sleeping)` for logged-out).
    case sleeping
    /// Scheduled short nap: 60 s cap.
    case sleepBrief
    /// Composite three-yawn timeline built from the single `tired` frame.
    case yawn
    case alert
    case runAround
}

/// Drives the menu bar cat using the classic oneko.js idle loop:
/// - Mostly sits still in the `idle` pose.
/// - Every ~20 s of idleness (random), plays one of `scratchSelf` or the
///   full `sleeping` sequence, then returns to sitting.
/// - External `setState(_:)` can lock the cat to a pose (sleeping for
///   logged-out, tired for error).
/// - External `play(_:)` can trigger a one-shot animation from the menu.
/// Ticks run at 100 ms so durations match the reference implementation.
@MainActor
final class CatAnimator {
    private let tickInterval: TimeInterval = 0.1

    // Sleep tunables. Long, slow breathing — barely noticeable frame swap.
    // Each tick is 100 ms.
    private let sleepTiredTicks = 20          //  2 s of "dozing off" before sleep
    private let sleepFrameHoldTicks = 80      //  8 s per sleep frame (slow rise/fall)
    private let sleepTotalTicks = 36_000      //  ~1 h cap; used only by the hard
                                              //  state lock (logged-out)
    private let sleepBriefTotalTicks = 600    //  60 s cap for scheduled naps

    // Alert hold: keep the startled pose visible long enough to notice.
    private let alertHoldTicks = 60           //  6 s

    // Scratch cycles (each cycle swaps frames every `scratchWallFrameTicks`).
    private let scratchWallTotalTicks = 30    //  3 s
    private let scratchWallFrameTicks = 5     //  0.5 s per frame

    // Yawn composite: 3 tired beats with idle pauses between.
    private let yawnBeatTicks = 5             //  0.5 s holding tired
    private let yawnGapTicks = 20             //  2 s back to idle

    // Idle breathing: flip a 1-source-pixel vertical offset every N ticks.
    private let breathHoldTicks = 45          //  4.5 s per breath phase

    private var timer: Timer?
    private var state: CatState = .idle
    private var idleTime = 0
    private var animation: CatAnimation?
    private var animationFrame = 0
    private var breathTick = 0

    var onFrame: ((NSImage) -> Void)?

    func start() {
        emit()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Lock the cat to a pose tied to app state. Pass `.idle` to resume the
    /// auto loop.
    func setState(_ newState: CatState) {
        guard state != newState else { return }
        state = newState
        idleTime = 0
        animation = nil
        animationFrame = 0
        emit()
    }

    /// Trigger a one-shot animation. Interrupts any current idle animation,
    /// forces the state back to `.idle`, then plays the requested sequence.
    func play(_ kind: CatAnimation) {
        state = .idle
        animation = kind
        animationFrame = 0
        idleTime = 0
        advance()
    }

    // MARK: - Ticking

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        // Pose-locked states don't animate.
        guard state == .idle else { return }
        idleTime += 1
        advance()
    }

    /// Emit the current animation frame and advance (or end) the animation.
    private func advance() {
        switch animation {
        case .sleeping:
            // Hard state lock: up to ~1 h before self-cancelling. In practice
            // the next interaction / poll wakes the cat long before that.
            if animationFrame < sleepTiredTicks {
                emit(sprite: .tired, frame: 0)
            } else {
                let offset = animationFrame - sleepTiredTicks
                emit(sprite: .sleeping, frame: offset / sleepFrameHoldTicks)
            }
            if animationFrame > sleepTotalTicks { resetAnimation() }
            animationFrame += 1

        case .sleepBrief:
            // Short scheduled nap: 60 s cap.
            if animationFrame < sleepTiredTicks {
                emit(sprite: .tired, frame: 0)
            } else {
                let offset = animationFrame - sleepTiredTicks
                emit(sprite: .sleeping, frame: offset / sleepFrameHoldTicks)
            }
            if animationFrame > sleepBriefTotalTicks { resetAnimation() }
            animationFrame += 1

        case .scratching, .scratchHead:
            emit(sprite: .scratchSelf, frame: animationFrame)
            if animationFrame > 9 { resetAnimation() }
            animationFrame += 1

        case .scratchUp:
            emitScratchCycle(CatRenderer.Cell.scratchWallN)

        case .scratchDown:
            emitScratchCycle(CatRenderer.Cell.scratchWallS)

        case .yawn:
            // 0..5 tired, 5..25 idle, 25..30 tired, 30..50 idle, 50..55 tired.
            let beat = yawnBeatTicks
            let gap = yawnGapTicks
            let b1 = beat               //  5
            let g1 = b1 + gap           // 25
            let b2 = g1 + beat          // 30
            let g2 = b2 + gap           // 50
            let b3 = g2 + beat          // 55
            let f = animationFrame
            if f < b1 || (f >= g1 && f < b2) || (f >= g2 && f < b3) {
                emit(sprite: .tired, frame: 0)
            } else if f < b3 {
                emit(cell: CatRenderer.Cell.idle)
            } else {
                resetAnimation()
                return
            }
            animationFrame += 1

        case .alert:
            emit(sprite: .alert, frame: 0)
            if animationFrame > alertHoldTicks { resetAnimation() }
            animationFrame += 1

        case .runAround:
            // 16 directional frames × 2 ticks each = ~3.2 s lap.
            let frames = CatRenderer.Cell.runAround
            let index = (animationFrame / 2) % frames.count
            emit(cell: frames[index])
            if animationFrame > frames.count * 2 { resetAnimation() }
            animationFrame += 1

        case nil:
            emitIdleBreath()
        }
    }

    private func emitScratchCycle(_ frames: [(Int, Int)]) {
        let index = (animationFrame / scratchWallFrameTicks) % frames.count
        emit(cell: frames[index])
        if animationFrame > scratchWallTotalTicks { resetAnimation() }
        animationFrame += 1
    }

    private func emitIdleBreath() {
        // Alternate between the resting pose and a "shoulder lift" pose where
        // rows above the torso sit 1 px higher. Paws and sitting body stay
        // planted across both phases.
        breathTick += 1
        if breathTick >= breathHoldTicks * 2 { breathTick = 0 }
        let lifted = breathTick >= breathHoldTicks
        onFrame?(CatRenderer.image(for: CatRenderer.Cell.idle,
                                   breathLifted: lifted))
    }

    private func resetAnimation() {
        animation = nil
        animationFrame = 0
    }

    // MARK: - Sprite emission

    private enum Sprite {
        case idle, alert, tired, sleeping, scratchSelf, error
    }

    private func emit() {
        switch state {
        case .idle:
            if let animation {
                emitForRunningAnimation(animation, frame: animationFrame)
            } else {
                emitIdleBreath()
            }
        case .alert:      emit(sprite: .alert, frame: 0)
        case .tired:      emit(sprite: .tired, frame: 0)
        case .sleeping:   emit(sprite: .sleeping, frame: 0)
        case .scratching: emit(sprite: .scratchSelf, frame: 0)
        case .error:      emit(sprite: .error, frame: 0)
        }
    }

    private func emitForRunningAnimation(_ animation: CatAnimation, frame: Int) {
        switch animation {
        case .sleeping, .sleepBrief:
            if frame < sleepTiredTicks {
                emit(sprite: .tired, frame: 0)
            } else {
                let offset = frame - sleepTiredTicks
                emit(sprite: .sleeping, frame: offset / sleepFrameHoldTicks)
            }
        case .scratching, .scratchHead:
            emit(sprite: .scratchSelf, frame: frame)
        case .scratchUp:
            let frames = CatRenderer.Cell.scratchWallN
            emit(cell: frames[(frame / scratchWallFrameTicks) % frames.count])
        case .scratchDown:
            let frames = CatRenderer.Cell.scratchWallS
            emit(cell: frames[(frame / scratchWallFrameTicks) % frames.count])
        case .yawn:
            emit(sprite: .tired, frame: 0)
        case .alert:
            emit(sprite: .alert, frame: 0)
        case .runAround:
            let frames = CatRenderer.Cell.runAround
            emit(cell: frames[(frame / 2) % frames.count])
        }
    }

    private func emit(sprite: Sprite, frame: Int) {
        let cell: (Int, Int)
        switch sprite {
        case .idle:        cell = CatRenderer.Cell.idle
        case .alert:       cell = CatRenderer.Cell.alert
        case .tired:       cell = CatRenderer.Cell.tired
        case .sleeping:
            let frames = CatRenderer.Cell.sleeping
            cell = frames[frame % frames.count]
        case .scratchSelf:
            let frames = CatRenderer.Cell.scratchSelf
            cell = frames[frame % frames.count]
        case .error:
            // No dedicated error pose in the sheet — reuse `tired`.
            cell = CatRenderer.Cell.tired
        }
        emit(cell: cell)
    }

    private func emit(cell: (Int, Int)) {
        onFrame?(CatRenderer.image(for: cell))
    }
}
