import Foundation

enum DemoDataProvider {
    static let projects: [GCPProject] = [
        GCPProject(
            projectId: "prod-platform-core",
            name: "Production Platform",
            projectNumber: "89412055412",
            lifecycleState: "ACTIVE",
            createTime: "2024-03-14T08:12:00Z"
        ),
        GCPProject(
            projectId: "ml-inference-west",
            name: "ML Inference West",
            projectNumber: "55102938471",
            lifecycleState: "ACTIVE",
            createTime: "2025-01-22T14:45:00Z"
        ),
        GCPProject(
            projectId: "analytics-warehouse",
            name: "Analytics Warehouse",
            projectNumber: "31904482190",
            lifecycleState: "ACTIVE",
            createTime: "2024-09-05T19:00:00Z"
        )
    ]

    static func billingInfo(for projectId: String) -> BillingInfo {
        BillingInfo(billingAccountName: "billingAccounts/01A9F2-883B1C-E40219", billingEnabled: true)
    }

    static func instances(for projectId: String) -> [ComputeInstance] {
        switch projectId {
        case "ml-inference-west":
            return [
                ComputeInstance(id: "101", name: "vllm-gpu-worker-01", zone: "us-west1-b", machineTypeShort: "g2-standard-8", status: "RUNNING", internalIP: "10.138.0.14", externalIP: "34.168.42.91", cpuPlatform: "Intel Cascade Lake", creationTimestamp: "2026-09-12T10:15:00Z", diskSizeGb: 200, estimatedMonthlyCost: 248.40, labels: ["env": "prod", "gpu": "l4"]),
                ComputeInstance(id: "102", name: "embedding-batch-02", zone: "us-west1-b", machineTypeShort: "e2-standard-4", status: "RUNNING", internalIP: "10.138.0.21", externalIP: nil, cpuPlatform: "AMD Rome", creationTimestamp: "2026-10-03T11:20:00Z", diskSizeGb: 80, estimatedMonthlyCost: 101.20, labels: ["env": "prod"]),
                ComputeInstance(id: "103", name: "eval-sandbox-vm", zone: "us-west1-a", machineTypeShort: "e2-medium", status: "TERMINATED", internalIP: "10.138.0.44", externalIP: nil, cpuPlatform: "Intel Broadwell", creationTimestamp: "2026-08-19T09:00:00Z", diskSizeGb: 50, estimatedMonthlyCost: 2.00, labels: ["env": "staging"])
            ]
        case "analytics-warehouse":
            return [
                ComputeInstance(id: "201", name: "airbyte-elt-runner", zone: "us-east1-b", machineTypeShort: "e2-standard-4", status: "RUNNING", internalIP: "10.142.0.9", externalIP: "35.229.118.4", cpuPlatform: "Intel Skylake", creationTimestamp: "2026-06-01T06:30:00Z", diskSizeGb: 100, estimatedMonthlyCost: 102.00, labels: ["team": "data"]),
                ComputeInstance(id: "202", name: "dbt-scheduler-vm", zone: "us-east1-b", machineTypeShort: "e2-small", status: "RUNNING", internalIP: "10.142.0.15", externalIP: nil, cpuPlatform: "Intel Skylake", creationTimestamp: "2026-07-11T12:10:00Z", diskSizeGb: 30, estimatedMonthlyCost: 14.50, labels: ["team": "data"])
            ]
        default:
            return [
                ComputeInstance(id: "1", name: "api-gateway-edge-01", zone: "us-central1-a", machineTypeShort: "c2-standard-4", status: "RUNNING", internalIP: "10.128.0.12", externalIP: "34.132.88.214", cpuPlatform: "Intel Cascade Lake", creationTimestamp: "2026-05-14T08:00:00Z", diskSizeGb: 64, estimatedMonthlyCost: 138.56, labels: ["tier": "edge", "env": "prod"]),
                ComputeInstance(id: "2", name: "redis-sentinel-primary", zone: "us-central1-b", machineTypeShort: "e2-highmem-2", status: "RUNNING", internalIP: "10.128.0.19", externalIP: nil, cpuPlatform: "AMD Rome", creationTimestamp: "2026-06-20T16:40:00Z", diskSizeGb: 50, estimatedMonthlyCost: 66.20, labels: ["tier": "cache", "env": "prod"]),
                ComputeInstance(id: "3", name: "bastion-iap-jumpbox", zone: "us-central1-c", machineTypeShort: "e2-micro", status: "RUNNING", internalIP: "10.128.0.3", externalIP: nil, cpuPlatform: "Intel Broadwell", creationTimestamp: "2026-02-01T09:10:00Z", diskSizeGb: 20, estimatedMonthlyCost: 7.11, labels: ["tier": "ops"]),
                ComputeInstance(id: "4", name: "loadtest-k6-runner", zone: "us-central1-a", machineTypeShort: "n2-standard-8", status: "TERMINATED", internalIP: "10.128.0.88", externalIP: nil, cpuPlatform: "Intel Cascade Lake", creationTimestamp: "2026-11-02T17:30:00Z", diskSizeGb: 100, estimatedMonthlyCost: 4.00, labels: ["tier": "qa"])
            ]
        }
    }

