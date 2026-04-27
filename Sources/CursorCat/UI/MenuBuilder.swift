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
            menu.addItem(makeItem(title: "Open Cursor to log in", action: openCursorSelector))
            menu.addItem(.separator())
        }

        menu.addItem(makeItem(title: "Cloud agents", action: openCloudAgentsSelector))
        menu.addItem(makeItem(title: "Cursor status", action: openStatusSelector))

        menu.addItem(.separator())

        menu.addItem(makeInteractItem())

        menu.addItem(.separator())

        menu.addItem(makeItem(title: "Check for Updates…",
                              action: checkForUpdatesSelector,
                              isEnabled: canCheckForUpdates))
        menu.addItem(makeItem(title: "About", action: aboutSelector))
        menu.addItem(makeItem(title: "Quit", action: quitSelector, keyEquivalent: "q"))

        return menu
    }

    private func makeItem(title: String,
                          action: Selector,
                          keyEquivalent: String = "",
                          isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.isEnabled = isEnabled
        return item
    }

    private func makeInteractItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Interact", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Interact")
        for entry in InteractionMenuAction.allCases {
            let item = makeItem(title: entry.title, action: interactSelector)
            item.tag = entry.rawValue
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }
}
