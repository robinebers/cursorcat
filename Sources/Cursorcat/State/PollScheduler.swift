import Foundation
import AppKit

/// Drives one concurrent refresh at a time. Coalesces overlapping requests.
@MainActor
final class PollScheduler {
    private let normalInterval: TimeInterval = 300  // 5 min
    private let backoffInterval: TimeInterval = 900 // 15 min
    private let wakeDebounce: TimeInterval = 3

    private let api: CursorAPI
    private let store: UsageStore

    private var timer: DispatchSourceTimer?
    private var isRefreshing = false
    private var consecutiveFailures = 0
    private var wakeWorkItem: DispatchWorkItem?

    init(api: CursorAPI, store: UsageStore) {
        self.api = api
        self.store = store
    }

    func start() {
        scheduleTimer(interval: normalInterval)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }

        triggerNow() // first launch
    }

    func triggerNow() {
        Task { await self.runOnce() }
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(10))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.triggerNow() }
        }
        t.resume()
        timer = t
    }

    private func handleWake() {
        wakeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.triggerNow() }
        wakeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeDebounce, execute: item)
    }

    private func runOnce() async {
        if isRefreshing {
            Log.poll.info("poll skipped: already refreshing")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        Log.poll.info("poll start")
        do {
            let snapshot = try await api.fetchSnapshot()
            store.applySnapshot(snapshot)
            consecutiveFailures = 0
            scheduleTimer(interval: normalInterval)
            Log.poll.info("poll ok")
            let derived = store.snapshot
            FileLog.shared.write("poll ok: today=\(derived.todaySpend ?? -1) yesterday=\(derived.yesterdaySpend ?? -1) cycle=\(derived.billingCycleSpend ?? -1) plan=\(derived.plan ?? "?") csvRows=\(snapshot.csvRows.count)", category: "poll")
            let dump = await api.collectRawDump()
            FileLog.shared.write(dump, category: "raw")
        } catch let err as CursorAuthError where err.shouldLogOut {
            Log.poll.error("poll logged-out: \(err.description)")
            store.setLoggedOut()
        } catch let err as HTTPError where err.isAuth {
            Log.poll.error("poll auth error: \(err.description)")
            store.setLoggedOut()
        } catch {
            consecutiveFailures += 1
            let msg = "Last update failed \(hhmm(Date()))"
            store.setError(msg)
            Log.poll.error("poll failed (\(self.consecutiveFailures)x): \(error.localizedDescription)")
            FileLog.shared.write("poll failed: \(error.localizedDescription)", category: "poll")
            if consecutiveFailures >= 3 {
                scheduleTimer(interval: backoffInterval)
            }
        }
    }

    private func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
