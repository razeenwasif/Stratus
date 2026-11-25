import Foundation

// MARK: - GKE (Kubernetes Engine)

struct GKENodePool: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let machineType: String
    let nodeCount: Int
    let status: String
}

struct GKECluster: Identifiable, Sendable, Hashable {
    var id: String { "\(location)-\(name)" }
    let name: String
    let location: String
    let status: String
    let masterVersion: String
    let nodeCount: Int
    let endpoint: String
    let network: String
    let nodePools: [GKENodePool]

    var isRunning: Bool {
        status.uppercased() == "RUNNING"
    }

    func getCredentialsCommand(projectId: String) -> String {
        "gcloud container clusters get-credentials \(name) --location=\(location) --project=\(projectId)"
    }
}

// MARK: - Cloud Functions v2

struct CloudFunctionItem: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let region: String
    let state: String
    let runtime: String
    let uri: String
    let memory: String
    let triggerType: String
    let updated: Date?

    var isActive: Bool {
        state.uppercased() == "ACTIVE"
    }
}

// MARK: - VPC Networks & Firewall Rules

struct VPCNetwork: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let autoCreateSubnetworks: Bool
    let routingMode: String
    let subnetworkCount: Int
}

struct FirewallRule: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let network: String
    let direction: String
    let priority: Int
    let disabled: Bool
    let action: String
    let protocolsAndPorts: String
    let sourceRanges: [String]
    let targetTags: [String]
}

// MARK: - Artifact Registry

struct ArtifactRepo: Identifiable, Sendable, Hashable {
    var id: String { fullName }
    let name: String
    let fullName: String
    let location: String
    let format: String
    let sizeBytes: Int64
    let description: String
}

struct ArtifactImage: Identifiable, Sendable, Hashable {
    var id: String { uri }
    let name: String
    let uri: String
    let tags: [String]
    let sizeBytes: Int64
    let uploadTime: Date?
}

// MARK: - Cloud Build & Cloud Scheduler

struct CloudBuildItem: Identifiable, Sendable, Hashable {
    let id: String
    let status: String
    let createTime: Date?
    let durationSeconds: Int?
    let sourceSummary: String
    let logUrl: String?

    var isSuccess: Bool {
        status.uppercased() == "SUCCESS"
    }

    var isFailure: Bool {
        let up = status.uppercased()
        return up == "FAILURE" || up == "TIMEOUT" || up == "INTERNAL_ERROR"
    }
}

struct SchedulerJob: Identifiable, Sendable, Hashable {
    var id: String { fullName }
    let name: String
    let fullName: String
    let location: String
    let schedule: String
    let timeZone: String
    let state: String
    let targetSummary: String
    let lastAttemptTime: Date?

    var isEnabled: Bool {
        state.uppercased() == "ENABLED"
    }
}

// MARK: - Pub/Sub

struct PubSubTopic: Identifiable, Sendable, Hashable {
    var id: String { fullName }
    let name: String
    let fullName: String
}

struct PubSubSubscription: Identifiable, Sendable, Hashable {
    var id: String { fullName }
    let name: String
    let fullName: String
    let topicName: String
    let ackDeadlineSeconds: Int
    let pushEndpoint: String?
}

// MARK: - Managed Databases (Firestore, Spanner, Memorystore Redis)

struct FirestoreDatabase: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let location: String
    let type: String
    let concurrencyMode: String
    let collections: [String]
}

struct SpannerInstance: Identifiable, Sendable, Hashable {
    var id: String { fullName }
    let name: String
    let fullName: String
    let config: String
    let nodeCount: Int
    let processingUnits: Int
    let state: String
    let databases: [String]

    var isReady: Bool {
        state.uppercased() == "READY"
    }
}

struct RedisInstance: Identifiable, Sendable, Hashable {
    var id: String { fullName }
    let name: String
    let fullName: String
    let location: String
    let tier: String
    let memorySizeGb: Int
    let host: String
    let port: Int
    let redisVersion: String
    let state: String

    var isReady: Bool {
        state.uppercased() == "READY"
    }
}

// MARK: - Cloud Monitoring

enum MonitoringMetricKind: String, Sendable, CaseIterable, Identifiable, Hashable {
    case computeCPU
    case cloudRunRequests
    case sqlCPU
    case sqlMemory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .computeCPU: return "Compute CPU"
        case .cloudRunRequests: return "Cloud Run Requests"
        case .sqlCPU: return "Cloud SQL CPU"
        case .sqlMemory: return "Cloud SQL Memory"
        }
    }

    var metricType: String {
        switch self {
        case .computeCPU: return "compute.googleapis.com/instance/cpu/utilization"
        case .cloudRunRequests: return "run.googleapis.com/request_count"
        case .sqlCPU: return "cloudsql.googleapis.com/database/cpu/utilization"
        case .sqlMemory: return "cloudsql.googleapis.com/database/memory/utilization"
        }
    }

    var unitSuffix: String {
        switch self {
        case .computeCPU, .sqlCPU, .sqlMemory: return "%"
        case .cloudRunRequests: return "req/m"
        }
    }

    var isPercentage: Bool {
        switch self {
        case .computeCPU, .sqlCPU, .sqlMemory: return true
        case .cloudRunRequests: return false
        }
    }

    var colorHex: String {
        switch self {
        case .computeCPU: return "#E88255"
        case .cloudRunRequests: return "#7A89FF"
        case .sqlCPU: return "#4BC3F7"
        case .sqlMemory: return "#34D399"
        }
    }
}

struct MonitoringPoint: Identifiable, Sendable, Hashable {
    let id: String
    let timestamp: Date
    let seriesName: String
    let value: Double

    init(timestamp: Date, seriesName: String, value: Double) {
        self.id = "\(seriesName)-\(Int(timestamp.timeIntervalSince1970))"
        self.timestamp = timestamp
        self.seriesName = seriesName
        self.value = value
    }
}
