import Foundation
import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    let auth = AuthManager()
    let api = GCPAPIClient()

    // Navigation & Chrome
    var selectedSection: NavSection = .overview
    var selectedDataTab: DataSubTab = .bigQuery
    var sidebarCollapsed = false
    var showCommandPalette = false
    var showAuthSheet = false
    var inspector: InspectorSelection?

    // Toast feedback
    var toastMessage: String?
    var toastIsError = false
    private var toastTask: Task<Void, Never>?

    // Projects
    var projects: [GCPProject] = []
    var selectedProject: GCPProject?
    var billingInfo: BillingInfo?

    // Overview
    var costOverview: CostOverview?
    var isLoadingOverview = false
    var overviewError: String?

    // Compute Engine
    var instances: [ComputeInstance] = []
    var isLoadingCompute = false
    var computeError: String?
    var busyInstanceIds: Set<String> = []

    // Cloud Run
    var cloudRunServices: [CloudRunService] = []
    var cloudRunRevisions: [CloudRunRevision] = []
    var isLoadingCloudRun = false
    var isLoadingRevisions = false
    var cloudRunError: String?

    // Cloud Storage
    var buckets: [GCSBucket] = []
    var selectedBucket: GCSBucket?
    var currentPrefix: String = ""
    var objects: [GCSObject] = []
    var isLoadingStorage = false
    var isUploadingObject = false
    var storageError: String?

    // Cloud Logging
    var logEntries: [LogEntry] = []
    var isLoadingLogs = false
    var loggingError: String?

    // IAM & APIs
    var iamBindings: [IAMBinding] = []
    var enabledAPIs: [EnabledAPI] = []
    var isLoadingIAM = false
    var iamError: String?
    var busyAPINames: Set<String> = []

    // Data & Secrets
    var datasets: [BQDataset] = []
    var selectedDataset: BQDataset?
    var tables: [BQTable] = []
    var lastQueryResult: BQQueryResult?
    var isLoadingBigQuery = false
    var isRunningQuery = false
    var bigQueryError: String?

    var sqlInstances: [CloudSQLInstance] = []
    var isLoadingSQL = false
    var busySQLNames: Set<String> = []
    var sqlError: String?

    var secrets: [SecretItem] = []
    var secretVersions: [SecretVersion] = []
    var revealedSecretValue: String?
    var revealedSecretVersionId: String?
    var isLoadingSecrets = false
    var secretsError: String?

    private var hasBootstrapped = false

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await auth.autoDetectOnLaunch()
        await loadProjectsAndInitialData()
    }

    func reconnectAndReload() async {
        inspector = nil
        await loadProjectsAndInitialData()
    }

    func switchToDemoMode() async {
        auth.switchToDemo()
        inspector = nil
        await loadProjectsAndInitialData()
        showToast("Switched to Demo Mode")
    }

    func loadProjectsAndInitialData() async {
        if auth.isDemo {
            projects = DemoDataProvider.projects
            selectedProject = projects.first
            await refreshCurrentSection()
            return
        }

        do {
            let token = try await auth.validAccessToken()
            let fetched = try await api.listProjects(token: token)
            projects = fetched
            if let preferred = auth.account.projectId,
               let match = fetched.first(where: { $0.projectId == preferred }) {
                selectedProject = match
            } else {
                selectedProject = fetched.first
            }
            if selectedProject == nil, let fallbackId = auth.account.projectId {
                let synth = GCPProject(projectId: fallbackId, name: fallbackId, projectNumber: "", lifecycleState: "ACTIVE", createTime: nil)
                projects = [synth]
                selectedProject = synth
            }
            await refreshCurrentSection()
        } catch {
            showToast(error.localizedDescription, isError: true)
            overviewError = error.localizedDescription
        }
    }

    func selectProject(_ project: GCPProject) async {
        guard selectedProject?.projectId != project.projectId else { return }
        selectedProject = project
        inspector = nil
        selectedBucket = nil
        currentPrefix = ""
        objects = []
        selectedDataset = nil
        tables = []
        lastQueryResult = nil
        revealedSecretValue = nil
        revealedSecretVersionId = nil
        await refreshCurrentSection()
    }

    func navigate(to section: NavSection) {
        selectedSection = section
        Task {
            await loadDataIfNeeded(for: section)
        }
    }

    func loadDataIfNeeded(for section: NavSection) async {
        switch section {
        case .overview:
            if costOverview == nil { await refreshOverview() }
        case .compute:
            if instances.isEmpty { await refreshCompute() }
        case .cloudRun:
            if cloudRunServices.isEmpty { await refreshCloudRun() }
        case .storage:
            if buckets.isEmpty { await refreshBuckets() }
        case .logging:
            if logEntries.isEmpty { await refreshLogs(filter: "") }
        case .iamAndApis:
            if iamBindings.isEmpty && enabledAPIs.isEmpty { await refreshIAMAndAPIs() }
        case .dataServices:
            await refreshDataServices()
        }
    }

    func refreshCurrentSection() async {
        switch selectedSection {
        case .overview: await refreshOverview()
        case .compute: await refreshCompute()
        case .cloudRun: await refreshCloudRun()
        case .storage: await refreshBuckets()
        case .logging: await refreshLogs(filter: "")
        case .iamAndApis: await refreshIAMAndAPIs()
        case .dataServices: await refreshDataServices()
        }
    }

    // MARK: - Overview

    func refreshOverview() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingOverview = true
        overviewError = nil
        defer { isLoadingOverview = false }

        if auth.isDemo {
            billingInfo = DemoDataProvider.billingInfo(for: projectId)
            instances = DemoDataProvider.instances(for: projectId)
            cloudRunServices = DemoDataProvider.cloudRunServices(for: projectId)
            buckets = DemoDataProvider.buckets(for: projectId)
            sqlInstances = DemoDataProvider.sqlInstances(for: projectId)
            datasets = DemoDataProvider.datasets(for: projectId)
            costOverview = DemoDataProvider.costOverview(for: projectId)
            return
        }

        do {
            let token = try await auth.validAccessToken()
            async let billingTask = try? api.getBillingInfo(projectId: projectId, token: token)
            async let vmTask = try? api.listComputeInstances(projectId: projectId, token: token)
            async let runTask = try? api.listCloudRunServices(projectId: projectId, token: token)
            async let bucketTask = try? api.listBuckets(projectId: projectId, token: token)
            async let sqlTask = try? api.listCloudSQLInstances(projectId: projectId, token: token)
            async let bqTask = try? api.listBigQueryDatasets(projectId: projectId, token: token)

            billingInfo = await billingTask
            instances = await vmTask ?? []
            cloudRunServices = await runTask ?? []
            buckets = await bucketTask ?? []
            sqlInstances = await sqlTask ?? []
            datasets = await bqTask ?? []

            costOverview = CostEstimator.buildOverview(
                projectId: projectId,
                instances: instances,
                cloudRun: cloudRunServices,
                buckets: buckets,
                sqlInstances: sqlInstances,
                datasets: datasets,
                logCount: logEntries.count
            )
        } catch {
            overviewError = error.localizedDescription
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Compute Engine

    func refreshCompute() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingCompute = true
        computeError = nil
        defer { isLoadingCompute = false }

        if auth.isDemo {
            instances = DemoDataProvider.instances(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            instances = try await api.listComputeInstances(projectId: projectId, token: token)
        } catch {
            computeError = error.localizedDescription
        }
    }

    func performVMAction(_ instance: ComputeInstance, action: String) async {
        guard let projectId = selectedProject?.projectId else { return }
        busyInstanceIds.insert(instance.id)
        defer { busyInstanceIds.remove(instance.id) }

        if auth.isDemo {
            try? await Task.sleep(for: .milliseconds(350))
            let newStatus: String
            switch action {
            case "start": newStatus = "RUNNING"
            case "stop": newStatus = "TERMINATED"
            default: newStatus = "RUNNING"
            }
            if let idx = instances.firstIndex(where: { $0.id == instance.id }) {
                let old = instances[idx]
                let updated = ComputeInstance(
                    id: old.id,
                    name: old.name,
                    zone: old.zone,
                    machineTypeShort: old.machineTypeShort,
                    status: newStatus,
                    internalIP: old.internalIP,
                    externalIP: newStatus == "RUNNING" ? (old.externalIP ?? "34.132.19.41") : nil,
                    cpuPlatform: old.cpuPlatform,
                    creationTimestamp: old.creationTimestamp,
                    diskSizeGb: old.diskSizeGb,
                    estimatedMonthlyCost: old.estimatedMonthlyCost,
                    labels: old.labels
                )
                instances[idx] = updated
                if case .vm(let current) = inspector, current.id == updated.id {
                    inspector = .vm(updated)
                }
            }
            showToast("\(instance.name): \(action) completed")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            try await api.performComputeAction(
                projectId: projectId,
                zone: instance.zone,
                instance: instance.name,
                action: action,
                token: token
            )
            showToast("\(instance.name): \(action) requested")
            await refreshCompute()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Cloud Run

    func refreshCloudRun() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingCloudRun = true
        cloudRunError = nil
        defer { isLoadingCloudRun = false }

        if auth.isDemo {
            cloudRunServices = DemoDataProvider.cloudRunServices(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            cloudRunServices = try await api.listCloudRunServices(projectId: projectId, token: token)
        } catch {
            cloudRunError = error.localizedDescription
        }
    }

    func inspectCloudRunService(_ service: CloudRunService) async {
        inspector = .cloudRun(service)
        isLoadingRevisions = true
        defer { isLoadingRevisions = false }

        if auth.isDemo {
            cloudRunRevisions = DemoDataProvider.revisions(for: service)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            cloudRunRevisions = try await api.listCloudRunRevisions(serviceFullName: service.fullName, token: token)
        } catch {
            cloudRunRevisions = []
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Cloud Storage

    func refreshBuckets() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingStorage = true
        storageError = nil
        defer { isLoadingStorage = false }

        if auth.isDemo {
            buckets = DemoDataProvider.buckets(for: projectId)
            if selectedBucket == nil, let first = buckets.first {
                await selectBucket(first)
            } else if let selectedBucket {
                objects = DemoDataProvider.objects(bucket: selectedBucket.name, prefix: currentPrefix)
            }
            return
        }

        do {
            let token = try await auth.validAccessToken()
            buckets = try await api.listBuckets(projectId: projectId, token: token)
            if selectedBucket == nil, let first = buckets.first {
                await selectBucket(first)
            } else if let selectedBucket {
                objects = try await api.listObjects(bucket: selectedBucket.name, prefix: currentPrefix, token: token)
            }
        } catch {
            storageError = error.localizedDescription
        }
    }

    func selectBucket(_ bucket: GCSBucket) async {
        selectedBucket = bucket
        currentPrefix = ""
        await loadObjects(bucket: bucket.name, prefix: "")
    }

    func openPrefix(_ prefix: String) async {
        guard let bucket = selectedBucket else { return }
        currentPrefix = prefix
        await loadObjects(bucket: bucket.name, prefix: prefix)
    }

    private func loadObjects(bucket: String, prefix: String) async {
        isLoadingStorage = true
        storageError = nil
        defer { isLoadingStorage = false }

        if auth.isDemo {
            objects = DemoDataProvider.objects(bucket: bucket, prefix: prefix)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            objects = try await api.listObjects(bucket: bucket, prefix: prefix, token: token)
        } catch {
            storageError = error.localizedDescription
        }
    }

    func previewObject(_ object: GCSObject) async {
        if object.isPrefix {
            await openPrefix(object.name)
            return
        }
        if auth.isDemo {
            let preview = object.isPreviewableText ? DemoDataProvider.objectPreviewText(for: object) : nil
            inspector = .gcsObject(object, previewText: preview)
            return
        }
        inspector = .gcsObject(object, previewText: nil)
        guard object.isPreviewableText && object.sizeBytes <= 131_072 else { return }
        do {
            let token = try await auth.validAccessToken()
            let data = try await api.downloadObject(bucket: object.bucket, objectName: object.name, token: token)
            let text = String(data: data, encoding: .utf8)
            inspector = .gcsObject(object, previewText: text)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func downloadObject(_ object: GCSObject) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = object.displayName
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        if auth.isDemo {
            let content = DemoDataProvider.objectPreviewText(for: object)
            try? content.data(using: .utf8)?.write(to: destURL)
            showToast("Saved \(object.displayName)")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            let data = try await api.downloadObject(bucket: object.bucket, objectName: object.name, token: token)
            try data.write(to: destURL)
            showToast("Downloaded \(object.displayName)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func uploadFileToCurrentBucket() async {
        guard let bucket = selectedBucket else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        isUploadingObject = true
        defer { isUploadingObject = false }

        let targetName = currentPrefix + fileURL.lastPathComponent
        if auth.isDemo {
            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attrs?[.size] as? Int64) ?? 1024
            let newObj = GCSObject(
                name: targetName,
                bucket: bucket.name,
                sizeBytes: size,
                contentType: "application/octet-stream",
                updated: Date(),
                isPrefix: false
            )
            objects.append(newObj)
            showToast("Uploaded \(fileURL.lastPathComponent)")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let token = try await auth.validAccessToken()
            try await api.uploadObject(bucket: bucket.name, objectName: targetName, data: data, contentType: mime, token: token)
            showToast("Uploaded \(fileURL.lastPathComponent)")
            await loadObjects(bucket: bucket.name, prefix: currentPrefix)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func deleteObject(_ object: GCSObject) async {
        if auth.isDemo {
            objects.removeAll { $0.id == object.id }
            if case .gcsObject(let cur, _) = inspector, cur.id == object.id {
                inspector = nil
            }
            showToast("Deleted \(object.displayName)")
            return
        }
        do {
            let token = try await auth.validAccessToken()
            try await api.deleteObject(bucket: object.bucket, objectName: object.name, token: token)
            if case .gcsObject(let cur, _) = inspector, cur.id == object.id {
                inspector = nil
            }
            showToast("Deleted \(object.displayName)")
            await loadObjects(bucket: object.bucket, prefix: currentPrefix)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Cloud Logging

    func refreshLogs(filter: String) async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingLogs = true
        loggingError = nil
        defer { isLoadingLogs = false }

        if auth.isDemo {
            logEntries = DemoDataProvider.logEntries(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            logEntries = try await api.listLogEntries(projectId: projectId, filter: filter, token: token)
        } catch {
            loggingError = error.localizedDescription
        }
    }

    // MARK: - IAM & APIs

    func refreshIAMAndAPIs() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingIAM = true
        iamError = nil
        defer { isLoadingIAM = false }

        if auth.isDemo {
            iamBindings = DemoDataProvider.iamBindings(for: projectId)
            enabledAPIs = DemoDataProvider.enabledAPIs()
            return
        }
        do {
            let token = try await auth.validAccessToken()
            async let bindingsTask = api.getIAMPolicy(projectId: projectId, token: token)
            async let apisTask = api.listEnabledAPIs(projectId: projectId, token: token)
            iamBindings = try await bindingsTask
            enabledAPIs = try await apisTask
        } catch {
            iamError = error.localizedDescription
        }
    }

    func toggleAPI(serviceName: String, enable: Bool) async {
        guard let projectId = selectedProject?.projectId else { return }
        busyAPINames.insert(serviceName)
        defer { busyAPINames.remove(serviceName) }

        if auth.isDemo {
            try? await Task.sleep(for: .milliseconds(250))
            if enable {
                if !enabledAPIs.contains(where: { $0.name == serviceName }) {
                    enabledAPIs.append(EnabledAPI(name: serviceName, title: serviceName, description: "Enabled in demo", state: "ENABLED"))
                }
            } else {
                enabledAPIs.removeAll { $0.name == serviceName }
            }
            showToast("\(serviceName) \(enable ? "enabled" : "disabled")")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            try await api.toggleAPI(projectId: projectId, serviceName: serviceName, enable: enable, token: token)
            showToast("\(serviceName) \(enable ? "enabled" : "disabled")")
            await refreshIAMAndAPIs()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Data & Secrets

    func refreshDataServices() async {
        switch selectedDataTab {
        case .bigQuery: await refreshBigQuery()
        case .cloudSQL: await refreshCloudSQL()
        case .secretManager: await refreshSecrets()
        }
    }

    func refreshBigQuery() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingBigQuery = true
        bigQueryError = nil
        defer { isLoadingBigQuery = false }

        if auth.isDemo {
            datasets = DemoDataProvider.datasets(for: projectId)
            if selectedDataset == nil, let first = datasets.first {
                await selectDataset(first)
            }
            return
        }
        do {
            let token = try await auth.validAccessToken()
            datasets = try await api.listBigQueryDatasets(projectId: projectId, token: token)
            if selectedDataset == nil, let first = datasets.first {
                await selectDataset(first)
            }
        } catch {
            bigQueryError = error.localizedDescription
        }
    }

    func selectDataset(_ dataset: BQDataset) async {
        selectedDataset = dataset
        guard let projectId = selectedProject?.projectId else { return }
        if auth.isDemo {
            tables = DemoDataProvider.tables(for: dataset.datasetId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            tables = try await api.listBigQueryTables(projectId: projectId, datasetId: dataset.datasetId, token: token)
        } catch {
            bigQueryError = error.localizedDescription
        }
    }

    func runBigQuery(sql: String) async {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let projectId = selectedProject?.projectId else { return }
        isRunningQuery = true
        bigQueryError = nil
        defer { isRunningQuery = false }

        if auth.isDemo {
            try? await Task.sleep(for: .milliseconds(280))
            lastQueryResult = DemoDataProvider.runDemoSQL(trimmed)
            return
        }

        do {
            let token = try await auth.validAccessToken()
            lastQueryResult = try await api.runBigQuerySQL(projectId: projectId, sql: trimmed, token: token)
        } catch {
            bigQueryError = error.localizedDescription
            showToast(error.localizedDescription, isError: true)
        }
    }

    func refreshCloudSQL() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingSQL = true
        sqlError = nil
        defer { isLoadingSQL = false }

        if auth.isDemo {
            sqlInstances = DemoDataProvider.sqlInstances(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            sqlInstances = try await api.listCloudSQLInstances(projectId: projectId, token: token)
        } catch {
            sqlError = error.localizedDescription
        }
    }

    func restartSQLInstance(_ instance: CloudSQLInstance) async {
        guard let projectId = selectedProject?.projectId else { return }
        busySQLNames.insert(instance.name)
        defer { busySQLNames.remove(instance.name) }

        if auth.isDemo {
            try? await Task.sleep(for: .milliseconds(350))
            showToast("Restarted \(instance.name)")
            return
        }
        do {
            let token = try await auth.validAccessToken()
            try await api.restartCloudSQLInstance(projectId: projectId, instance: instance.name, token: token)
            showToast("Restart requested for \(instance.name)")
            await refreshCloudSQL()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func refreshSecrets() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingSecrets = true
        secretsError = nil
        defer { isLoadingSecrets = false }

        if auth.isDemo {
            secrets = DemoDataProvider.secrets(for: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            secrets = try await api.listSecrets(projectId: projectId, token: token)
        } catch {
            secretsError = error.localizedDescription
        }
    }

    func inspectSecret(_ secret: SecretItem) async {
        inspector = .secret(secret)
        revealedSecretValue = nil
        revealedSecretVersionId = nil

        if auth.isDemo {
            secretVersions = DemoDataProvider.secretVersions(for: secret)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            secretVersions = try await api.listSecretVersions(secretFullName: secret.name, token: token)
        } catch {
            secretVersions = []
            showToast(error.localizedDescription, isError: true)
        }
    }

    func revealSecretVersion(_ version: SecretVersion) async {
        if auth.isDemo {
            revealedSecretVersionId = version.id
            revealedSecretValue = "sk_live_stratus_demo_\(version.versionNumber)_98f21a0c4e"
            return
        }
        do {
            let token = try await auth.validAccessToken()
            let secretVal = try await api.accessSecretVersion(versionFullName: version.name, token: token)
            revealedSecretVersionId = version.id
            revealedSecretValue = secretVal
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: - Utilities

    func copyToClipboard(_ value: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showToast("Copied \(label)")
    }

    func showToast(_ message: String, isError: Bool = false) {
        toastTask?.cancel()
        toastMessage = message
        toastIsError = isError
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }
}
