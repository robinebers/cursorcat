import AppKit

/// Rebuilds the NSMenu from a UsageSnapshot. Rows where data is absent are omitted.
@MainActor
final class MenuBuilder {
    weak var target: AnyObject?
    let refreshSelector: Selector
    let openCursorSelector: Selector
    let quitSelector: Selector
    let interactSelector: Selector

    init(target: AnyObject,
         refreshSelector: Selector,
         openCursorSelector: Selector,
         quitSelector: Selector,
         interactSelector: Selector) {
        self.target = target
        self.refreshSelector = refreshSelector
        self.openCursorSelector = openCursorSelector
        self.quitSelector = quitSelector
        self.interactSelector = interactSelector
    }

    /// Interact submenu entries. Tag on each item identifies the animation.
    static let interactions: [(title: String, tag: Int)] = [
        ("Scratch", 0),
        ("Sleep", 1),
        ("Alert", 2),
        ("Run around", 3)
    ]

    static func animation(forTag tag: Int) -> CatAnimation? {
        switch tag {
        case 0: return .scratching
        case 1: return .sleeping
        case 2: return .alert
        case 3: return .runAround
        default: return nil
        }
    }

    func build(snapshot: UsageSnapshot) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if !snapshot.isLoggedIn {
            addLoggedOutItems(to: menu)
            return menu
        }

        if let amount = snapshot.yesterdaySpend {
            menu.addItem(disabled("Yesterday: \(Money.format(cents: amount))"))
        }
        if let amount = snapshot.last7DaysSpend {
            menu.addItem(disabled("Last 7 days: \(Money.format(cents: amount))"))
        }
        if let amount = snapshot.billingCycleSpend {
            var label = "This billing cycle: \(Money.format(cents: amount))"
            if let days = snapshot.billingCycleResetInDays {
                label += " · resets in \(days)d"
            }
            menu.addItem(disabled(label))
        }

        menu.addItem(.separator())

        if let plan = snapshot.plan {
            menu.addItem(disabled("Plan: \(plan)"))
        }
        if let used = snapshot.requestsUsed, let limit = snapshot.requestsLimit, limit > 0 {
            let left = max(0, limit - used)
            menu.addItem(disabled("Requests: \(left)/\(limit) left"))
        }
        if let pct = snapshot.autoPercentLeft {
            menu.addItem(disabled("Auto: \(Int(pct.rounded()))% left"))
        }
        if let pct = snapshot.apiPercentLeft {
            menu.addItem(disabled("API: \(Int(pct.rounded()))% left"))
        }
        if let limit = snapshot.onDemandLimit, limit > 0 {
            let remaining = snapshot.onDemandRemaining ?? 0
            menu.addItem(disabled("On-demand: \(Money.format(cents: remaining))/\(Money.format(cents: limit)) left"))
        }
        if let credits = snapshot.creditsLeft, credits > 0 {
            menu.addItem(disabled("Credits: \(Money.format(cents: credits)) left"))
        }

        if let error = snapshot.lastError {
            menu.addItem(.separator())
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(
                string: error,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize).italics(),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            menu.addItem(item)
        }

        menu.addItem(.separator())

        menu.addItem(makeInteractItem())

        let refresh = NSMenuItem(title: "Refresh now", action: refreshSelector, keyEquivalent: "r")
        refresh.target = target
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cursorcat", action: quitSelector, keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)

        return menu
    }

    private func addLoggedOutItems(to menu: NSMenu) {
        let open = NSMenuItem(title: "Open Cursor to log in", action: openCursorSelector, keyEquivalent: "")
        open.target = target
        menu.addItem(open)

        menu.addItem(.separator())

        menu.addItem(makeInteractItem())

        let refresh = NSMenuItem(title: "Refresh now", action: refreshSelector, keyEquivalent: "r")
        refresh.target = target
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cursorcat", action: quitSelector, keyEquivalent: "q")
        quit.target = target
        menu.addItem(quit)
    }

    private func makeInteractItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Interact", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Interact")
        for entry in Self.interactions {
            let item = NSMenuItem(title: entry.title, action: interactSelector, keyEquivalent: "")
            item.target = target
            item.tag = entry.tag
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

enum Money {
    static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func format(cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(dollars)"
    }
}

private extension NSFont {
    func italics() -> NSFont {
        let desc = self.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: self.pointSize) ?? self
    }
}
