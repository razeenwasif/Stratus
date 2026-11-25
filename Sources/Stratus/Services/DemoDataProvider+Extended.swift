import Foundation

extension DemoDataProvider {
    static func gkeClusters(for projectId: String) -> [GKECluster] {
        [
            GKECluster(
                name: "prod-gke-autopilot",
                location: "us-central1",
                status: "RUNNING",
                masterVersion: "1.30.5-gke.1443001",
                nodeCount: 6,
                endpoint: "34.122.91.18",
                network: "prod-vpc-core",
                nodePools: [
                    GKENodePool(name: "default-pool", machineType: "e2-standard-4", nodeCount: 4, status: "RUNNING"),
                    GKENodePool(name: "highmem-pool", machineType: "n2-highmem-4", nodeCount: 2, status: "RUNNING")
                ]
            ),
            GKECluster(
                name: "staging-spot-cluster",
                location: "us-central1-a",
                status: "RUNNING",
                masterVersion: "1.30.4-gke.1210000",
                nodeCount: 2,
                endpoint: "35.224.19.84",
                network: "prod-vpc-core",
                nodePools: [
                    GKENodePool(name: "spot-workers", machineType: "e2-medium", nodeCount: 2, status: "RUNNING")
                ]
            )
        ]
    }

    static func cloudFunctions(for projectId: String) -> [CloudFunctionItem] {
        let now = Date()
        return [
            CloudFunctionItem(id: "fn-1", name: "stripe-webhook-verifier", region: "us-central1", state: "ACTIVE", runtime: "nodejs20", uri: "https://us-central1-\(projectId).cloudfunctions.net/stripe-webhook-verifier", memory: "256M", triggerType: "HTTPS", updated: now.addingTimeInterval(-3600 * 12)),
            CloudFunctionItem(id: "fn-2", name: "gcs-thumbnail-resize", region: "us-central1", state: "ACTIVE", runtime: "python312", uri: "https://us-central1-\(projectId).cloudfunctions.net/gcs-thumbnail-resize", memory: "512M", triggerType: "storage.object.v1.finalized", updated: now.addingTimeInterval(-86400 * 3)),
            CloudFunctionItem(id: "fn-3", name: "pubsub-slack-alerts", region: "us-east1", state: "ACTIVE", runtime: "go122", uri: "https://us-east1-\(projectId).cloudfunctions.net/pubsub-slack-alerts", memory: "128M", triggerType: "pubsub.topic.v1.messagePublished", updated: now.addingTimeInterval(-86400 * 9))
        ]
    }

    static func vpcNetworks() -> [VPCNetwork] {
        [
            VPCNetwork(name: "prod-vpc-core", autoCreateSubnetworks: false, routingMode: "GLOBAL", subnetworkCount: 4),
            VPCNetwork(name: "default", autoCreateSubnetworks: true, routingMode: "REGIONAL", subnetworkCount: 12)
        ]
    }

    static func firewallRules() -> [FirewallRule] {
        [
            FirewallRule(name: "allow-https-lb-ingress", network: "prod-vpc-core", direction: "INGRESS", priority: 1000, disabled: false, action: "ALLOW", protocolsAndPorts: "tcp:443,80", sourceRanges: ["130.211.0.0/22", "35.191.0.0/16"], targetTags: ["edge-gateway"]),
            FirewallRule(name: "allow-iap-ssh", network: "prod-vpc-core", direction: "INGRESS", priority: 1000, disabled: false, action: "ALLOW", protocolsAndPorts: "tcp:22", sourceRanges: ["35.235.240.0/20"], targetTags: ["iap-ssh"]),
            FirewallRule(name: "allow-internal-mesh", network: "prod-vpc-core", direction: "INGRESS", priority: 1100, disabled: false, action: "ALLOW", protocolsAndPorts: "tcp:0-65535 udp:0-65535 icmp", sourceRanges: ["10.128.0.0/16"], targetTags: []),
            FirewallRule(name: "deny-public-postgres", network: "prod-vpc-core", direction: "INGRESS", priority: 900, disabled: false, action: "DENY", protocolsAndPorts: "tcp:5432", sourceRanges: ["0.0.0.0/0"], targetTags: ["postgres"])
        ]
    }

