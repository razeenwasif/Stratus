import Foundation

extension GCPParser {
    static func decodeGKEClusters(from data: Data) throws -> [GKECluster] {
        struct Response: Decodable {
            struct ClusterDTO: Decodable {
                struct PoolDTO: Decodable {
                    struct ConfigDTO: Decodable { let machineType: String? }
                    let name: String
                    let initialNodeCount: Int?
                    let status: String?
                    let config: ConfigDTO?
                }
                let name: String
                let location: String?
                let zone: String?
                let status: String?
                let currentMasterVersion: String?
                let currentNodeCount: Int?
                let endpoint: String?
                let network: String?
                let nodePools: [PoolDTO]?
            }
            let clusters: [ClusterDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.clusters ?? []).map { dto in
            let pools = (dto.nodePools ?? []).map { p in
                GKENodePool(
                    name: p.name,
                    machineType: p.config?.machineType ?? "e2-standard-4",
                    nodeCount: p.initialNodeCount ?? 1,
                    status: p.status ?? "RUNNING"
                )
            }
            let totalNodes = dto.currentNodeCount ?? pools.reduce(0) { $0 + $1.nodeCount }
            return GKECluster(
                name: dto.name,
                location: dto.location ?? dto.zone ?? "us-central1",
                status: dto.status ?? "RUNNING",
                masterVersion: dto.currentMasterVersion ?? "1.30",
                nodeCount: totalNodes,
                endpoint: dto.endpoint ?? "",
                network: dto.network ?? "default",
                nodePools: pools
            )
        }
    }

    static func decodeCloudFunctions(from data: Data) throws -> [CloudFunctionItem] {
        struct Response: Decodable {
            struct FunctionDTO: Decodable {
                struct BuildConfig: Decodable { let runtime: String? }
                struct ServiceConfig: Decodable { let uri: String?; let availableMemory: String? }
                struct EventTrigger: Decodable { let eventType: String? }
                let name: String
                let state: String?
                let updateTime: String?
                let buildConfig: BuildConfig?
                let serviceConfig: ServiceConfig?
                let eventTrigger: EventTrigger?
            }
            let functions: [FunctionDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.functions ?? []).map { dto in
            let parts = dto.name.split(separator: "/").map(String.init)
            let short = parts.last ?? dto.name
            let region: String
            if let idx = parts.firstIndex(of: "locations"), idx + 1 < parts.count {
                region = parts[idx + 1]
            } else {
                region = "us-central1"
            }
            let trigger = dto.eventTrigger?.eventType?.split(separator: ".").last.map(String.init) ?? "HTTPS"
            return CloudFunctionItem(
                id: dto.name,
                name: short,
                region: region,
                state: dto.state ?? "ACTIVE",
                runtime: dto.buildConfig?.runtime ?? "nodejs20",
                uri: dto.serviceConfig?.uri ?? "",
                memory: dto.serviceConfig?.availableMemory ?? "256M",
                triggerType: trigger,
                updated: parseISO8601(dto.updateTime)
            )
        }
    }

    static func decodeVPCNetworks(from data: Data) throws -> [VPCNetwork] {
        struct Response: Decodable {
            struct NetworkDTO: Decodable {
                struct RoutingConfig: Decodable { let routingMode: String? }
                let name: String
                let autoCreateSubnetworks: Bool?
                let routingConfig: RoutingConfig?
                let subnetworks: [String]?
            }
            let items: [NetworkDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.items ?? []).map { dto in
            VPCNetwork(
                name: dto.name,
                autoCreateSubnetworks: dto.autoCreateSubnetworks ?? false,
                routingMode: dto.routingConfig?.routingMode ?? "REGIONAL",
                subnetworkCount: dto.subnetworks?.count ?? 0
            )
        }
    }

    static func decodeFirewallRules(from data: Data) throws -> [FirewallRule] {
        struct Response: Decodable {
            struct RuleDTO: Decodable {
                struct ProtoDTO: Decodable {
                    let IPProtocol: String?
                    let ports: [String]?
                }
                let name: String
                let network: String?
                let direction: String?
                let priority: Int?
                let disabled: Bool?
                let allowed: [ProtoDTO]?
                let denied: [ProtoDTO]?
                let sourceRanges: [String]?
                let targetTags: [String]?
            }
            let items: [RuleDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.items ?? []).map { dto in
            let isDeny = (dto.denied?.isEmpty == false)
            let rules = isDeny ? (dto.denied ?? []) : (dto.allowed ?? [])
            let protoStr = rules.map { r in
                let p = r.IPProtocol ?? "all"
                if let ports = r.ports, !ports.isEmpty {
                    return "\(p):\(ports.joined(separator: ","))"
                }
                return p
            }.joined(separator: " ")
            return FirewallRule(
                name: dto.name,
                network: dto.network?.split(separator: "/").last.map(String.init) ?? "default",
                direction: dto.direction ?? "INGRESS",
                priority: dto.priority ?? 1000,
                disabled: dto.disabled ?? false,
                action: isDeny ? "DENY" : "ALLOW",
                protocolsAndPorts: protoStr.isEmpty ? "all" : protoStr,
                sourceRanges: dto.sourceRanges ?? [],
                targetTags: dto.targetTags ?? []
            )
        }.sorted { $0.priority < $1.priority }
    }

    static func decodeArtifactRepos(from data: Data) throws -> [ArtifactRepo] {
        struct Response: Decodable {
            struct RepoDTO: Decodable {
                let name: String
                let format: String?
                let sizeBytes: String?
                let description: String?
            }
            let repositories: [RepoDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.repositories ?? []).map { dto in
            let parts = dto.name.split(separator: "/").map(String.init)
            let short = parts.last ?? dto.name
            let loc: String
            if let idx = parts.firstIndex(of: "locations"), idx + 1 < parts.count {
                loc = parts[idx + 1]
            } else {
                loc = "us"
            }
            return ArtifactRepo(
                name: short,
                fullName: dto.name,
                location: loc,
                format: dto.format ?? "DOCKER",
                sizeBytes: Int64(dto.sizeBytes ?? "0") ?? 0,
                description: dto.description ?? ""
            )
        }
    }

    static func decodeCloudBuilds(from data: Data) throws -> [CloudBuildItem] {
        struct Response: Decodable {
            struct BuildDTO: Decodable {
                struct TimingSpan: Decodable { let startTime: String?; let endTime: String? }
                struct Source: Decodable {
                    struct RepoSource: Decodable { let repoName: String?; let branchName: String? }
                    let repoSource: RepoSource?
                }
                let id: String
                let status: String?
                let createTime: String?
                let logUrl: String?
                let source: Source?
                let timing: [String: TimingSpan]?
            }
            let builds: [BuildDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.builds ?? []).map { dto in
            let created = parseISO8601(dto.createTime)
            var duration: Int?
            if let span = dto.timing?["BUILD"],
               let s = parseISO8601(span.startTime),
               let e = parseISO8601(span.endTime) {
                duration = max(1, Int(e.timeIntervalSince(s)))
            }
            let repo = dto.source?.repoSource?.repoName ?? "manual"
            let branch = dto.source?.repoSource?.branchName
            let src = branch != nil ? "\(repo)@\(branch!)" : repo
            return CloudBuildItem(
                id: dto.id,
                status: dto.status ?? "WORKING",
                createTime: created,
                durationSeconds: duration,
                sourceSummary: src,
                logUrl: dto.logUrl
            )
        }
    }

    static func decodeSchedulerJobs(from data: Data) throws -> [SchedulerJob] {
        struct Response: Decodable {
            struct JobDTO: Decodable {
                struct HttpTarget: Decodable { let uri: String? }
                struct PubsubTarget: Decodable { let topicName: String? }
                let name: String
                let schedule: String?
                let timeZone: String?
                let state: String?
                let lastAttemptTime: String?
                let httpTarget: HttpTarget?
                let pubsubTarget: PubsubTarget?
            }
            let jobs: [JobDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.jobs ?? []).map { dto in
            let parts = dto.name.split(separator: "/").map(String.init)
            let short = parts.last ?? dto.name
            let loc: String
            if let idx = parts.firstIndex(of: "locations"), idx + 1 < parts.count {
                loc = parts[idx + 1]
            } else {
                loc = "us-central1"
            }
            let target = dto.httpTarget?.uri ?? dto.pubsubTarget?.topicName?.split(separator: "/").last.map(String.init) ?? "target"
            return SchedulerJob(
                name: short,
                fullName: dto.name,
                location: loc,
                schedule: dto.schedule ?? "* * * * *",
                timeZone: dto.timeZone ?? "UTC",
                state: dto.state ?? "ENABLED",
                targetSummary: target,
                lastAttemptTime: parseISO8601(dto.lastAttemptTime)
            )
        }
    }

    static func decodeMonitoringTimeSeries(from data: Data, metric: MonitoringMetricKind) throws -> [MonitoringPoint] {
        struct Response: Decodable {
            struct SeriesDTO: Decodable {
                struct MetricInfo: Decodable { let labels: [String: String]? }
                struct ResourceInfo: Decodable { let labels: [String: String]? }
                struct PointDTO: Decodable {
                    struct Interval: Decodable { let endTime: String? }
                    struct TypedValue: Decodable {
                        let doubleValue: Double?
                        let int64Value: String?
                    }
                    let interval: Interval?
                    let value: TypedValue?
                }
                let metric: MetricInfo?
                let resource: ResourceInfo?
                let points: [PointDTO]?
            }
            let timeSeries: [SeriesDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var results: [MonitoringPoint] = []
        for (idx, series) in (decoded.timeSeries ?? []).prefix(5).enumerated() {
            let labels = series.resource?.labels ?? series.metric?.labels ?? [:]
            let labelName = labels["instance_name"]
                ?? labels["service_name"]
                ?? labels["database_id"]
                ?? labels["instance_id"]
                ?? "series-\(idx + 1)"

            for pt in series.points ?? [] {
                guard let ts = parseISO8601(pt.interval?.endTime) else { continue }
                let rawVal = pt.value?.doubleValue ?? Double(pt.value?.int64Value ?? "0") ?? 0
                let scaled = metric.isPercentage ? rawVal * 100.0 : rawVal
                results.append(MonitoringPoint(timestamp: ts, seriesName: labelName, value: max(0, scaled)))
            }
        }
        return results.sorted { $0.timestamp < $1.timestamp }
    }

    static func decodeRedisInstances(from data: Data) throws -> [RedisInstance] {
        struct Response: Decodable {
            struct RedisDTO: Decodable {
                let name: String
                let tier: String?
                let memorySizeGb: Int?
                let host: String?
                let port: Int?
                let redisVersion: String?
                let state: String?
                let locationId: String?
            }
            let instances: [RedisDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.instances ?? []).map { dto in
            let parts = dto.name.split(separator: "/").map(String.init)
            let short = parts.last ?? dto.name
            let loc: String
            if let l = dto.locationId { loc = l }
            else if let idx = parts.firstIndex(of: "locations"), idx + 1 < parts.count { loc = parts[idx + 1] }
            else { loc = "us-central1" }
            return RedisInstance(
                name: short,
                fullName: dto.name,
                location: loc,
                tier: dto.tier ?? "STANDARD_HA",
                memorySizeGb: dto.memorySizeGb ?? 4,
                host: dto.host ?? "10.0.0.1",
                port: dto.port ?? 6379,
                redisVersion: dto.redisVersion ?? "REDIS_7_0",
                state: dto.state ?? "READY"
            )
        }
    }
}

extension GCPAPIClient {
    // MARK: - GKE

    func listGKEClusters(projectId: String, token: String) async throws -> [GKECluster] {
        let data = try await rawRequest(
            urlString: "https://container.googleapis.com/v1/projects/\(projectId)/locations/-/clusters",
            token: token
        )
        return try GCPParser.decodeGKEClusters(from: data)
    }

    // MARK: - Cloud Functions v2

    func listCloudFunctions(projectId: String, token: String) async throws -> [CloudFunctionItem] {
        let data = try await rawRequest(
            urlString: "https://cloudfunctions.googleapis.com/v2/projects/\(projectId)/locations/-/functions",
            token: token
        )
        return try GCPParser.decodeCloudFunctions(from: data)
    }

    // MARK: - VPC & Firewalls

    func listVPCNetworks(projectId: String, token: String) async throws -> [VPCNetwork] {
        let data = try await rawRequest(
            urlString: "https://compute.googleapis.com/compute/v1/projects/\(projectId)/global/networks",
            token: token
        )
        return try GCPParser.decodeVPCNetworks(from: data)
    }

    func listFirewallRules(projectId: String, token: String) async throws -> [FirewallRule] {
        let data = try await rawRequest(
            urlString: "https://compute.googleapis.com/compute/v1/projects/\(projectId)/global/firewalls",
            token: token
        )
        return try GCPParser.decodeFirewallRules(from: data)
    }

    // MARK: - Artifact Registry

    func listArtifactRepos(projectId: String, token: String) async throws -> [ArtifactRepo] {
        let data = try await rawRequest(
            urlString: "https://artifactregistry.googleapis.com/v1/projects/\(projectId)/locations/-/repositories",
            token: token
        )
        return try GCPParser.decodeArtifactRepos(from: data)
    }

    func listArtifactImages(repoFullName: String, token: String) async throws -> [ArtifactImage] {
        struct Response: Decodable {
            struct ImageDTO: Decodable {
                let name: String
                let uri: String
                let tags: [String]?
                let imageSizeBytes: String?
                let uploadTime: String?
            }
            let dockerImages: [ImageDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://artifactregistry.googleapis.com/v1/\(repoFullName)/dockerImages?pageSize=40",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.dockerImages ?? []).map { dto in
            let short = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
            return ArtifactImage(
                name: short,
                uri: dto.uri,
                tags: dto.tags ?? [],
                sizeBytes: Int64(dto.imageSizeBytes ?? "0") ?? 0,
                uploadTime: GCPParser.parseISO8601(dto.uploadTime)
            )
        }
    }

    // MARK: - Cloud Build & Cloud Scheduler

    func listCloudBuilds(projectId: String, token: String) async throws -> [CloudBuildItem] {
        let data = try await rawRequest(
            urlString: "https://cloudbuild.googleapis.com/v1/projects/\(projectId)/builds?pageSize=30",
            token: token
        )
        return try GCPParser.decodeCloudBuilds(from: data)
    }

    func listSchedulerJobs(projectId: String, token: String) async throws -> [SchedulerJob] {
        let data = try await rawRequest(
            urlString: "https://cloudscheduler.googleapis.com/v1/projects/\(projectId)/locations/-/jobs",
            token: token
        )
        return try GCPParser.decodeSchedulerJobs(from: data)
    }

    func runSchedulerJob(jobFullName: String, token: String) async throws {
        _ = try await rawRequest(
            urlString: "https://cloudscheduler.googleapis.com/v1/\(jobFullName):run",
            method: "POST",
            body: Data("{}".utf8),
            token: token
        )
    }

    // MARK: - Pub/Sub

    func listPubSubTopics(projectId: String, token: String) async throws -> [PubSubTopic] {
        struct Response: Decodable {
            struct TopicDTO: Decodable { let name: String }
            let topics: [TopicDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://pubsub.googleapis.com/v1/projects/\(projectId)/topics?pageSize=100",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.topics ?? []).map {
            PubSubTopic(name: $0.name.split(separator: "/").last.map(String.init) ?? $0.name, fullName: $0.name)
        }
    }

    func listPubSubSubscriptions(projectId: String, token: String) async throws -> [PubSubSubscription] {
        struct Response: Decodable {
            struct SubDTO: Decodable {
                struct PushConfig: Decodable { let pushEndpoint: String? }
                let name: String
                let topic: String?
                let ackDeadlineSeconds: Int?
                let pushConfig: PushConfig?
            }
            let subscriptions: [SubDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://pubsub.googleapis.com/v1/projects/\(projectId)/subscriptions?pageSize=100",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.subscriptions ?? []).map { dto in
            PubSubSubscription(
                name: dto.name.split(separator: "/").last.map(String.init) ?? dto.name,
                fullName: dto.name,
                topicName: dto.topic?.split(separator: "/").last.map(String.init) ?? "—",
                ackDeadlineSeconds: dto.ackDeadlineSeconds ?? 10,
                pushEndpoint: dto.pushConfig?.pushEndpoint
            )
        }
    }

    func publishPubSubMessage(topicFullName: String, message: String, token: String) async throws {
        let b64 = Data(message.utf8).base64EncodedString()
        let body = try JSONSerialization.data(withJSONObject: ["messages": [["data": b64]]])
        _ = try await rawRequest(
            urlString: "https://pubsub.googleapis.com/v1/\(topicFullName):publish",
            method: "POST",
            body: body,
            token: token
        )
    }

    // MARK: - Firestore, Spanner, Memorystore Redis

    func listFirestoreDatabases(projectId: String, token: String) async throws -> [FirestoreDatabase] {
        struct Response: Decodable {
            struct DBDTO: Decodable {
                let name: String
                let locationId: String?
                let type: String?
                let concurrencyMode: String?
            }
            let databases: [DBDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var dbs: [FirestoreDatabase] = []
        for dto in decoded.databases ?? [] {
            let dbId = dto.name.split(separator: "/").last.map(String.init) ?? "(default)"
            let cols = (try? await listFirestoreCollections(projectId: projectId, databaseId: dbId, token: token)) ?? []
            dbs.append(FirestoreDatabase(
                name: dbId,
                location: dto.locationId ?? "nam5",
                type: dto.type ?? "FIRESTORE_NATIVE",
                concurrencyMode: dto.concurrencyMode ?? "OPTIMISTIC",
                collections: cols
            ))
        }
        return dbs
    }

    func listFirestoreCollections(projectId: String, databaseId: String, token: String) async throws -> [String] {
        struct Response: Decodable { let collectionIds: [String]? }
        let data = try await rawRequest(
            urlString: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(databaseId)/documents:listCollectionIds",
            method: "POST",
            body: Data("{\"pageSize\":50}".utf8),
            token: token
        )
        return try JSONDecoder().decode(Response.self, from: data).collectionIds ?? []
    }

    func listSpannerInstances(projectId: String, token: String) async throws -> [SpannerInstance] {
        struct Response: Decodable {
            struct InstDTO: Decodable {
                let name: String
                let config: String?
                let nodeCount: Int?
                let processingUnits: Int?
                let state: String?
            }
            let instances: [InstDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://spanner.googleapis.com/v1/projects/\(projectId)/instances",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var list: [SpannerInstance] = []
        for dto in decoded.instances ?? [] {
            let short = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
            let dbs = (try? await listSpannerDatabases(instanceFullName: dto.name, token: token)) ?? []
            list.append(SpannerInstance(
                name: short,
                fullName: dto.name,
                config: dto.config?.split(separator: "/").last.map(String.init) ?? "regional",
                nodeCount: dto.nodeCount ?? 1,
                processingUnits: dto.processingUnits ?? 1000,
                state: dto.state ?? "READY",
                databases: dbs
            ))
        }
        return list
    }

    func listSpannerDatabases(instanceFullName: String, token: String) async throws -> [String] {
        struct Response: Decodable {
            struct DBDTO: Decodable { let name: String }
            let databases: [DBDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://spanner.googleapis.com/v1/\(instanceFullName)/databases",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.databases ?? []).map { $0.name.split(separator: "/").last.map(String.init) ?? $0.name }
    }

    func listRedisInstances(projectId: String, token: String) async throws -> [RedisInstance] {
        let data = try await rawRequest(
            urlString: "https://redis.googleapis.com/v1/projects/\(projectId)/locations/-/instances",
            token: token
        )
        return try GCPParser.decodeRedisInstances(from: data)
    }

    // MARK: - Cloud Monitoring

    func queryMonitoringTimeSeries(projectId: String, metric: MonitoringMetricKind, hours: Int = 24, token: String) async throws -> [MonitoringPoint] {
        let end = Date()
        let start = end.addingTimeInterval(-TimeInterval(hours * 3600))
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://monitoring.googleapis.com/v3/projects/\(projectId)/timeSeries")!
        components.queryItems = [
            URLQueryItem(name: "filter", value: "metric.type = \"\(metric.metricType)\""),
            URLQueryItem(name: "interval.startTime", value: iso.string(from: start)),
            URLQueryItem(name: "interval.endTime", value: iso.string(from: end)),
            URLQueryItem(name: "aggregation.alignmentPeriod", value: hours <= 1 ? "60s" : (hours <= 6 ? "300s" : "1800s")),
            URLQueryItem(name: "aggregation.perSeriesAligner", value: metric == .cloudRunRequests ? "ALIGN_RATE" : "ALIGN_MEAN"),
            URLQueryItem(name: "view", value: "FULL")
        ]
        guard let urlStr = components.url?.absoluteString else {
            throw GCPAPIError.invalidURL("monitoring timeSeries")
        }
        let data = try await rawRequest(urlString: urlStr, token: token)
        return try GCPParser.decodeMonitoringTimeSeries(from: data, metric: metric)
    }
}