    static func cloudRunServices(for projectId: String) -> [CloudRunService] {
        let now = Date()
        return [
            CloudRunService(
                id: "run-1",
                name: "checkout-api",
                fullName: "projects/\(projectId)/locations/us-central1/services/checkout-api",
                region: "us-central1",
                uri: "https://checkout-api-7f9a2b-uc.a.run.app",
                latestReadyRevision: "checkout-api-00048-k9p",
                ingress: "ALL",
                lastModified: now.addingTimeInterval(-3600 * 4),
                creator: "ci-deployer@\(projectId).iam.gserviceaccount.com",
                conditionsReady: true,
                traffic: [
                    TrafficTarget(revisionName: "checkout-api-00048-k9p", percent: 90, latestRevision: true),
                    TrafficTarget(revisionName: "checkout-api-00047-m2x", percent: 10, latestRevision: false)
                ],
                cpu: "2000m",
                memory: "1Gi",
                minInstances: 1,
                maxInstances: 40,
                requestCount24h: 1_240_310,
                estimatedMonthlyCost: 64.80
            ),
            CloudRunService(
                id: "run-2",
                name: "auth-token-broker",
                fullName: "projects/\(projectId)/locations/us-central1/services/auth-token-broker",
                region: "us-central1",
                uri: "https://auth-token-broker-7f9a2b-uc.a.run.app",
                latestReadyRevision: "auth-token-broker-00019-q7l",
                ingress: "INTERNAL_AND_CLOUD_LOAD_BALANCING",
                lastModified: now.addingTimeInterval(-86400 * 2),
                creator: "platform@acme.dev",
                conditionsReady: true,
                traffic: [
                    TrafficTarget(revisionName: "auth-token-broker-00019-q7l", percent: 100, latestRevision: true)
                ],
                cpu: "1000m",
                memory: "512Mi",
                minInstances: 1,
                maxInstances: 20,
                requestCount24h: 842_900,
                estimatedMonthlyCost: 34.10
            ),
            CloudRunService(
                id: "run-3",
                name: "webhook-ingestor",
                fullName: "projects/\(projectId)/locations/us-east1/services/webhook-ingestor",
                region: "us-east1",
                uri: "https://webhook-ingestor-9c41d-ue.a.run.app",
                latestReadyRevision: "webhook-ingestor-00012-z1w",
                ingress: "ALL",
                lastModified: now.addingTimeInterval(-86400 * 6),
                creator: "ci-deployer@\(projectId).iam.gserviceaccount.com",
                conditionsReady: true,
                traffic: [
                    TrafficTarget(revisionName: "webhook-ingestor-00012-z1w", percent: 100, latestRevision: true)
                ],
                cpu: "1000m",
                memory: "512Mi",
                minInstances: 0,
                maxInstances: 15,
                requestCount24h: 193_400,
                estimatedMonthlyCost: 11.40
            ),
            CloudRunService(
                id: "run-4",
                name: "pdf-invoice-worker",
                fullName: "projects/\(projectId)/locations/europe-west1/services/pdf-invoice-worker",
                region: "europe-west1",
                uri: "https://pdf-invoice-worker-2a8e1-ew.a.run.app",
                latestReadyRevision: "pdf-invoice-worker-00005-r4n",
                ingress: "INTERNAL_ONLY",
                lastModified: now.addingTimeInterval(-86400 * 14),
                creator: "ci-deployer@\(projectId).iam.gserviceaccount.com",
                conditionsReady: false,
                traffic: [
                    TrafficTarget(revisionName: "pdf-invoice-worker-00005-r4n", percent: 100, latestRevision: true)
                ],
                cpu: "2000m",
                memory: "2Gi",
                minInstances: 0,
                maxInstances: 5,
                requestCount24h: 14_200,
                estimatedMonthlyCost: 6.20
            )
        ]
    }

