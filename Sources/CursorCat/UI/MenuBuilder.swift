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
    let refreshSelector: Selector
    let openCursorSelector: Selector
    let openCloudAgentsSelector: Selector
    let openStatusSelector: Selector
    let quitSelector: Selector
    let interactSelector: Selector

    init(target: AnyObject,
         refreshSelector: Selector,
         openCursorSelector: Selector,
         openCloudAgentsSelector: Selector,
         openStatusSelector: Selector,
         quitSelector: Selector,
         interactSelector: Selector) {
        self.target = target
        self.refreshSelector = refreshSelector
        self.openCursorSelector = openCursorSelector
        self.openCloudAgentsSelector = openCloudAgentsSelector
        self.openStatusSelector = openStatusSelector
        self.quitSelector = quitSelector
        self.interactSelector = interactSelector
    }

    func build(isLoggedIn: Bool) -> NSMenu {
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

        menu.addItem(makeInteractItem())

        let refresh = NSMenuItem(title: "Refresh now",
                                 action: refreshSelector,
                                 keyEquivalent: "r")
        refresh.target = target
        menu.addItem(refresh)

        menu.addItem(.separator())

        let cloud = NSMenuItem(title: "Cloud Agents",
                               action: openCloudAgentsSelector,
                               keyEquivalent: "")
        cloud.target = target
        cloud.image = NSImage(systemSymbolName: "cloud",
                              accessibilityDescription: nil)
        menu.addItem(cloud)

        let status = NSMenuItem(title: "Cursor Status",
                                action: openStatusSelector,
                                keyEquivalent: "")
        status.target = target
        status.image = NSImage(systemSymbolName: "waveform.path.ecg",
                               accessibilityDescription: nil)
        menu.addItem(status)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit CursorCat",
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