    static func artifactRepos(for projectId: String) -> [ArtifactRepo] {
        [
            ArtifactRepo(name: "services", fullName: "projects/\(projectId)/locations/us-central1/repositories/services", location: "us-central1", format: "DOCKER", sizeBytes: 18_420_190_200, description: "Production Cloud Run & GKE container images"),
            ArtifactRepo(name: "python-wheels", fullName: "projects/\(projectId)/locations/us/repositories/python-wheels", location: "us", format: "PYTHON", sizeBytes: 1_240_000_000, description: "Internal ML & ETL packages")
        ]
    }

    static func artifactImages(for repo: ArtifactRepo) -> [ArtifactImage] {
        let now = Date()
        return [
            ArtifactImage(name: "checkout-api", uri: "\(repo.location)-docker.pkg.dev/prod-platform-core/\(repo.name)/checkout-api:v2.14.0", tags: ["v2.14.0", "latest"], sizeBytes: 184_200_000, uploadTime: now.addingTimeInterval(-3600 * 4)),
            ArtifactImage(name: "auth-token-broker", uri: "\(repo.location)-docker.pkg.dev/prod-platform-core/\(repo.name)/auth-token-broker:v1.9.2", tags: ["v1.9.2"], sizeBytes: 94_110_000, uploadTime: now.addingTimeInterval(-86400 * 2)),
            ArtifactImage(name: "webhook-ingestor", uri: "\(repo.location)-docker.pkg.dev/prod-platform-core/\(repo.name)/webhook-ingestor:v3.1.0", tags: ["v3.1.0", "prod"], sizeBytes: 112_800_000, uploadTime: now.addingTimeInterval(-86400 * 6))
        ]
    }

    static func cloudBuilds() -> [CloudBuildItem] {
        let now = Date()
        return [
            CloudBuildItem(id: "b94a10f2-4c11", status: "SUCCESS", createTime: now.addingTimeInterval(-1800), durationSeconds: 94, sourceSummary: "platform-api@main", logUrl: nil),
            CloudBuildItem(id: "e12f99a4-8d02", status: "SUCCESS", createTime: now.addingTimeInterval(-3600 * 5), durationSeconds: 142, sourceSummary: "checkout-web@main", logUrl: nil),
            CloudBuildItem(id: "a77c31b8-19f0", status: "FAILURE", createTime: now.addingTimeInterval(-86400), durationSeconds: 38, sourceSummary: "worker-pdf@feat/chromium", logUrl: nil)
        ]
    }

    static func schedulerJobs(for projectId: String) -> [SchedulerJob] {
        let now = Date()
        return [
            SchedulerJob(name: "nightly-billing-rollup", fullName: "projects/\(projectId)/locations/us-central1/jobs/nightly-billing-rollup", location: "us-central1", schedule: "0 2 * * *", timeZone: "UTC", state: "ENABLED", targetSummary: "BigQuery / Cloud Run", lastAttemptTime: now.addingTimeInterval(-3600 * 8)),
            SchedulerJob(name: "hourly-cache-warmer", fullName: "projects/\(projectId)/locations/us-central1/jobs/hourly-cache-warmer", location: "us-central1", schedule: "0 * * * *", timeZone: "UTC", state: "ENABLED", targetSummary: "https://checkout-api.../warm", lastAttemptTime: now.addingTimeInterval(-1200)),
            SchedulerJob(name: "weekly-stale-snapshot-prune", fullName: "projects/\(projectId)/locations/us-central1/jobs/weekly-stale-snapshot-prune", location: "us-central1", schedule: "0 4 * * 0", timeZone: "UTC", state: "PAUSED", targetSummary: "pubsub/ops-maintenance", lastAttemptTime: now.addingTimeInterval(-86400 * 5))
        ]
    }