    static func revisions(for service: CloudRunService) -> [CloudRunRevision] {
        let now = Date()
        return [
            CloudRunRevision(
                id: "\(service.name)-rev-1",
                name: service.latestReadyRevision,
                createTime: service.lastModified ?? now,
                containerImage: "us-docker.pkg.dev/prod-platform-core/services/\(service.name):v2.14.0",
                ready: service.conditionsReady
            ),
            CloudRunRevision(
                id: "\(service.name)-rev-2",
                name: "\(service.name)-00047-m2x",
                createTime: (service.lastModified ?? now).addingTimeInterval(-86400 * 5),
                containerImage: "us-docker.pkg.dev/prod-platform-core/services/\(service.name):v2.13.4",
                ready: true
            ),
            CloudRunRevision(
                id: "\(service.name)-rev-3",
                name: "\(service.name)-00046-a8c",
                createTime: (service.lastModified ?? now).addingTimeInterval(-86400 * 11),
                containerImage: "us-docker.pkg.dev/prod-platform-core/services/\(service.name):v2.13.1",
                ready: true
            )
        ]
    }

    static func buckets(for projectId: String) -> [GCSBucket] {
        [
            GCSBucket(name: "\(projectId)-artifacts", location: "US", storageClass: "STANDARD", timeCreated: Date().addingTimeInterval(-86400 * 180), versioningEnabled: true, estimatedSizeBytes: 412_316_860_416, objectCount: 1_842),
            GCSBucket(name: "\(projectId)-tfstate", location: "US-CENTRAL1", storageClass: "STANDARD", timeCreated: Date().addingTimeInterval(-86400 * 320), versioningEnabled: true, estimatedSizeBytes: 184_520_100, objectCount: 47),
            GCSBucket(name: "\(projectId)-bq-exports", location: "US", storageClass: "NEARLINE", timeCreated: Date().addingTimeInterval(-86400 * 95), versioningEnabled: false, estimatedSizeBytes: 1_284_110_320_000, objectCount: 9_120),
            GCSBucket(name: "\(projectId)-media-cdn", location: "MULTI_REGIONAL", storageClass: "STANDARD", timeCreated: Date().addingTimeInterval(-86400 * 240), versioningEnabled: false, estimatedSizeBytes: 84_210_910_000, objectCount: 24_610)
        ]
    }

