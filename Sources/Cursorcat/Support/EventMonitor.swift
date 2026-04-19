import AppKit

final class EventMonitor {
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent) -> NSEvent?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
    }

    func start() {
        stop()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [handler] event in
            _ = handler(event)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