    static func pubSubTopics(for projectId: String) -> [PubSubTopic] {
        [
            PubSubTopic(name: "orders-events", fullName: "projects/\(projectId)/topics/orders-events"),
            PubSubTopic(name: "billing-alerts", fullName: "projects/\(projectId)/topics/billing-alerts"),
            PubSubTopic(name: "dead-letter-dlq", fullName: "projects/\(projectId)/topics/dead-letter-dlq")
        ]
    }

    static func pubSubSubscriptions(for projectId: String) -> [PubSubSubscription] {
        [
            PubSubSubscription(name: "orders-events-bigquery-sink", fullName: "projects/\(projectId)/subscriptions/orders-events-bigquery-sink", topicName: "orders-events", ackDeadlineSeconds: 30, pushEndpoint: nil),
            PubSubSubscription(name: "billing-alerts-webhook", fullName: "projects/\(projectId)/subscriptions/billing-alerts-webhook", topicName: "billing-alerts", ackDeadlineSeconds: 20, pushEndpoint: "https://webhook-ingestor-9c41d-ue.a.run.app/pubsub")
        ]
    }

    static func firestoreDatabases() -> [FirestoreDatabase] {
        [
            FirestoreDatabase(name: "(default)", location: "nam5", type: "FIRESTORE_NATIVE", concurrencyMode: "OPTIMISTIC", collections: ["users", "sessions", "feature_flags", "audit_events"])
        ]
    }

    static func spannerInstances(for projectId: String) -> [SpannerInstance] {
        [
            SpannerInstance(name: "ledger-global", fullName: "projects/\(projectId)/instances/ledger-global", config: "nam-eur-asia1", nodeCount: 1, processingUnits: 1000, state: "READY", databases: ["transactions_db", "idempotency_keys"])
        ]
    }

    static func redisInstances(for projectId: String) -> [RedisInstance] {
        [
            RedisInstance(name: "session-store-ha", fullName: "projects/\(projectId)/locations/us-central1/instances/session-store-ha", location: "us-central1", tier: "STANDARD_HA", memorySizeGb: 8, host: "10.82.12.4", port: 6379, redisVersion: "REDIS_7_2", state: "READY")
        ]
    }

    static func monitoringSeries(metric: MonitoringMetricKind, hours: Int) -> [MonitoringPoint] {
        let now = Date()
        let steps = 36
        let stepInterval = TimeInterval(hours * 3600) / Double(steps)
        let seriesNames: [String]
        switch metric {
        case .computeCPU: seriesNames = ["api-gateway-edge-01", "redis-sentinel-primary"]
        case .cloudRunRequests: seriesNames = ["checkout-api", "auth-token-broker"]
        case .sqlCPU, .sqlMemory: seriesNames = ["orders-pg-primary", "sessions-replica-01"]
        }

        var points: [MonitoringPoint] = []
        for (sIdx, name) in seriesNames.enumerated() {
            for i in 0...steps {
                let ts = now.addingTimeInterval(-Double(steps - i) * stepInterval)
                let base: Double
                let amp: Double
                switch metric {
                case .computeCPU:
                    base = sIdx == 0 ? 34.0 : 18.0
                    amp = 19.0
                case .cloudRunRequests:
                    base = sIdx == 0 ? 420.0 : 210.0
                    amp = 185.0
                case .sqlCPU:
                    base = sIdx == 0 ? 28.0 : 11.0
                    amp = 14.0
                case .sqlMemory:
                    base = sIdx == 0 ? 64.0 : 48.0
                    amp = 7.0
                }
                let wave = sin(Double(i + sIdx * 4) * 0.42) * amp + cos(Double(i) * 0.85) * (amp * 0.35)
                points.append(MonitoringPoint(timestamp: ts, seriesName: name, value: max(1, base + wave)))
            }
        }
        return points
    }
}