    static func objects(bucket: String, prefix: String) -> [GCSObject] {
        let now = Date()
        if prefix.isEmpty {
            return [
                GCSObject(name: "releases/", bucket: bucket, sizeBytes: 0, contentType: "application/x-directory", updated: nil, isPrefix: true),
                GCSObject(name: "configs/", bucket: bucket, sizeBytes: 0, contentType: "application/x-directory", updated: nil, isPrefix: true),
                GCSObject(name: "manifest.json", bucket: bucket, sizeBytes: 1_428, contentType: "application/json", updated: now.addingTimeInterval(-1800), isPrefix: false),
                GCSObject(name: "deployment-audit.log", bucket: bucket, sizeBytes: 18_420, contentType: "text/plain", updated: now.addingTimeInterval(-7200), isPrefix: false),
                GCSObject(name: "bundle-linux-arm64.tar.gz", bucket: bucket, sizeBytes: 48_912_304, contentType: "application/gzip", updated: now.addingTimeInterval(-86400), isPrefix: false)
            ]
        } else if prefix == "releases/" {
            return [
                GCSObject(name: "releases/v2.14.0/", bucket: bucket, sizeBytes: 0, contentType: "application/x-directory", updated: nil, isPrefix: true),
                GCSObject(name: "releases/checksums.sha256", bucket: bucket, sizeBytes: 642, contentType: "text/plain", updated: now.addingTimeInterval(-3600), isPrefix: false)
            ]
        } else {
            return [
                GCSObject(name: "\(prefix)production.yaml", bucket: bucket, sizeBytes: 2_190, contentType: "text/yaml", updated: now.addingTimeInterval(-4200), isPrefix: false),
                GCSObject(name: "\(prefix)routes.json", bucket: bucket, sizeBytes: 3_810, contentType: "application/json", updated: now.addingTimeInterval(-14_000), isPrefix: false)
            ]
        }
    }

    static func objectPreviewText(for object: GCSObject) -> String {
        if object.name.hasSuffix(".json") {
            return """
            {
              "service": "checkout-api",
              "bucket": "\(object.bucket)",
              "object": "\(object.name)",
              "revision": "v2.14.0",
              "region": "us-central1",
              "canaryPercent": 10,
              "healthCheck": "/readyz"
            }
            """
        } else if object.name.hasSuffix(".yaml") {
            return """
            apiVersion: serving.knative.dev/v1
            kind: Service
            metadata:
              name: checkout-api
            spec:
              traffic:
                - latestRevision: true
                  percent: 90
                - revisionName: checkout-api-00047-m2x
                  percent: 10
            """
        }
        return """
        [2026-11-25T09:58:12Z] INFO  verified artifact checksums for v2.14.0
        [2026-11-25T09:58:14Z] INFO  promoted revision checkout-api-00048-k9p (90% traffic)
        [2026-11-25T09:58:19Z] INFO  p99 latency 18.4ms · 0 errors
        """
    }

    static func sqlInstances(for projectId: String) -> [CloudSQLInstance] {
        [
            CloudSQLInstance(name: "orders-pg-primary", databaseVersion: "POSTGRES_16", region: "us-central1", state: "RUNNABLE", tier: "db-custom-4-16384", ipAddress: "10.82.4.12", storageSizeGb: 250, availabilityType: "REGIONAL", estimatedMonthlyCost: 142.80),
            CloudSQLInstance(name: "sessions-replica-01", databaseVersion: "POSTGRES_16", region: "us-central1", state: "RUNNABLE", tier: "db-custom-2-8192", ipAddress: "10.82.4.19", storageSizeGb: 100, availabilityType: "ZONAL", estimatedMonthlyCost: 58.40)
        ]
    }

    static func datasets(for projectId: String) -> [BQDataset] {
        [
            BQDataset(datasetId: "billing_export", location: "US", friendlyName: "Cloud Billing Export", creationTime: nil),
            BQDataset(datasetId: "product_events", location: "US", friendlyName: "Telemetry & Product Events", creationTime: nil),
            BQDataset(datasetId: "finance_marts", location: "US", friendlyName: "Revenue Marts", creationTime: nil)
        ]
    }

