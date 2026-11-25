import Foundation

enum GCPAPIError: LocalizedError, Sendable {
    case invalidURL(String)
    case httpError(code: Int, status: String?, message: String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid Google Cloud API URL: \(url)"
        case .httpError(let code, let status, let message):
            if let status, !status.isEmpty {
                return "[\(code) \(status)] \(message)"
            }
            return "[\(code)] \(message)"
        case .decodingError(let msg):
            return "Failed to parse API response: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        }
    }
}

/// Pure decoding & URL-encoding helpers exposed internally for unit tests.
enum GCPParser {
    static func encodeGCSObjectName(_ name: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/?#&=+%")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: raw) { return d }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
    }

    static func decodeProjects(from data: Data) throws -> [GCPProject] {
        struct Response: Decodable {
            struct ProjectDTO: Decodable {
                let projectId: String
                let displayName: String?
                let name: String?
                let state: String?
                let createTime: String?
            }
            let projects: [ProjectDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.projects ?? []).map { dto in
            let number = dto.name?.split(separator: "/").last.map(String.init) ?? ""
            return GCPProject(
                projectId: dto.projectId,
                name: dto.displayName ?? dto.projectId,
                projectNumber: number,
                lifecycleState: dto.state ?? "ACTIVE",
                createTime: dto.createTime
            )
        }
    }

    static func decodeComputeAggregatedInstances(from data: Data) throws -> [ComputeInstance] {
        struct Response: Decodable {
            struct ZoneScope: Decodable {
                struct InstanceDTO: Decodable {
                    struct NetworkInterface: Decodable {
                        struct AccessConfig: Decodable {
                            let natIP: String?
                        }
                        let networkIP: String?
                        let accessConfigs: [AccessConfig]?
                    }
                    struct DiskDTO: Decodable {
                        let diskSizeGb: String?
                    }
                    let id: String?
                    let name: String
                    let zone: String?
                    let machineType: String?
                    let status: String?
                    let cpuPlatform: String?
                    let creationTimestamp: String?
                    let networkInterfaces: [NetworkInterface]?
                    let disks: [DiskDTO]?
                    let labels: [String: String]?
                }
                let instances: [InstanceDTO]?
            }
            let items: [String: ZoneScope]?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var result: [ComputeInstance] = []
        for (scopeKey, scopeVal) in decoded.items ?? [:] {
            let zoneFallback = scopeKey.replacingOccurrences(of: "zones/", with: "")
            for dto in scopeVal.instances ?? [] {
                let zoneName = dto.zone?.split(separator: "/").last.map(String.init) ?? zoneFallback
                let machineShort = dto.machineType?.split(separator: "/").last.map(String.init) ?? "e2-medium"
                let internalIP = dto.networkInterfaces?.first?.networkIP
                let externalIP = dto.networkInterfaces?.first?.accessConfigs?.first?.natIP
                let diskGb = dto.disks?.compactMap { Int($0.diskSizeGb ?? "0") }.reduce(0, +) ?? 20
                let status = dto.status ?? "UNKNOWN"
                let estMonthly = estimateVMCost(machineType: machineShort, diskGb: diskGb, running: status == "RUNNING")

                result.append(ComputeInstance(
                    id: dto.id ?? "\(zoneName)-\(dto.name)",
                    name: dto.name,
                    zone: zoneName,
                    machineTypeShort: machineShort,
                    status: status,
                    internalIP: internalIP,
                    externalIP: externalIP,
                    cpuPlatform: dto.cpuPlatform,
                    creationTimestamp: dto.creationTimestamp,
                    diskSizeGb: diskGb,
                    estimatedMonthlyCost: estMonthly,
                    labels: dto.labels ?? [:]
                ))
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    static func estimateVMCost(machineType: String, diskGb: Int, running: Bool) -> Double {
        let storageCost = Double(diskGb) * 0.04
        guard running else { return storageCost }
        let parts = machineType.split(separator: "-")
        let vcpus = parts.last.flatMap { Int($0) } ?? (machineType.contains("micro") ? 1 : 2)
        let perVcpuMonth: Double
        if machineType.hasPrefix("e2-") { perVcpuMonth = 24.5 }
        else if machineType.hasPrefix("n2-") || machineType.hasPrefix("c2-") { perVcpuMonth = 34.0 }
        else if machineType.hasPrefix("n1-") { perVcpuMonth = 29.0 }
        else { perVcpuMonth = 28.0 }
        return Double(vcpus) * perVcpuMonth + storageCost
    }

    static func decodeCloudRunServices(from data: Data) throws -> [CloudRunService] {
        struct Response: Decodable {
            struct ServiceDTO: Decodable {
                struct Condition: Decodable {
                    let type: String?
                    let state: String?
                }
                struct TrafficDTO: Decodable {
                    let revision: String?
                    let percent: Int?
                    let type: String?
                }
                struct TemplateDTO: Decodable {
                    struct ScalingDTO: Decodable {
                        let minInstanceCount: Int?
                        let maxInstanceCount: Int?
                    }
                    struct ContainerDTO: Decodable {
                        struct ResourcesDTO: Decodable {
                            let limits: [String: String]?
                        }
                        let resources: ResourcesDTO?
                    }
                    let scaling: ScalingDTO?
                    let containers: [ContainerDTO]?
                }
                let name: String
                let uri: String?
                let latestReadyRevision: String?
                let ingress: String?
                let updateTime: String?
                let creator: String?
                let conditions: [Condition]?
                let traffic: [TrafficDTO]?
                let template: TemplateDTO?
            }
            let services: [ServiceDTO]?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.services ?? []).map { dto in
            let segments = dto.name.split(separator: "/").map(String.init)
            let shortName = segments.last ?? dto.name
            let region: String
            if let locIdx = segments.firstIndex(of: "locations"), locIdx + 1 < segments.count {
                region = segments[locIdx + 1]
            } else {
                region = "us-central1"
            }
            let ready = dto.conditions?.first(where: { $0.type == "Ready" })?.state == "CONDITION_SUCCEEDED"
            let latestRev = dto.latestReadyRevision?.split(separator: "/").last.map(String.init) ?? "latest"
            let targets = (dto.traffic ?? []).map { t in
                TrafficTarget(
                    revisionName: t.revision?.split(separator: "/").last.map(String.init) ?? latestRev,
                    percent: t.percent ?? 100,
                    latestRevision: (t.type ?? "").contains("LATEST")
                )
            }
            let limits = dto.template?.containers?.first?.resources?.limits ?? [:]
            let cpu = limits["cpu"] ?? "1000m"
            let memory = limits["memory"] ?? "512Mi"
            let minInst = dto.template?.scaling?.minInstanceCount ?? 0
            let maxInst = dto.template?.scaling?.maxInstanceCount ?? 10
            let estCost = minInst > 0 ? Double(minInst) * 28.0 : 4.20

            return CloudRunService(
                id: dto.name,
                name: shortName,
                fullName: dto.name,
                region: region,
                uri: dto.uri ?? "",
                latestReadyRevision: latestRev,
                ingress: (dto.ingress ?? "INGRESS_TRAFFIC_ALL").replacingOccurrences(of: "INGRESS_TRAFFIC_", with: ""),
                lastModified: parseISO8601(dto.updateTime),
                creator: dto.creator,
                conditionsReady: ready || dto.conditions == nil,
                traffic: targets.isEmpty ? [TrafficTarget(revisionName: latestRev, percent: 100, latestRevision: true)] : targets,
                cpu: cpu,
                memory: memory,
                minInstances: minInst,
                maxInstances: maxInst,
                requestCount24h: 0,
                estimatedMonthlyCost: estCost
            )
        }
    }

    static func decodeGCSObjects(from data: Data, bucket: String) throws -> [GCSObject] {
        struct Response: Decodable {
            struct ObjectDTO: Decodable {
                let name: String
                let size: String?
                let contentType: String?
                let updated: String?
            }
            let prefixes: [String]?
            let items: [ObjectDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        var results: [GCSObject] = []
        for prefix in decoded.prefixes ?? [] {
            results.append(GCSObject(
                name: prefix,
                bucket: bucket,
                sizeBytes: 0,
                contentType: "application/x-directory",
                updated: nil,
                isPrefix: true
            ))
        }
        for item in decoded.items ?? [] {
            if item.name.hasSuffix("/") && (Int64(item.size ?? "0") ?? 0) == 0 {
                continue
            }
            results.append(GCSObject(
                name: item.name,
                bucket: bucket,
                sizeBytes: Int64(item.size ?? "0") ?? 0,
                contentType: item.contentType ?? "application/octet-stream",
                updated: parseISO8601(item.updated),
                isPrefix: false
            ))
        }
        return results
    }

    static func decodeLogEntries(from data: Data) throws -> [LogEntry] {
        struct Response: Decodable {
            struct ResourceDTO: Decodable {
                let type: String?
                let labels: [String: String]?
            }
            struct EntryDTO: Decodable {
                let insertId: String?
                let timestamp: String?
                let severity: String?
                let logName: String?
                let resource: ResourceDTO?
                let textPayload: String?
                let jsonPayload: AnyCodableValue?
                let protoPayload: AnyCodableValue?
            }
            let entries: [EntryDTO]?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.entries ?? []).enumerated().map { idx, dto in
            let sev = LogSeverity(rawValue: (dto.severity ?? "DEFAULT").uppercased()) ?? .default
            let payload = dto.jsonPayload ?? dto.protoPayload
            let message = dto.textPayload ?? payload?.stringSummary ?? "(empty payload)"
            let ts = parseISO8601(dto.timestamp) ?? Date()
            let insertId = dto.insertId ?? "log-\(idx)-\(Int(ts.timeIntervalSince1970 * 1000))"
            return LogEntry(
                id: insertId,
                insertId: insertId,
                timestamp: ts,
                severity: sev,
                logName: dto.logName?.split(separator: "/").last.map(String.init) ?? "default",
                resourceType: dto.resource?.type ?? "global",
                resourceLabels: dto.resource?.labels ?? [:],
                message: message,
                jsonPayload: payload
            )
        }
    }

    static func decodeSecretAccessPayload(from data: Data) throws -> String {
        struct Response: Decodable {
            struct Payload: Decodable {
                let data: String?
            }
            let payload: Payload?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let b64 = decoded.payload?.data,
              let rawData = Data(base64Encoded: b64) else {
            return "(empty secret)"
        }
        return String(data: rawData, encoding: .utf8) ?? "<binary \(rawData.count) bytes>"
    }
}

actor GCPAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Core Request Helper

    func rawRequest(
        urlString: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        token: String
    ) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw GCPAPIError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 25
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GCPAPIError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GCPAPIError.networkError("Invalid HTTP response")
        }

        guard (200...299).contains(http.statusCode) else {
            struct ErrorEnvelope: Decodable {
                struct GoogleError: Decodable {
                    let code: Int?
                    let message: String?
                    let status: String?
                }
                let error: GoogleError?
            }
            if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
               let err = envelope.error {
                throw GCPAPIError.httpError(
                    code: err.code ?? http.statusCode,
                    status: err.status,
                    message: err.message ?? "Request failed"
                )
            }
            let raw = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw GCPAPIError.httpError(code: http.statusCode, status: nil, message: raw)
        }

        return data
    }

    // MARK: - Projects & Billing

    func listProjects(token: String) async throws -> [GCPProject] {
        let data = try await rawRequest(
            urlString: "https://cloudresourcemanager.googleapis.com/v3/projects:search?pageSize=50",
            token: token
        )
        return try GCPParser.decodeProjects(from: data)
    }

    func getBillingInfo(projectId: String, token: String) async throws -> BillingInfo {
        struct DTO: Decodable {
            let billingAccountName: String?
            let billingEnabled: Bool?
        }
        let data = try await rawRequest(
            urlString: "https://cloudbilling.googleapis.com/v1/projects/\(projectId)/billingInfo",
            token: token
        )
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        return BillingInfo(
            billingAccountName: dto.billingAccountName,
            billingEnabled: dto.billingEnabled ?? false
        )
    }

    // MARK: - Compute Engine

    func listComputeInstances(projectId: String, token: String) async throws -> [ComputeInstance] {
        let data = try await rawRequest(
            urlString: "https://compute.googleapis.com/compute/v1/projects/\(projectId)/aggregated/instances?maxResults=250",
            token: token
        )
        return try GCPParser.decodeComputeAggregatedInstances(from: data)
    }

    func performComputeAction(projectId: String, zone: String, instance: String, action: String, token: String) async throws {
        let url = "https://compute.googleapis.com/compute/v1/projects/\(projectId)/zones/\(zone)/instances/\(instance)/\(action)"
        _ = try await rawRequest(urlString: url, method: "POST", body: Data("{}".utf8), token: token)
    }

    // MARK: - Cloud Run v2

    func listCloudRunServices(projectId: String, token: String) async throws -> [CloudRunService] {
        let data = try await rawRequest(
            urlString: "https://run.googleapis.com/v2/projects/\(projectId)/locations/-/services?pageSize=100",
            token: token
        )
        return try GCPParser.decodeCloudRunServices(from: data)
    }

    func listCloudRunRevisions(serviceFullName: String, token: String) async throws -> [CloudRunRevision] {
        struct Response: Decodable {
            struct RevDTO: Decodable {
                struct ContainerDTO: Decodable { let image: String? }
                struct Condition: Decodable { let type: String?; let state: String? }
                let name: String
                let createTime: String?
                let containers: [ContainerDTO]?
                let conditions: [Condition]?
            }
            let revisions: [RevDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://run.googleapis.com/v2/\(serviceFullName)/revisions?pageSize=20",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.revisions ?? []).map { dto in
            let short = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
            let ready = dto.conditions?.first(where: { $0.type == "Ready" })?.state == "CONDITION_SUCCEEDED"
            return CloudRunRevision(
                id: dto.name,
                name: short,
                createTime: GCPParser.parseISO8601(dto.createTime),
                containerImage: dto.containers?.first?.image ?? "gcr.io/unknown",
                ready: ready || dto.conditions == nil
            )
        }
    }

    // MARK: - Cloud Storage

    func listBuckets(projectId: String, token: String) async throws -> [GCSBucket] {
        struct Response: Decodable {
            struct BucketDTO: Decodable {
                struct Versioning: Decodable { let enabled: Bool? }
                let name: String
                let location: String?
                let storageClass: String?
                let timeCreated: String?
                let versioning: Versioning?
            }
            let items: [BucketDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://storage.googleapis.com/storage/v1/b?project=\(projectId)&maxResults=100",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.items ?? []).map { dto in
            GCSBucket(
                name: dto.name,
                location: dto.location ?? "US",
                storageClass: dto.storageClass ?? "STANDARD",
                timeCreated: GCPParser.parseISO8601(dto.timeCreated),
                versioningEnabled: dto.versioning?.enabled ?? false,
                estimatedSizeBytes: 0,
                objectCount: 0
            )
        }
    }

    func listObjects(bucket: String, prefix: String, token: String) async throws -> [GCSObject] {
        var url = "https://storage.googleapis.com/storage/v1/b/\(bucket)/o?delimiter=/&maxResults=250"
        if !prefix.isEmpty {
            url += "&prefix=\(GCPParser.encodeGCSObjectName(prefix))"
        }
        let data = try await rawRequest(urlString: url, token: token)
        return try GCPParser.decodeGCSObjects(from: data, bucket: bucket)
    }

    func downloadObject(bucket: String, objectName: String, token: String) async throws -> Data {
        let encoded = GCPParser.encodeGCSObjectName(objectName)
        return try await rawRequest(
            urlString: "https://storage.googleapis.com/storage/v1/b/\(bucket)/o/\(encoded)?alt=media",
            token: token
        )
    }

    func uploadObject(bucket: String, objectName: String, data: Data, contentType: String, token: String) async throws {
        let encoded = GCPParser.encodeGCSObjectName(objectName)
        _ = try await rawRequest(
            urlString: "https://storage.googleapis.com/upload/storage/v1/b/\(bucket)/o?uploadType=media&name=\(encoded)",
            method: "POST",
            body: data,
            contentType: contentType,
            token: token
        )
    }

    func deleteObject(bucket: String, objectName: String, token: String) async throws {
        let encoded = GCPParser.encodeGCSObjectName(objectName)
        _ = try await rawRequest(
            urlString: "https://storage.googleapis.com/storage/v1/b/\(bucket)/o/\(encoded)",
            method: "DELETE",
            token: token
        )
    }

    // MARK: - Cloud Logging

    func listLogEntries(projectId: String, filter: String, pageSize: Int = 80, token: String) async throws -> [LogEntry] {
        struct Body: Encodable {
            let resourceNames: [String]
            let filter: String?
            let orderBy: String
            let pageSize: Int
        }
        let body = Body(
            resourceNames: ["projects/\(projectId)"],
            filter: filter.isEmpty ? nil : filter,
            orderBy: "timestamp desc",
            pageSize: pageSize
        )
        let bodyData = try JSONEncoder().encode(body)
        let data = try await rawRequest(
            urlString: "https://logging.googleapis.com/v2/entries:list",
            method: "POST",
            body: bodyData,
            token: token
        )
        return try GCPParser.decodeLogEntries(from: data)
    }

    // MARK: - IAM & Service Usage

    func getIAMPolicy(projectId: String, token: String) async throws -> [IAMBinding] {
        struct Response: Decodable {
            struct BindingDTO: Decodable {
                let role: String
                let members: [String]?
            }
            let bindings: [BindingDTO]?
        }
        let body = Data("{\"options\":{\"requestedPolicyVersion\":3}}".utf8)
        let data = try await rawRequest(
            urlString: "https://cloudresourcemanager.googleapis.com/v3/projects/\(projectId):getIamPolicy",
            method: "POST",
            body: body,
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.bindings ?? []).map { IAMBinding(role: $0.role, members: $0.members ?? []) }
    }

    func listEnabledAPIs(projectId: String, token: String) async throws -> [EnabledAPI] {
        struct Response: Decodable {
            struct ServiceDTO: Decodable {
                struct ConfigDTO: Decodable {
                    let name: String?
                    let title: String?
                    let documentation: DocDTO?
                    struct DocDTO: Decodable { let summary: String? }
                }
                let name: String?
                let state: String?
                let config: ConfigDTO?
            }
            let services: [ServiceDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://serviceusage.googleapis.com/v1/projects/\(projectId)/services?filter=state:ENABLED&pageSize=200",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.services ?? []).map { dto in
            let fullName = dto.config?.name ?? dto.name?.split(separator: "/").last.map(String.init) ?? "unknown.googleapis.com"
            return EnabledAPI(
                name: fullName,
                title: dto.config?.title ?? fullName,
                description: dto.config?.documentation?.summary ?? "Google Cloud API",
                state: dto.state ?? "ENABLED"
            )
        }.sorted { $0.title < $1.title }
    }

    func toggleAPI(projectId: String, serviceName: String, enable: Bool, token: String) async throws {
        let action = enable ? "enable" : "disable"
        _ = try await rawRequest(
            urlString: "https://serviceusage.googleapis.com/v1/projects/\(projectId)/services/\(serviceName):\(action)",
            method: "POST",
            body: Data("{}".utf8),
            token: token
        )
    }

    // MARK: - BigQuery

    func listBigQueryDatasets(projectId: String, token: String) async throws -> [BQDataset] {
        struct Response: Decodable {
            struct DatasetDTO: Decodable {
                struct Ref: Decodable { let datasetId: String }
                let datasetReference: Ref
                let location: String?
                let friendlyName: String?
            }
            let datasets: [DatasetDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://bigquery.googleapis.com/bigquery/v2/projects/\(projectId)/datasets?maxResults=100",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.datasets ?? []).map {
            BQDataset(
                datasetId: $0.datasetReference.datasetId,
                location: $0.location ?? "US",
                friendlyName: $0.friendlyName,
                creationTime: nil
            )
        }
    }

    func listBigQueryTables(projectId: String, datasetId: String, token: String) async throws -> [BQTable] {
        struct Response: Decodable {
            struct TableDTO: Decodable {
                struct Ref: Decodable { let tableId: String; let datasetId: String }
                let tableReference: Ref
                let type: String?
                let creationTime: String?
            }
            let tables: [TableDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://bigquery.googleapis.com/bigquery/v2/projects/\(projectId)/datasets/\(datasetId)/tables?maxResults=100",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.tables ?? []).map {
            BQTable(
                tableId: $0.tableReference.tableId,
                datasetId: $0.tableReference.datasetId,
                type: $0.type ?? "TABLE",
                numRows: 0,
                numBytes: 0,
                lastModified: nil
            )
        }
    }

    func runBigQuerySQL(projectId: String, sql: String, token: String) async throws -> BQQueryResult {
        struct RequestBody: Encodable {
            let query: String
            let useLegacySql: Bool
            let maxResults: Int
        }
        struct Response: Decodable {
            struct Schema: Decodable {
                struct Field: Decodable { let name: String }
                let fields: [Field]?
            }
            struct Row: Decodable {
                struct Cell: Decodable {
                    let v: AnyCodableValue?
                }
                let f: [Cell]?
            }
            let schema: Schema?
            let rows: [Row]?
            let totalBytesProcessed: String?
            let jobComplete: Bool?
        }

        let start = Date()
        let bodyData = try JSONEncoder().encode(RequestBody(query: sql, useLegacySql: false, maxResults: 200))
        let data = try await rawRequest(
            urlString: "https://bigquery.googleapis.com/bigquery/v2/projects/\(projectId)/queries",
            method: "POST",
            body: bodyData,
            token: token
        )
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        let columns = decoded.schema?.fields?.map(\.name) ?? []
        let rows: [[String]] = (decoded.rows ?? []).map { row in
            (row.f ?? []).map { cell in
                cell.v?.stringSummary ?? "NULL"
            }
        }
        return BQQueryResult(
            columns: columns,
            rows: rows,
            totalBytesProcessed: Int64(decoded.totalBytesProcessed ?? "0") ?? 0,
            durationMs: elapsed,
            jobComplete: decoded.jobComplete ?? true
        )
    }

    // MARK: - Cloud SQL

    func listCloudSQLInstances(projectId: String, token: String) async throws -> [CloudSQLInstance] {
        struct Response: Decodable {
            struct InstanceDTO: Decodable {
                struct Settings: Decodable {
                    let tier: String?
                    let dataDiskSizeGb: String?
                    let availabilityType: String?
                }
                struct IPAddress: Decodable {
                    let ipAddress: String?
                    let type: String?
                }
                let name: String
                let databaseVersion: String?
                let region: String?
                let state: String?
                let settings: Settings?
                let ipAddresses: [IPAddress]?
            }
            let items: [InstanceDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://sqladmin.googleapis.com/v1/projects/\(projectId)/instances",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.items ?? []).map { dto in
            let tier = dto.settings?.tier ?? "db-f1-micro"
            let storageGb = Int(dto.settings?.dataDiskSizeGb ?? "10") ?? 10
            let estCost = tier.contains("micro") ? 11.0 : (tier.contains("custom") ? 96.0 : 48.0)
            return CloudSQLInstance(
                name: dto.name,
                databaseVersion: dto.databaseVersion ?? "POSTGRES_16",
                region: dto.region ?? "us-central1",
                state: dto.state ?? "RUNNABLE",
                tier: tier,
                ipAddress: dto.ipAddresses?.first?.ipAddress,
                storageSizeGb: storageGb,
                availabilityType: dto.settings?.availabilityType ?? "ZONAL",
                estimatedMonthlyCost: estCost
            )
        }
    }

    func restartCloudSQLInstance(projectId: String, instance: String, token: String) async throws {
        _ = try await rawRequest(
            urlString: "https://sqladmin.googleapis.com/v1/projects/\(projectId)/instances/\(instance)/restart",
            method: "POST",
            body: Data("{}".utf8),
            token: token
        )
    }

    // MARK: - Secret Manager

    func listSecrets(projectId: String, token: String) async throws -> [SecretItem] {
        struct Response: Decodable {
            struct SecretDTO: Decodable {
                struct Replication: Decodable {
                    struct Auto: Decodable {}
                    let automatic: Auto?
                }
                let name: String
                let createTime: String?
                let replication: Replication?
                let labels: [String: String]?
            }
            let secrets: [SecretDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://secretmanager.googleapis.com/v1/projects/\(projectId)/secrets?pageSize=100",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.secrets ?? []).map { dto in
            let short = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
            let policy = dto.replication?.automatic != nil ? "Automatic" : "User-managed"
            return SecretItem(
                name: dto.name,
                shortName: short,
                createTime: GCPParser.parseISO8601(dto.createTime),
                replicationPolicy: policy,
                labels: dto.labels ?? [:]
            )
        }
    }

    func listSecretVersions(secretFullName: String, token: String) async throws -> [SecretVersion] {
        struct Response: Decodable {
            struct VersionDTO: Decodable {
                let name: String
                let state: String?
                let createTime: String?
            }
            let versions: [VersionDTO]?
        }
        let data = try await rawRequest(
            urlString: "https://secretmanager.googleapis.com/v1/\(secretFullName)/versions?pageSize=25",
            token: token
        )
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.versions ?? []).map { dto in
            let verNum = dto.name.split(separator: "/").last.map(String.init) ?? "1"
            return SecretVersion(
                name: dto.name,
                versionNumber: verNum,
                state: dto.state ?? "ENABLED",
                createTime: GCPParser.parseISO8601(dto.createTime)
            )
        }
    }

    func accessSecretVersion(versionFullName: String, token: String) async throws -> String {
        let data = try await rawRequest(
            urlString: "https://secretmanager.googleapis.com/v1/\(versionFullName):access",
            token: token
        )
        return try GCPParser.decodeSecretAccessPayload(from: data)
    }
}
