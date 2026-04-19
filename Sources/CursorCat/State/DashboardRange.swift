import Foundation

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case models
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .models: return "Models"
        case .settings: return "Settings"
        }
    }
}

enum DashboardRange: String, CaseIterable, Hashable, Identifiable {
    case today
    case yesterday
    case billingCycle
    case last30Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .billingCycle: return "Billing Cycle"
        case .last30Days: return "Last 30 Days"
        }
    }

    var comparisonLabel: String {
        switch self {
        case .today: return "vs. yesterday"
        case .yesterday: return "vs. today"
        case .billingCycle: return "vs. prev billing cycle"
        case .last30Days: return "vs. prev. 30 days"
        }
    }
}

struct DashboardRangeSummary: Equatable {
    let totalCents: Int
    let comparisonCents: Int
    let comparisonLabel: String
}
