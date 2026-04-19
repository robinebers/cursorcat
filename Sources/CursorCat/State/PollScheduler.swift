import Foundation
import AppKit

/// Drives one concurrent refresh at a time. Coalesces overlapping requests.
@MainActor
final class PollScheduler: ObservableObject {
    private let normalInterval: TimeInterval = 300  // 5 min
    private let backoffInterval: TimeInterval = 900 // 15 min
    private let authMonitorInterval: TimeInterval = 15
    private let wakeDebounce: TimeInterval = 3

    private let auth: CursorAuth
    private let api: CursorAPI
    private let store: UsageStore

    private var timer: DispatchSourceTimer?
    private var authMonitorTimer: DispatchSourceTimer?
    private var consecutiveFailures = 0
    private var wakeWorkItem: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private var hasStarted = false
    private var lastKnownHasLocalAuth: Bool?

    @Published private(set) var nextRefreshAt: Date?
    @Published private(set) var manualRefreshLockedUntil: Date?
    @Published private(set) var isRefreshing = false

    init(auth: CursorAuth, api: CursorAPI, store: UsageStore) {
        self.auth = auth
        self.api = api
        self.store = store
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        scheduleTimer(interval: normalInterval)
        startAuthMonitor()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWake()
            }
        }

        triggerNow() // first launch
    }

    func triggerNow(manual: Bool = false) {
        let now = Date()
        if manual {
            if store.viewState == .loggedOut {
                Task {
                    await auth.invalidate()
                    await self.runOnce()
                }
                return
            }
            guard canTriggerManualRefresh(at: now) else {
                return
            }
            manualRefreshLockedUntil = now.addingTimeInterval(normalInterval)
            scheduleTimer(deadline: manualRefreshLockedUntil ?? now)
        }
        Task { await self.runOnce() }
    }

    func canTriggerManualRefresh(at date: Date = Date()) -> Bool {
        guard !isRefreshing else { return false }
        guard let manualRefreshLockedUntil else { return true }
        return date >= manualRefreshLockedUntil
    }

    func stop() {
        timer?.cancel()
        timer = nil
        authMonitorTimer?.cancel()
        authMonitorTimer = nil
        wakeWorkItem?.cancel()
        wakeWorkItem = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        hasStarted = false
    }

    private func scheduleTimer(interval: TimeInterval) {
        scheduleTimer(deadline: Date().addingTimeInterval(interval), repeating: interval)
    }

    private func scheduleTimer(deadline: Date, repeating interval: TimeInterval = 300) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        let delay = max(0, deadline.timeIntervalSinceNow)
        t.schedule(deadline: .now() + delay, repeating: interval, leeway: .seconds(10))
        t.setEventHandler { [weak self] in
            self?.triggerNow()
        }
        t.resume()
        timer = t
        nextRefreshAt = deadline
    }

    private func handleWake() {
        wakeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.triggerNow() }
        wakeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeDebounce, execute: item)
    }

    private func startAuthMonitor() {
        authMonitorTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + authMonitorInterval,
            repeating: authMonitorInterval,
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.reconcileLocalAuthState() }
        }
        timer.resume()
        authMonitorTimer = timer
    }

    private func reconcileLocalAuthState() async {
        let state = await auth.loadAuthState(forceReload: true)
        let hasLocalAuth = state.accessToken != nil || state.refreshToken != nil

        if !hasLocalAuth {
            lastKnownHasLocalAuth = false
            await auth.invalidate()
            if store.viewState != .loggedOut {
                store.setLoggedOut()
            }
            return
        }

        let authJustAppeared = lastKnownHasLocalAuth == false
        lastKnownHasLocalAuth = true

        if authJustAppeared && store.viewState == .loggedOut && !isRefreshing {
            await auth.invalidate()
            await runOnce()
        }
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
            if FileLog.rawDumpEnabled {
                let dump = await api.collectRawDump()
                FileLog.shared.write(dump, category: "raw")
            }
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