    static func tables(for datasetId: String) -> [BQTable] {
        switch datasetId {
        case "billing_export":
            return [
                BQTable(tableId: "gcp_billing_export_v1", datasetId: datasetId, type: "TABLE", numRows: 482_910, numBytes: 184_200_000, lastModified: Date()),
                BQTable(tableId: "daily_service_rollup", datasetId: datasetId, type: "VIEW", numRows: 12_400, numBytes: 0, lastModified: Date())
            ]
        case "product_events":
            return [
                BQTable(tableId: "api_requests_hourly", datasetId: datasetId, type: "TABLE", numRows: 18_420_000, numBytes: 4_820_190_000, lastModified: Date()),
                BQTable(tableId: "checkout_conversions", datasetId: datasetId, type: "TABLE", numRows: 912_300, numBytes: 312_000_000, lastModified: Date())
            ]
        default:
            return [
                BQTable(tableId: "monthly_arr_summary", datasetId: datasetId, type: "TABLE", numRows: 4_820, numBytes: 2_400_000, lastModified: Date())
            ]
        }
    }

    static func runDemoSQL(_ sql: String) -> BQQueryResult {
        BQQueryResult(
            columns: ["service_name", "region", "requests_24h", "p99_ms", "cost_usd"],
            rows: [
                ["Compute Engine", "us-central1", "—", "—", "184.50"],
                ["Cloud SQL", "us-central1", "1,420,910", "4.2", "142.80"],
                ["Cloud Run", "us-central1", "2,290,810", "18.4", "116.50"],
                ["Cloud Storage", "US", "812,400", "22.1", "39.10"],
                ["BigQuery", "US", "1,942", "410.0", "24.60"]
            ],
            totalBytesProcessed: 48_210_400,
            durationMs: 312,
            jobComplete: true
        )
    }

    static func secrets(for projectId: String) -> [SecretItem] {
        [
            SecretItem(name: "projects/\(projectId)/secrets/stripe-live-secret-key", shortName: "stripe-live-secret-key", createTime: Date().addingTimeInterval(-86400 * 120), replicationPolicy: "Automatic", labels: ["env": "prod", "owner": "billing"]),
            SecretItem(name: "projects/\(projectId)/secrets/postgres-orders-dsn", shortName: "postgres-orders-dsn", createTime: Date().addingTimeInterval(-86400 * 90), replicationPolicy: "Automatic", labels: ["env": "prod"]),
            SecretItem(name: "projects/\(projectId)/secrets/oauth-signing-jwk", shortName: "oauth-signing-jwk", createTime: Date().addingTimeInterval(-86400 * 45), replicationPolicy: "User-managed", labels: ["rotation": "90d"])
        ]
    }

    static func secretVersions(for secret: SecretItem) -> [SecretVersion] {
        [
            SecretVersion(name: "\(secret.name)/versions/3", versionNumber: "3", state: "ENABLED", createTime: Date().addingTimeInterval(-86400 * 7)),
            SecretVersion(name: "\(secret.name)/versions/2", versionNumber: "2", state: "DISABLED", createTime: Date().addingTimeInterval(-86400 * 42)),
            SecretVersion(name: "\(secret.name)/versions/1", versionNumber: "1", state: "DESTROYED", createTime: Date().addingTimeInterval(-86400 * 90))
        ]
    }

