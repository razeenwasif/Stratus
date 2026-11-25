import Foundation

enum DeepLinkParser {
    static func parse(_ url: URL) -> (section: NavSection?, projectId: String?) {
        guard url.scheme?.lowercased() == "stratus" else {
            return (nil, nil)
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let sectionRaw = queryItems.first(where: { $0.name == "section" })?.value
            ?? (url.host == "navigate" ? nil : url.host)
        let projectId = queryItems.first(where: { $0.name == "project" })?.value

        let section: NavSection?
        if let sectionRaw {
            let lower = sectionRaw.lowercased()
            if lower == "cloudrun" || lower == "functions" {
                section = .serverless
            } else if lower == "gke" {
                section = .compute
            } else if lower == "network" || lower == "vpc" || lower == "builds" || lower == "artifacts" {
                section = .networkAndCI
            } else if lower == "pubsub" || lower == "firestore" || lower == "spanner" || lower == "redis" {
                section = .dataServices
            } else if lower == "firebase" || lower == "auth" || lower == "hosting" || lower == "rules" || lower == "remoteconfig" || lower == "rtdb" {
                section = .firebase
            } else if lower == "metrics" {
                section = .monitoring
            } else {
                section = NavSection.allCases.first {
                    $0.rawValue.caseInsensitiveCompare(sectionRaw) == .orderedSame
                        || $0.shortTitle.caseInsensitiveCompare(sectionRaw) == .orderedSame
                }
            }
        } else {
            section = nil
        }
        return (section, projectId)
    }
}

enum AgentBridgeError: LocalizedError, Sendable {
    case missingArgument(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name): return "Missing required argument: \(name)"
        case .invalidArgument(let msg): return "Invalid argument: \(msg)"
        }
    }
}

/// Shared headless service bridge used by both `MCPServer` (`--mcp`) and `StratusCLI`.
@MainActor
final class AgentBridge {
    let auth: AuthManager
    let api: GCPAPIClient
    private var didBootstrap = false

    init(auth: AuthManager = AuthManager(), api: GCPAPIClient = GCPAPIClient()) {
        self.auth = auth
        self.api = api
    }

    func ensureInitialized(forceDemo: Bool = false) async {
        if forceDemo {
            auth.switchToDemo()
            didBootstrap = true
            return
        }
        if !didBootstrap {
            await auth.autoDetectOnLaunch()
            didBootstrap = true
        }
    }

    private func resolveProjectId(_ explicit: String?) async throws -> String {
        if let explicit, !explicit.isEmpty {
            return explicit
        }
        if let accountProj = auth.account.projectId, !accountProj.isEmpty {
            return accountProj
        }
        if auth.isDemo {
            return DemoDataProvider.projects.first?.projectId ?? "prod-platform-core"
        }
        let token = try await auth.validAccessToken()
        let projects = try await api.listProjects(token: token)
        if let first = projects.first?.projectId {
            return first
        }
        throw AgentBridgeError.missingArgument("projectId")
    }

    // MARK: - 17 Agent Operations

