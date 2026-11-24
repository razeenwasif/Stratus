import Foundation

struct GCPProject: Identifiable, Sendable, Hashable {
    var id: String { projectId }
    let projectId: String
    let name: String
    let projectNumber: String
    let lifecycleState: String
    let createTime: String?
}

struct BillingInfo: Sendable, Hashable {
    let billingAccountName: String?
    let billingEnabled: Bool
}

struct DailyCostPoint: Identifiable, Sendable, Hashable {
    let id: String
    let date: Date
    let service: String
    let cost: Double

    init(date: Date, service: String, cost: Double) {
        self.id = "\(service)-\(Int(date.timeIntervalSince1970))"
        self.date = date
        self.service = service
        self.cost = cost
    }
}

struct ServiceSpend: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    let resourceCount: Int
    let countLabel: String
    let cost: Double
    let sharePercent: Double
    let usageLabel: String
    let targetSection: NavSection
}

struct CostCategoryItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let cost: Double
    let colorHex: String
}

struct OverviewTotalMetric: Identifiable, Sendable, Hashable {
    var id: String { label }
    let label: String
    let value: String
    let subtitle: String?
}

struct TopResourceItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let category: String
    let meta: String
    let metricText: String
    let cost: Double
    let targetSection: NavSection
}

struct CostOverview: Sendable, Hashable {
    let totalSpend: Double
    let periodSubtitle: String
    let serviceSpends: [ServiceSpend]
    let dailySeries: [DailyCostPoint]
    let totals: [OverviewTotalMetric]
    let costByType: [CostCategoryItem]
    let costByService: [CostCategoryItem]
    let topResources: [TopResourceItem]
    let isEstimate: Bool
    let serviceOrder: [String]
    let serviceColors: [String: String]
}