    static func logEntries(for projectId: String) -> [LogEntry] {
        let now = Date()
        return [
            LogEntry(
                id: "log-1",
                insertId: "67401a9c000a1f",
                timestamp: now.addingTimeInterval(-14),
                severity: .info,
                logName: "run.googleapis.com%2Frequests",
                resourceType: "cloud_run_revision",
                resourceLabels: ["service_name": "checkout-api", "revision_name": "checkout-api-00048-k9p", "location": "us-central1"],
                message: "POST /v2/orders/confirm 200 OK · 19ms · trace=9a41f02e",
                jsonPayload: .object([
                    "httpRequest": .object(["method": .string("POST"), "status": .int(200), "latencyMs": .double(19.4)]),
                    "service": .string("checkout-api"),
                    "region": .string("us-central1")
                ])
            ),
            LogEntry(
                id: "log-2",
                insertId: "67401a8e0009b2",
                timestamp: now.addingTimeInterval(-48),
                severity: .warning,
                logName: "run.googleapis.com%2Fstderr",
                resourceType: "cloud_run_revision",
                resourceLabels: ["service_name": "webhook-ingestor", "location": "us-east1"],
                message: "Retrying downstream delivery attempt 2/5 after 429 Too Many Requests",
                jsonPayload: .object([
                    "attempt": .int(2),
                    "upstreamStatus": .int(429),
                    "retryInMs": .int(1200)
                ])
            ),
            LogEntry(
                id: "log-3",
                insertId: "67401a410004c1",
                timestamp: now.addingTimeInterval(-132),
                severity: .error,
                logName: "run.googleapis.com%2Fstderr",
                resourceType: "cloud_run_revision",
                resourceLabels: ["service_name": "pdf-invoice-worker", "location": "europe-west1"],
                message: "Chromium headless worker exited with OOM (memory limit 2048Mi exceeded)",
                jsonPayload: .object([
                    "error": .string("MemoryLimitExceeded"),
                    "limitMi": .int(2048),
                    "rssMi": .int(2051),
                    "invoiceId": .string("inv_992014")
                ])
            ),
            LogEntry(
                id: "log-4",
                insertId: "674019e00001a0",
                timestamp: now.addingTimeInterval(-290),
                severity: .info,
                logName: "cloudsql.googleapis.com%2Fpostgres.log",
                resourceType: "cloudsql_database",
                resourceLabels: ["database_id": "\(projectId):orders-pg-primary", "region": "us-central1"],
                message: "checkpoint complete: wrote 412 buffers (2.5%); 0 WAL file(s) added, 1 removed",
                jsonPayload: nil
            ),
            LogEntry(
                id: "log-5",
                insertId: "674018b20007d4",
                timestamp: now.addingTimeInterval(-640),
                severity: .notice,
                logName: "cloudaudit.googleapis.com%2Factivity",
                resourceType: "gce_instance",
                resourceLabels: ["instance_id": "1", "zone": "us-central1-a"],
                message: "v1.compute.instances.setMetadata completed by platform@acme.dev",
                jsonPayload: .object([
                    "principalEmail": .string("platform@acme.dev"),
                    "methodName": .string("v1.compute.instances.setMetadata"),
                    "status": .string("OK")
                ])
            ),
            LogEntry(
                id: "log-6",
                insertId: "674017100003f9",
                timestamp: now.addingTimeInterval(-1120),
                severity: .debug,
                logName: "run.googleapis.com%2Fstdout",
                resourceType: "cloud_run_revision",
                resourceLabels: ["service_name": "auth-token-broker", "location": "us-central1"],
                message: "JWK cache hit · kid=key-2026-11 · ttl=3140s",
                jsonPayload: nil
            )
        ]
    }

    static func iamBindings(for projectId: String) -> [IAMBinding] {
        [
            IAMBinding(role: "roles/owner", members: ["user:admin@acme.dev", "group:platform-admins@acme.dev"]),
            IAMBinding(role: "roles/run.admin", members: ["serviceAccount:ci-deployer@\(projectId).iam.gserviceaccount.com", "user:alex@acme.dev"]),
            IAMBinding(role: "roles/compute.instanceAdmin.v1", members: ["serviceAccount:terraform-ops@\(projectId).iam.gserviceaccount.com"]),
            IAMBinding(role: "roles/storage.objectAdmin", members: ["serviceAccount:ci-deployer@\(projectId).iam.gserviceaccount.com", "serviceAccount:elt-pipeline@\(projectId).iam.gserviceaccount.com"]),
            IAMBinding(role: "roles/bigquery.dataViewer", members: ["group:data-analysts@acme.dev"]),
            IAMBinding(role: "roles/secretmanager.secretAccessor", members: ["serviceAccount:checkout-runtime@\(projectId).iam.gserviceaccount.com"])
        ]
    }

