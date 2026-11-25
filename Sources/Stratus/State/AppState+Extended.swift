import Foundation

extension AppState {
    func refreshComputeSection() async {
        switch selectedComputeTab {
        case .vms: await refreshCompute()
        case .gke: await refreshGKE()
        }
    }

    func refreshServerlessSection() async {
        switch selectedServerlessTab {
        case .cloudRun: await refreshCloudRun()
        case .functions: await refreshFunctions()
        }
    }

    func refreshNetworkCISection() async {
        switch selectedNetworkCITab {
        case .vpc: await refreshNetwork()
        case .artifacts: await refreshArtifacts()
        case .builds: await refreshBuildsAndScheduler()
        }
    }

    func refreshSecuritySection() async {
        switch selectedSecurityTab {
        case .iam, .apis: await refreshIAMAndAPIs()
        case .secrets: await refreshSecrets()
        }
    }

    // MARK: - GKE

    func refreshGKE() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingGKE = true
        gkeError = nil
        defer { isLoadingGKE = false }

        if auth.isDemo {
            gkeClusters = DemoDataProvider.gkeClusters(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            gkeClusters = try await api.listGKEClusters(projectId: projectId, token: token)
        } catch {
            gkeError = error.localizedDescription
        }
    }

    // MARK: - Cloud Functions v2

    func refreshFunctions() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingFunctions = true
        functionsError = nil
        defer { isLoadingFunctions = false }

        if auth.isDemo {
            cloudFunctions = DemoDataProvider.cloudFunctions(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            cloudFunctions = try await api.listCloudFunctions(projectId: projectId, token: token)
        } catch {
            functionsError = error.localizedDescription
        }
    }

    // MARK: - VPC & Firewalls

    func refreshNetwork() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingNetwork = true
        networkError = nil
        defer { isLoadingNetwork = false }

