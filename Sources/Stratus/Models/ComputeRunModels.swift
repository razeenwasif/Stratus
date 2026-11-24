import Foundation

struct ComputeInstance: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let zone: String
    let machineTypeShort: String
    let status: String
    let internalIP: String?
    let externalIP: String?
    let cpuPlatform: String?
    let creationTimestamp: String?
    let diskSizeGb: Int
    let estimatedMonthlyCost: Double
    let labels: [String: String]

    var isRunning: Bool {
        status.uppercased() == "RUNNING"
    }

    var vcpuCount: Int {
        // Infer vCPU from standard GCP machine type suffix (e.g. e2-standard-4 -> 4)
        let parts = machineTypeShort.split(separator: "-")
        if let last = parts.last, let n = Int(last) {
            return max(1, n)
        }
        if machineTypeShort.contains("micro") || machineTypeShort.contains("small") { return 1 }
        if machineTypeShort.contains("medium") { return 2 }
        return 2
    }

    var sshCommand: String {
        "gcloud compute ssh \(name) --zone=\(zone)"
    }
}

struct TrafficTarget: Identifiable, Sendable, Hashable {
    var id: String { "\(revisionName)-\(percent)-\(latestRevision)" }
    let revisionName: String
    let percent: Int
    let latestRevision: Bool
}

struct CloudRunService: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let fullName: String
    let region: String
    let uri: String
    let latestReadyRevision: String
    let ingress: String
    let lastModified: Date?
    let creator: String?
    let conditionsReady: Bool
    let traffic: [TrafficTarget]
    let cpu: String
    let memory: String
    let minInstances: Int
    let maxInstances: Int
    let requestCount24h: Int
    let estimatedMonthlyCost: Double
}

struct CloudRunRevision: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let createTime: Date?
    let containerImage: String
    let ready: Bool
}