    static func enabledAPIs() -> [EnabledAPI] {
        [
            EnabledAPI(name: "compute.googleapis.com", title: "Compute Engine API", description: "Creates and runs virtual machines on Google Cloud Platform.", state: "ENABLED"),
            EnabledAPI(name: "run.googleapis.com", title: "Cloud Run Admin API", description: "Deploy and manage user provided container images that scale to zero.", state: "ENABLED"),
            EnabledAPI(name: "storage.googleapis.com", title: "Cloud Storage JSON API", description: "Stores and retrieves potentially large, immutable data objects.", state: "ENABLED"),
            EnabledAPI(name: "bigquery.googleapis.com", title: "BigQuery API", description: "A data platform for customers to create, manage, share and query data.", state: "ENABLED"),
            EnabledAPI(name: "sqladmin.googleapis.com", title: "Cloud SQL Admin API", description: "API for Cloud SQL database instance management.", state: "ENABLED"),
            EnabledAPI(name: "secretmanager.googleapis.com", title: "Secret Manager API", description: "Stores sensitive data such as API keys, passwords, and certificates.", state: "ENABLED"),
            EnabledAPI(name: "logging.googleapis.com", title: "Cloud Logging API", description: "Writes log entries and manages your Cloud Logging configuration.", state: "ENABLED"),
            EnabledAPI(name: "cloudbilling.googleapis.com", title: "Cloud Billing API", description: "Allows developers to manage billing for their Google Cloud Platform projects.", state: "ENABLED"),
            EnabledAPI(name: "serviceusage.googleapis.com", title: "Service Usage API", description: "Enables services that service consumers want to use on Google Cloud.", state: "ENABLED")
        ]
    }