        if auth.isDemo {
            vpcNetworks = DemoDataProvider.vpcNetworks()
            firewallRules = DemoDataProvider.firewallRules()
            return
        }
        do {
            let token = try await auth.validAccessToken()
            async let nets = api.listVPCNetworks(projectId: projectId, token: token)
            async let rules = api.listFirewallRules(projectId: projectId, token: token)
            vpcNetworks = try await nets
            firewallRules = try await rules
        } catch {
            networkError = error.localizedDescription
        }
    }

    // MARK: - Artifact Registry

    func refreshArtifacts() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingArtifacts = true
        artifactsError = nil
        defer { isLoadingArtifacts = false }

        if auth.isDemo {
            artifactRepos = DemoDataProvider.artifactRepos(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            artifactRepos = try await api.listArtifactRepos(projectId: projectId, token: token)
        } catch {
            artifactsError = error.localizedDescription
        }
    }

    func inspectArtifactRepo(_ repo: ArtifactRepo) async {
        inspector = .artifactRepo(repo)
        isLoadingArtifactImages = true
        defer { isLoadingArtifactImages = false }

        if auth.isDemo {
            artifactImages = DemoDataProvider.artifactImages(for: repo)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            artifactImages = try await api.listArtifactImages(repoFullName: repo.fullName, token: token)
        } catch {
            artifactImages = []
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Cloud Build & Scheduler

    func refreshBuildsAndScheduler() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingBuilds = true
        buildsError = nil
        defer { isLoadingBuilds = false }

        if auth.isDemo {
            cloudBuilds = DemoDataProvider.cloudBuilds()
            schedulerJobs = DemoDataProvider.schedulerJobs(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            async let b = try? api.listCloudBuilds(projectId: projectId, token: token)
            async let s = try? api.listSchedulerJobs(projectId: projectId, token: token)
            cloudBuilds = await b ?? []
            schedulerJobs = await s ?? []
        } catch {
            buildsError = error.localizedDescription
        }
    }

    func runSchedulerJob(_ job: SchedulerJob) async {
        busySchedulerJobs.insert(job.id)
        defer { busySchedulerJobs.remove(job.id) }

        if auth.isDemo {
            try? await Task.sleep(for: .milliseconds(300))
            showToast("Triggered job \(job.name)")
            return
        }
        do {
            let token = try await auth.validAccessToken()
            try await api.runSchedulerJob(jobFullName: job.fullName, token: token)
            showToast("Triggered job \(job.name)")
            await refreshBuildsAndScheduler()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Pub/Sub

    func refreshPubSub() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingPubSub = true
        pubSubError = nil
        defer { isLoadingPubSub = false }

        if auth.isDemo {
            pubSubTopics = DemoDataProvider.pubSubTopics(for: projectId)
            pubSubSubscriptions = DemoDataProvider.pubSubSubscriptions(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            async let t = api.listPubSubTopics(projectId: projectId, token: token)
            async let s = api.listPubSubSubscriptions(projectId: projectId, token: token)
            pubSubTopics = try await t
            pubSubSubscriptions = try await s
        } catch {
            pubSubError = error.localizedDescription
        }
    }

    func publishPubSubMessage(topic: PubSubTopic, payload: String) async {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if auth.isDemo {
            showToast("Published message to \(topic.name) (demo)")
            return
        }
        do {
            let token = try await auth.validAccessToken()
            try await api.publishPubSubMessage(topicFullName: topic.fullName, message: trimmed, token: token)
            showToast("Published message to \(topic.name)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Firestore, Spanner, Memorystore Redis

    func refreshFirestore() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingFirestore = true
        firestoreError = nil
        defer { isLoadingFirestore = false }

        if auth.isDemo {
            firestoreDatabases = DemoDataProvider.firestoreDatabases()
            if !firestoreDatabases.contains(where: { $0.name == selectedFirestoreDatabaseId }),
               let first = firestoreDatabases.first {
                selectedFirestoreDatabaseId = first.name
            }
            await loadFirestoreCollectionsAtCurrentParent(autoOpenFirst: selectedFirestoreCollectionPath.isEmpty)
            await loadFirestoreIndexes()
            return
        }
        do {
            let token = try await auth.validAccessToken()
            firestoreDatabases = try await api.listFirestoreDatabases(projectId: projectId, token: token)
            if !firestoreDatabases.contains(where: { $0.name == selectedFirestoreDatabaseId }),
               let first = firestoreDatabases.first {
                selectedFirestoreDatabaseId = first.name
            }
            await loadFirestoreCollectionsAtCurrentParent(autoOpenFirst: selectedFirestoreCollectionPath.isEmpty)
            await loadFirestoreIndexes()
        } catch {
            firestoreError = error.localizedDescription
        }
    }

    func refreshSpanner() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingSpanner = true
        spannerError = nil
        defer { isLoadingSpanner = false }

        if auth.isDemo {
            spannerInstances = DemoDataProvider.spannerInstances(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            spannerInstances = try await api.listSpannerInstances(projectId: projectId, token: token)
        } catch {
            spannerError = error.localizedDescription
        }
    }

    func refreshRedis() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingRedis = true
        redisError = nil
        defer { isLoadingRedis = false }

        if auth.isDemo {
            redisInstances = DemoDataProvider.redisInstances(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            redisInstances = try await api.listRedisInstances(projectId: projectId, token: token)
        } catch {
            redisError = error.localizedDescription
        }
    }

    // MARK: - Cloud Monitoring

    func refreshMonitoring(metric: MonitoringMetricKind? = nil, hours: Int? = nil) async {
        if let metric { selectedMetricKind = metric }
        if let hours { monitoringHours = hours }
        guard let projectId = selectedProject?.projectId else { return }

        isLoadingMonitoring = true
        monitoringError = nil
        defer { isLoadingMonitoring = false }

        if auth.isDemo {
            monitoringPoints = DemoDataProvider.monitoringSeries(metric: selectedMetricKind, hours: monitoringHours)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            monitoringPoints = try await api.queryMonitoringTimeSeries(
                projectId: projectId,
                metric: selectedMetricKind,
                hours: monitoringHours,
                token: token
            )
        } catch {
            monitoringError = error.localizedDescription
        }
    }
}