    func status(demo: Bool = false) async -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        return .object([
            "mode": .string(auth.mode.rawValue),
            "modeDisplay": .string(auth.mode.displayName),
            "email": .string(auth.account.email),
            "defaultProjectId": auth.account.projectId.map(AnyCodableValue.string) ?? .null,
            "gcloudPath": auth.detectedGcloudPath.map(AnyCodableValue.string) ?? .null,
            "isDemo": .bool(auth.isDemo)
        ])
    }

    func listProjects(demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let projects: [GCPProject]
        if auth.isDemo {
            projects = DemoDataProvider.projects
        } else {
            let token = try await auth.validAccessToken()
            projects = try await api.listProjects(token: token)
        }
        return .object([
            "count": .int(projects.count),
            "projects": .array(projects.map {
                .object([
                    "projectId": .string($0.projectId),
                    "name": .string($0.name),
                    "projectNumber": .string($0.projectNumber),
                    "lifecycleState": .string($0.lifecycleState)
                ])
            })
        ])
    }

    func overview(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        let overview: CostOverview
        if auth.isDemo {
            overview = DemoDataProvider.costOverview(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            async let vmTask = try? api.listComputeInstances(projectId: pid, token: token)
            async let runTask = try? api.listCloudRunServices(projectId: pid, token: token)
            async let bucketTask = try? api.listBuckets(projectId: pid, token: token)
            async let sqlTask = try? api.listCloudSQLInstances(projectId: pid, token: token)
            async let bqTask = try? api.listBigQueryDatasets(projectId: pid, token: token)

            overview = CostEstimator.buildOverview(
                projectId: pid,
                instances: await vmTask ?? [],
                cloudRun: await runTask ?? [],
                buckets: await bucketTask ?? [],
                sqlInstances: await sqlTask ?? [],
                datasets: await bqTask ?? [],
                logCount: 0
            )
        }

        return .object([
            "projectId": .string(pid),
            "totalSpendUsd": .double((overview.totalSpend * 100).rounded() / 100),
            "periodSubtitle": .string(overview.periodSubtitle),
            "isEstimate": .bool(overview.isEstimate),
            "services": .array(overview.serviceSpends.map {
                .object([
                    "name": .string($0.name),
                    "count": .int($0.resourceCount),
                    "costUsd": .double(($0.cost * 100).rounded() / 100),
                    "sharePercent": .double(($0.sharePercent * 10).rounded() / 10)
                ])
            }),
            "topResources": .array(overview.topResources.map {
                .object([
                    "name": .string($0.name),
                    "category": .string($0.category),
                    "meta": .string($0.meta),
                    "costUsd": .double(($0.cost * 100).rounded() / 100)
                ])
            })
        ])
    }

    func listVMs(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        let vms: [ComputeInstance]
        if auth.isDemo {
            vms = DemoDataProvider.instances(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            vms = try await api.listComputeInstances(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "count": .int(vms.count),
            "instances": .array(vms.map { vm in
                .object([
                    "id": .string(vm.id),
                    "name": .string(vm.name),
                    "zone": .string(vm.zone),
                    "machineType": .string(vm.machineTypeShort),
                    "status": .string(vm.status),
                    "internalIP": vm.internalIP.map(AnyCodableValue.string) ?? .null,
                    "externalIP": vm.externalIP.map(AnyCodableValue.string) ?? .null,
                    "diskSizeGb": .int(vm.diskSizeGb),
                    "sshCommand": .string(vm.sshCommand)
                ])
            })
        ])
    }

    func vmAction(projectId: String?, zone: String, instance: String, action: String, demo: Bool = false) async throws -> AnyCodableValue {
        let allowed = ["start", "stop", "reset"]
        guard allowed.contains(action) else {
            throw AgentBridgeError.invalidArgument("action must be one of: start, stop, reset")
        }
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        if !auth.isDemo {
            let token = try await auth.validAccessToken()
            try await api.performComputeAction(projectId: pid, zone: zone, instance: instance, action: action, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "zone": .string(zone),
            "instance": .string(instance),
            "action": .string(action),
            "status": .string(auth.isDemo ? "simulated" : "requested")
        ])
    }

    func listCloudRun(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        let services: [CloudRunService]
        if auth.isDemo {
            services = DemoDataProvider.cloudRunServices(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            services = try await api.listCloudRunServices(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "count": .int(services.count),
            "services": .array(services.map { svc in
                .object([
                    "name": .string(svc.name),
                    "region": .string(svc.region),
                    "uri": .string(svc.uri),
                    "ready": .bool(svc.conditionsReady),
                    "latestReadyRevision": .string(svc.latestReadyRevision),
                    "ingress": .string(svc.ingress),
                    "cpu": .string(svc.cpu),
                    "memory": .string(svc.memory)
                ])
            })
        ])
    }

    func listBuckets(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        let buckets: [GCSBucket]
        if auth.isDemo {
            buckets = DemoDataProvider.buckets(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            buckets = try await api.listBuckets(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "count": .int(buckets.count),
            "buckets": .array(buckets.map { b in
                .object([
                    "name": .string(b.name),
                    "location": .string(b.location),
                    "storageClass": .string(b.storageClass),
                    "versioningEnabled": .bool(b.versioningEnabled)
                ])
            })
        ])
    }

    func listObjects(bucket: String, prefix: String = "", demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let objects: [GCSObject]
        if auth.isDemo {
            objects = DemoDataProvider.objects(bucket: bucket, prefix: prefix)
        } else {
            let token = try await auth.validAccessToken()
            objects = try await api.listObjects(bucket: bucket, prefix: prefix, token: token)
        }
        return .object([
            "bucket": .string(bucket),
            "prefix": .string(prefix),
            "count": .int(objects.count),
            "objects": .array(objects.map { o in
                .object([
                    "name": .string(o.name),
                    "isFolder": .bool(o.isPrefix),
                    "sizeBytes": .int(Int(o.sizeBytes)),
                    "contentType": .string(o.contentType)
                ])
            })
        ])
    }

    func readObject(bucket: String, objectName: String, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let content: String
        if auth.isDemo {
            let dummy = GCSObject(name: objectName, bucket: bucket, sizeBytes: 1024, contentType: "text/plain", updated: Date(), isPrefix: false)
            content = DemoDataProvider.objectPreviewText(for: dummy)
        } else {
            let token = try await auth.validAccessToken()
            let data = try await api.downloadObject(bucket: bucket, objectName: objectName, token: token)
            let capped = data.prefix(262_144)
            content = String(data: capped, encoding: .utf8) ?? "<binary \(data.count) bytes>"
        }
        return .object([
            "bucket": .string(bucket),
            "objectName": .string(objectName),
            "content": .string(content)
        ])
    }

    func queryLogs(projectId: String?, filter: String = "", pageSize: Int = 50, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        let entries: [LogEntry]
        if auth.isDemo {
            entries = DemoDataProvider.logEntries(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            entries = try await api.listLogEntries(projectId: pid, filter: filter, pageSize: max(1, min(pageSize, 200)), token: token)
        }
        let iso = ISO8601DateFormatter()
        return .object([
            "projectId": .string(pid),
            "count": .int(entries.count),
            "entries": .array(entries.map { e in
                .object([
                    "timestamp": .string(iso.string(from: e.timestamp)),
                    "severity": .string(e.severity.rawValue),
                    "resourceType": .string(e.resourceType),
                    "logName": .string(e.logName),
                    "message": .string(e.message)
                ])
            })
        ])
    }

    func listIAM(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        let bindings: [IAMBinding]
        if auth.isDemo {
            bindings = DemoDataProvider.iamBindings(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            bindings = try await api.getIAMPolicy(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "bindings": .array(bindings.map { b in
                .object([
                    "role": .string(b.role),
                    "members": .array(b.members.map(AnyCodableValue.string))
                ])
            })
        ])
    }

    func listAPIs(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        let apis: [EnabledAPI]
        if auth.isDemo {
            apis = DemoDataProvider.enabledAPIs()
        } else {
            let token = try await auth.validAccessToken()
            apis = try await api.listEnabledAPIs(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "count": .int(apis.count),
            "apis": .array(apis.map { a in
                .object([
                    "name": .string(a.name),
                    "title": .string(a.title),
                    "state": .string(a.state)
                ])
            })
        ])
    }

    func toggleAPI(projectId: String?, serviceName: String, enable: Bool, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)
        if !auth.isDemo {
            let token = try await auth.validAccessToken()
            try await api.toggleAPI(projectId: pid, serviceName: serviceName, enable: enable, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "serviceName": .string(serviceName),
            "action": .string(enable ? "enable" : "disable"),
            "status": .string(auth.isDemo ? "simulated" : "requested")
        ])
    }

    func bigquery(projectId: String?, datasetId: String? = nil, sql: String? = nil, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)

        if let sql, !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let res: BQQueryResult
            if auth.isDemo {
                res = DemoDataProvider.runDemoSQL(sql)
            } else {
                let token = try await auth.validAccessToken()
                res = try await api.runBigQuerySQL(projectId: pid, sql: sql, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "columns": .array(res.columns.map(AnyCodableValue.string)),
                "rows": .array(res.rows.map { .array($0.map(AnyCodableValue.string)) }),
                "totalBytesProcessed": .int(Int(res.totalBytesProcessed)),
                "durationMs": .int(res.durationMs)
            ])
        }

        if let datasetId, !datasetId.isEmpty {
            let tables: [BQTable]
            if auth.isDemo {
                tables = DemoDataProvider.tables(for: datasetId)
            } else {
                let token = try await auth.validAccessToken()
                tables = try await api.listBigQueryTables(projectId: pid, datasetId: datasetId, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "datasetId": .string(datasetId),
                "tables": .array(tables.map {
                    .object(["tableId": .string($0.tableId), "type": .string($0.type)])
                })
            ])
        }

        let datasets: [BQDataset]
        if auth.isDemo {
            datasets = DemoDataProvider.datasets(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            datasets = try await api.listBigQueryDatasets(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "datasets": .array(datasets.map {
                .object(["datasetId": .string($0.datasetId), "location": .string($0.location)])
            })
        ])
    }

    func cloudSQL(projectId: String?, restartInstance: String? = nil, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)

        if let restartInstance, !restartInstance.isEmpty {
            if !auth.isDemo {
                let token = try await auth.validAccessToken()
                try await api.restartCloudSQLInstance(projectId: pid, instance: restartInstance, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "instance": .string(restartInstance),
                "action": .string("restart"),
                "status": .string(auth.isDemo ? "simulated" : "requested")
            ])
        }

        let instances: [CloudSQLInstance]
        if auth.isDemo {
            instances = DemoDataProvider.sqlInstances(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            instances = try await api.listCloudSQLInstances(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "instances": .array(instances.map { s in
                .object([
                    "name": .string(s.name),
                    "databaseVersion": .string(s.databaseVersion),
                    "region": .string(s.region),
                    "state": .string(s.state),
                    "tier": .string(s.tier),
                    "ipAddress": s.ipAddress.map(AnyCodableValue.string) ?? .null
                ])
            })
        ])
    }

    func secrets(projectId: String?, secretName: String? = nil, revealVersion: String? = nil, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveProjectId(projectId)

        if let secretName, !secretName.isEmpty {
            let fullName = secretName.hasPrefix("projects/") ? secretName : "projects/\(pid)/secrets/\(secretName)"
            if let revealVersion, !revealVersion.isEmpty {
                let verFull = "\(fullName)/versions/\(revealVersion)"
                let val: String
                if auth.isDemo {
                    val = "sk_live_stratus_demo_\(revealVersion)_98f21a0c4e"
                } else {
                    let token = try await auth.validAccessToken()
                    val = try await api.accessSecretVersion(versionFullName: verFull, token: token)
                }
                return .object([
                    "secret": .string(secretName),
                    "version": .string(revealVersion),
                    "value": .string(val)
                ])
            }

            let versions: [SecretVersion]
            if auth.isDemo {
                let dummy = SecretItem(name: fullName, shortName: secretName, createTime: nil, replicationPolicy: "Automatic", labels: [:])
                versions = DemoDataProvider.secretVersions(for: dummy)
            } else {
                let token = try await auth.validAccessToken()
                versions = try await api.listSecretVersions(secretFullName: fullName, token: token)
            }
            return .object([
                "secret": .string(secretName),
                "versions": .array(versions.map {
                    .object(["versionNumber": .string($0.versionNumber), "state": .string($0.state)])
                })
            ])
        }

        let items: [SecretItem]
        if auth.isDemo {
            items = DemoDataProvider.secrets(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            items = try await api.listSecrets(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "secrets": .array(items.map {
                .object(["name": .string($0.shortName), "replication": .string($0.replicationPolicy)])
            })
        ])
    }

    func openUI(section: String? = nil, projectId: String? = nil) async throws -> AnyCodableValue {
        var components = URLComponents()
        components.scheme = "stratus"
        components.host = "navigate"
        var items: [URLQueryItem] = []
        if let section, !section.isEmpty {
            items.append(URLQueryItem(name: "section", value: section))
        }
        if let projectId, !projectId.isEmpty {
            items.append(URLQueryItem(name: "project", value: projectId))
        }
        if !items.isEmpty {
            components.queryItems = items
        }
        let targetURL = components.url?.absoluteString ?? "stratus://navigate"

        try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = [targetURL]
            try proc.run()
            proc.waitUntilExit()
        }.value

        return .object([
            "opened": .string(targetURL)
        ])
    }
}