    /// Builds a rich T3-Code-screenshot-style CostOverview with spiky organic 30-day curves.
    static func costOverview(for projectId: String) -> CostOverview {
        let vmCost = instances(for: projectId).reduce(0.0) { $0 + $1.estimatedMonthlyCost }
        let runCost = cloudRunServices(for: projectId).reduce(0.0) { $0 + $1.estimatedMonthlyCost }
        let sqlCost = sqlInstances(for: projectId).reduce(0.0) { $0 + $1.estimatedMonthlyCost }
        let gcsCost = 39.10
        let bqCost = 24.60
        let total = vmCost + runCost + sqlCost + gcsCost + bqCost

        let colors = CostEstimator.serviceColors
        let items: [(String, String, Int, String, Double, String, NavSection)] = [
            ("Compute Engine", "cpu", instances(for: projectId).count, "\(instances(for: projectId).count) VMs", vmCost, "\(instances(for: projectId).filter(\.isRunning).count) running", .compute),
            ("Cloud SQL", "cylinder.split.1x2", 2, "2 instances", sqlCost, "Postgres 16 HA", .dataServices),
            ("Cloud Run", "bolt.horizontal.fill", 4, "4 services", runCost, "2.29M req/24h", .serverless),
            ("Cloud Storage", "externaldrive", 4, "4 buckets", gcsCost, "1.61 TiB stored", .storage),
            ("BigQuery", "tablecells", 3, "3 datasets", bqCost, "48.2 MB scanned", .dataServices)
        ]

        let serviceSpends: [ServiceSpend] = items.map { item in
            let share = (item.4 / total) * 100.0
            return ServiceSpend(
                id: item.0,
                name: item.0,
                icon: item.1,
                colorHex: colors[item.0] ?? "#71717A",
                resourceCount: item.2,
                countLabel: item.3,
                cost: item.4,
                sharePercent: share,
                usageLabel: "\(Int(round(share)))% of cost · \(item.5)",
                targetSection: item.6
            )
        }.sorted { $0.cost > $1.cost }

        let serviceOrder = serviceSpends.map(\.name)

        // Organic spiky daily curves echoing the T3 Code screenshot
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let spikes: [Int: (Double, Double, Double)] = [
            3:  (0.4, 0.2, 0.1),
            8:  (0.9, 0.4, 0.2),
            14: (2.8, 1.1, 0.4),
            19: (14.2, 6.4, 3.1),
            21: (3.2, 1.8, 0.9),
            25: (6.4, 11.8, 2.2),
            28: (4.1, 3.2, 1.5),
            29: (5.2, 4.0, 2.1)
        ]

        var dailySeries: [DailyCostPoint] = []
        for idx in 0..<30 {
            let offset = idx - 29
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let spike = spikes[idx] ?? (0.0, 0.0, 0.0)
            for svc in serviceSpends {
                let base = (svc.cost / 30.0) * 0.35
                let extra: Double
                switch svc.name {
                case "Compute Engine": extra = spike.0 * (vmCost / 200.0)
                case "Cloud Run": extra = spike.1
                case "Cloud SQL": extra = spike.2 + 1.2
                case "Cloud Storage": extra = (idx % 7 == 0) ? 1.4 : 0.35
                default: extra = (idx % 5 == 0) ? 1.9 : 0.2
                }
                dailySeries.append(DailyCostPoint(date: date, service: svc.name, cost: max(0, base + extra)))
            }
        }

        let totals: [OverviewTotalMetric] = [
            OverviewTotalMetric(label: "Active VMs", value: "\(instances(for: projectId).filter(\.isRunning).count)/\(instances(for: projectId).count)", subtitle: nil),
            OverviewTotalMetric(label: "Cloud Run", value: "2.29M", subtitle: "requests / 24h"),
            OverviewTotalMetric(label: "Storage used", value: "1.61 TiB", subtitle: "4 buckets"),
            OverviewTotalMetric(label: "Cloud SQL", value: "350 GB", subtitle: "2 instances"),
            OverviewTotalMetric(label: "Log volume", value: "4.18 GB", subtitle: "last 30d")
        ]

        let costByType: [CostCategoryItem] = [
            CostCategoryItem(id: "Compute", name: "Compute", cost: vmCost + runCost, colorHex: "#E88255"),
            CostCategoryItem(id: "Databases", name: "Databases", cost: sqlCost + bqCost, colorHex: "#4BC3F7"),
            CostCategoryItem(id: "Storage", name: "Storage", cost: gcsCost, colorHex: "#34D399")
        ]

        let costByService = serviceSpends.map {
            CostCategoryItem(id: $0.name, name: $0.name, cost: $0.cost, colorHex: $0.colorHex)
        }

        let topResources: [TopResourceItem] = [
            TopResourceItem(id: "tr-1", name: instances(for: projectId).first?.name ?? "api-gateway-edge-01", category: "Compute", meta: instances(for: projectId).first?.zone ?? "us-central1-a", metricText: "4 vCPU · 64 GB", cost: vmCost * 0.64, targetSection: .compute),
            TopResourceItem(id: "tr-2", name: "orders-pg-primary", category: "Cloud SQL", meta: "POSTGRES_16 · HA", metricText: "250 GB", cost: 142.80, targetSection: .dataServices),
            TopResourceItem(id: "tr-3", name: "checkout-api", category: "Cloud Run", meta: "us-central1 · 90/10 split", metricText: "1.24M req", cost: 64.80, targetSection: .serverless),
            TopResourceItem(id: "tr-4", name: "redis-sentinel-primary", category: "Compute", meta: "us-central1-b · e2-highmem-2", metricText: "2 vCPU", cost: 66.20, targetSection: .compute)
        ]

        return CostOverview(
            totalSpend: total,
            periodSubtitle: "16 resources · 30 days · Demo estimate",
            serviceSpends: serviceSpends,
            dailySeries: dailySeries,
            totals: totals,
            costByType: costByType,
            costByService: costByService,
            topResources: topResources,
            isEstimate: true,
            serviceOrder: serviceOrder,
            serviceColors: colors
        )
    }
}
