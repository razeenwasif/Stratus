import Foundation

extension AgentBridge {
    private func resolvePid(_ explicit: String?) async throws -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        if let acct = auth.account.projectId, !acct.isEmpty { return acct }
        if auth.isDemo { return DemoDataProvider.projects.first?.projectId ?? "prod-platform-core" }
        let token = try await auth.validAccessToken()
        if let first = try await api.listProjects(token: token).first?.projectId { return first }
        throw AgentBridgeError.missingArgument("projectId")
    }

    func listGKE(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        let clusters: [GKECluster]
        if auth.isDemo {
            clusters = DemoDataProvider.gkeClusters(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            clusters = try await api.listGKEClusters(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "count": .int(clusters.count),
            "clusters": .array(clusters.map { c in
                .object([
                    "name": .string(c.name),
                    "location": .string(c.location),
                    "status": .string(c.status),
                    "masterVersion": .string(c.masterVersion),
                    "nodeCount": .int(c.nodeCount),
                    "endpoint": .string(c.endpoint)
                ])
            })
        ])
    }

    func listFunctions(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        let fns: [CloudFunctionItem]
        if auth.isDemo {
            fns = DemoDataProvider.cloudFunctions(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            fns = try await api.listCloudFunctions(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "count": .int(fns.count),
            "functions": .array(fns.map { f in
                .object([
                    "name": .string(f.name),
                    "region": .string(f.region),
                    "state": .string(f.state),
                    "runtime": .string(f.runtime),
                    "triggerType": .string(f.triggerType),
                    "uri": .string(f.uri)
                ])
            })
        ])
    }

    func listNetwork(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        let nets: [VPCNetwork]
        let rules: [FirewallRule]
        if auth.isDemo {
            nets = DemoDataProvider.vpcNetworks()
            rules = DemoDataProvider.firewallRules()
        } else {
            let token = try await auth.validAccessToken()
            async let n = api.listVPCNetworks(projectId: pid, token: token)
            async let r = api.listFirewallRules(projectId: pid, token: token)
            nets = try await n
            rules = try await r
        }
        return .object([
            "projectId": .string(pid),
            "networks": .array(nets.map { .object(["name": .string($0.name), "routingMode": .string($0.routingMode), "subnets": .int($0.subnetworkCount)]) }),
            "firewallRules": .array(rules.map { r in
                .object([
                    "name": .string(r.name),
                    "network": .string(r.network),
                    "action": .string(r.action),
                    "direction": .string(r.direction),
                    "priority": .int(r.priority),
                    "protocolsAndPorts": .string(r.protocolsAndPorts)
                ])
            })
        ])
    }

    func listArtifacts(projectId: String?, repoFullName: String? = nil, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        if let repoFullName, !repoFullName.isEmpty {
            let images: [ArtifactImage]
            if auth.isDemo {
                let dummy = ArtifactRepo(name: repoFullName, fullName: repoFullName, location: "us-central1", format: "DOCKER", sizeBytes: 0, description: "")
                images = DemoDataProvider.artifactImages(for: dummy)
            } else {
                let token = try await auth.validAccessToken()
                images = try await api.listArtifactImages(repoFullName: repoFullName, token: token)
            }
            return .object([
                "repository": .string(repoFullName),
                "images": .array(images.map { .object(["name": .string($0.name), "uri": .string($0.uri), "tags": .array($0.tags.map(AnyCodableValue.string))]) })
            ])
        }
        let repos: [ArtifactRepo]
        if auth.isDemo {
            repos = DemoDataProvider.artifactRepos(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            repos = try await api.listArtifactRepos(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "repositories": .array(repos.map { .object(["name": .string($0.name), "fullName": .string($0.fullName), "location": .string($0.location), "format": .string($0.format)]) })
        ])
    }

    func listBuilds(projectId: String?, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        let builds: [CloudBuildItem]
        if auth.isDemo {
            builds = DemoDataProvider.cloudBuilds()
        } else {
            let token = try await auth.validAccessToken()
            builds = try await api.listCloudBuilds(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "builds": .array(builds.map { .object(["id": .string($0.id), "status": .string($0.status), "source": .string($0.sourceSummary), "durationSeconds": $0.durationSeconds.map(AnyCodableValue.int) ?? .null]) })
        ])
    }

    func scheduler(projectId: String?, runJobFullName: String? = nil, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        if let runJobFullName, !runJobFullName.isEmpty {
            if !auth.isDemo {
                let token = try await auth.validAccessToken()
                try await api.runSchedulerJob(jobFullName: runJobFullName, token: token)
            }
            return .object(["job": .string(runJobFullName), "status": .string(auth.isDemo ? "simulated" : "triggered")])
        }
        let jobs: [SchedulerJob]
        if auth.isDemo {
            jobs = DemoDataProvider.schedulerJobs(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            jobs = try await api.listSchedulerJobs(projectId: pid, token: token)
        }
        return .object([
            "projectId": .string(pid),
            "jobs": .array(jobs.map { .object(["name": .string($0.name), "fullName": .string($0.fullName), "schedule": .string($0.schedule), "state": .string($0.state), "target": .string($0.targetSummary)]) })
        ])
    }

    func pubsub(projectId: String?, publishTopic: String? = nil, message: String? = nil, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        if let publishTopic, !publishTopic.isEmpty, let message {
            let fullTopic = publishTopic.hasPrefix("projects/") ? publishTopic : "projects/\(pid)/topics/\(publishTopic)"
            if !auth.isDemo {
                let token = try await auth.validAccessToken()
                try await api.publishPubSubMessage(topicFullName: fullTopic, message: message, token: token)
            }
            return .object(["topic": .string(fullTopic), "status": .string(auth.isDemo ? "simulated" : "published")])
        }
        let topics: [PubSubTopic]
        let subs: [PubSubSubscription]
        if auth.isDemo {
            topics = DemoDataProvider.pubSubTopics(for: pid)
            subs = DemoDataProvider.pubSubSubscriptions(for: pid)
        } else {
            let token = try await auth.validAccessToken()
            async let t = api.listPubSubTopics(projectId: pid, token: token)
            async let s = api.listPubSubSubscriptions(projectId: pid, token: token)
            topics = try await t
            subs = try await s
        }
        return .object([
            "projectId": .string(pid),
            "topics": .array(topics.map { .object(["name": .string($0.name), "fullName": .string($0.fullName)]) }),
            "subscriptions": .array(subs.map { .object(["name": .string($0.name), "topic": .string($0.topicName), "ackDeadlineSeconds": .int($0.ackDeadlineSeconds)]) })
        ])
    }

    func databases(projectId: String?, kind: String = "all", demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        let includeFirestore = (kind == "all" || kind == "firestore")
        let includeSpanner = (kind == "all" || kind == "spanner")
        let includeRedis = (kind == "all" || kind == "redis")

        var out: [String: AnyCodableValue] = ["projectId": .string(pid)]
        if auth.isDemo {
            if includeFirestore {
                out["firestore"] = .array(DemoDataProvider.firestoreDatabases().map {
                    .object(["name": .string($0.name), "location": .string($0.location), "collections": .array($0.collections.map(AnyCodableValue.string))])
                })
            }
            if includeSpanner {
                out["spanner"] = .array(DemoDataProvider.spannerInstances(for: pid).map {
                    .object(["name": .string($0.name), "config": .string($0.config), "processingUnits": .int($0.processingUnits), "databases": .array($0.databases.map(AnyCodableValue.string))])
                })
            }
            if includeRedis {
                out["redis"] = .array(DemoDataProvider.redisInstances(for: pid).map {
                    .object(["name": .string($0.name), "host": .string($0.host), "port": .int($0.port), "memorySizeGb": .int($0.memorySizeGb), "version": .string($0.redisVersion)])
                })
            }
            return .object(out)
        }

        let token = try await auth.validAccessToken()
        if includeFirestore {
            let fs = (try? await api.listFirestoreDatabases(projectId: pid, token: token)) ?? []
            out["firestore"] = .array(fs.map { .object(["name": .string($0.name), "location": .string($0.location), "collections": .array($0.collections.map(AnyCodableValue.string))]) })
        }
        if includeSpanner {
            let sp = (try? await api.listSpannerInstances(projectId: pid, token: token)) ?? []
            out["spanner"] = .array(sp.map { .object(["name": .string($0.name), "config": .string($0.config), "processingUnits": .int($0.processingUnits), "databases": .array($0.databases.map(AnyCodableValue.string))]) })
        }
        if includeRedis {
            let rd = (try? await api.listRedisInstances(projectId: pid, token: token)) ?? []
            out["redis"] = .array(rd.map { .object(["name": .string($0.name), "host": .string($0.host), "port": .int($0.port), "memorySizeGb": .int($0.memorySizeGb), "version": .string($0.redisVersion)]) })
        }
        return .object(out)
    }

    func monitoring(projectId: String?, metricRaw: String = "computeCPU", hours: Int = 24, demo: Bool = false) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolvePid(projectId)
        let metric = MonitoringMetricKind(rawValue: metricRaw) ?? .computeCPU
        let pts: [MonitoringPoint]
        if auth.isDemo {
            pts = DemoDataProvider.monitoringSeries(metric: metric, hours: hours)
        } else {
            let token = try await auth.validAccessToken()
            pts = try await api.queryMonitoringTimeSeries(projectId: pid, metric: metric, hours: hours, token: token)
        }
        let values = pts.map(\.value)
        let peak = values.max() ?? 0
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let iso = ISO8601DateFormatter()
        return .object([
            "projectId": .string(pid),
            "metric": .string(metric.title),
            "unit": .string(metric.unitSuffix),
            "hours": .int(hours),
            "peak": .double((peak * 100).rounded() / 100),
            "average": .double((avg * 100).rounded() / 100),
            "pointCount": .int(pts.count),
            "latestPoints": .array(pts.suffix(12).map {
                .object(["timestamp": .string(iso.string(from: $0.timestamp)), "series": .string($0.seriesName), "value": .double(($0.value * 100).rounded() / 100)])
            })
        ])
    }
}
