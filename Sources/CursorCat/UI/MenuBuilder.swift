import AppKit

enum InteractionMenuAction: Int, CaseIterable {
    case scratchHead
    case scratchUp
    case scratchDown
    case sleep
    case alert
    case runAround

    var title: String {
        switch self {
        case .scratchHead: return "Scratch head"
        case .scratchUp: return "Scratch up"
        case .scratchDown: return "Scratch down"
        case .sleep: return "Sleep"
        case .alert: return "Alert"
        case .runAround: return "Run around"
        }
    }

    var animation: CatAnimation {
        switch self {
        case .scratchHead: return .scratchHead
        case .scratchUp: return .scratchUp
        case .scratchDown: return .scratchDown
        case .sleep: return .sleeping
        case .alert: return .alert
        case .runAround: return .runAround
        }
    }
}

@MainActor
final class ActionsMenuBuilder {
    weak var target: AnyObject?
    let checkForUpdatesSelector: Selector
    let aboutSelector: Selector
    let openCursorSelector: Selector
    let openCloudAgentsSelector: Selector
    let openStatusSelector: Selector
    let quitSelector: Selector
    let interactSelector: Selector

    init(target: AnyObject,
         checkForUpdatesSelector: Selector,
         aboutSelector: Selector,
         openCursorSelector: Selector,
         openCloudAgentsSelector: Selector,
         openStatusSelector: Selector,
         quitSelector: Selector,
         interactSelector: Selector) {
        self.target = target
        self.checkForUpdatesSelector = checkForUpdatesSelector
        self.aboutSelector = aboutSelector
        self.openCursorSelector = openCursorSelector
        self.openCloudAgentsSelector = openCloudAgentsSelector
        self.openStatusSelector = openStatusSelector
        self.quitSelector = quitSelector
        self.interactSelector = interactSelector
    }

    func build(isLoggedIn: Bool, canCheckForUpdates: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !isLoggedIn {
            let open = NSMenuItem(title: "Open Cursor to log in",
                                  action: openCursorSelector,
                                  keyEquivalent: "")
            open.target = target
            menu.addItem(open)
            menu.addItem(.separator())
        }

        let cloud = NSMenuItem(title: "Cloud agents",
                               action: openCloudAgentsSelector,
                               keyEquivalent: "")
        cloud.target = target
        menu.addItem(cloud)

        let status = NSMenuItem(title: "Cursor status",
                                action: openStatusSelector,
                                keyEquivalent: "")
        status.target = target
        menu.addItem(status)

        menu.addItem(.separator())

        menu.addItem(makeInteractItem())

        menu.addItem(.separator())

        let checkForUpdates = NSMenuItem(title: "Check for Updates…",
                                         action: checkForUpdatesSelector,
                                         keyEquivalent: "")
        checkForUpdates.target = target
        checkForUpdates.isEnabled = canCheckForUpdates
        menu.addItem(checkForUpdates)

        let about = NSMenuItem(title: "About",
                               action: aboutSelector,
                               keyEquivalent: "")
        about.target = target
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit",
                              action: quitSelector,
                              keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)

        return menu
    }

    private func makeInteractItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Interact", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Interact")
        for entry in InteractionMenuAction.allCases {
            let item = NSMenuItem(title: entry.title,
                                  action: interactSelector,
                                  keyEquivalent: "")
            item.target = target
            item.tag = entry.rawValue
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }
}
