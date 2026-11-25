import Foundation

/// Pure REST JSON parsers & query builders for Firebase and Firestore, exposed internally for unit tests.
enum FirebaseParser {
    static func encodePathSegments(_ path: String) -> String {
        path
            .split(separator: "/")
            .map { seg in
                var allowed = CharacterSet.urlPathAllowed
                allowed.remove(charactersIn: "?#&=+%")
                return String(seg).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(seg)
            }
            .joined(separator: "/")
    }

    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/?#&=+%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    static func sanitizeRemoteConfigForPublish(_ rawJSON: String) throws -> Data {
        guard let obj = try JSONSerialization.jsonObject(with: Data(rawJSON.utf8)) as? [String: Any] else {
            throw GCPAPIError.decodingError("Remote Config template must be a JSON object")
        }
        var cleaned = obj
        if let ver = cleaned["version"] as? [String: Any] {
            if let desc = ver["description"] as? String, !desc.isEmpty {
                cleaned["version"] = ["description": desc]
            } else {
                cleaned.removeValue(forKey: "version")
            }
        }
        return try JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys])
    }

    static func filterAndSortDocuments(
        _ docs: [FirestoreDocument],
        filterField: String?,
        op: FirestoreQueryOperator,
        filterValueRaw: String?,
        orderByField: String?,
        descending: Bool,
        limit: Int
    ) -> [FirestoreDocument] {
        var results = docs
        let cleanField = filterField?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanValue = filterValueRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanField.isEmpty && !cleanValue.isEmpty {
            let target = inferTypedValue(from: cleanValue)
            results = results.filter { doc in
                guard let fieldVal = doc.fields[cleanField] else { return false }
                switch op {
                case .equal:
                    return fieldVal == target || fieldVal.displayString.caseInsensitiveCompare(cleanValue) == .orderedSame
                case .notEqual:
                    return fieldVal != target && fieldVal.displayString.caseInsensitiveCompare(cleanValue) != .orderedSame
                case .lessThan:
                    return compareFirestoreValues(fieldVal, target) == .orderedAscending
                case .lessThanOrEqual:
                    let cmp = compareFirestoreValues(fieldVal, target)
                    return cmp == .orderedAscending || cmp == .orderedSame
                case .greaterThan:
                    return compareFirestoreValues(fieldVal, target) == .orderedDescending
                case .greaterThanOrEqual:
                    let cmp = compareFirestoreValues(fieldVal, target)
                    return cmp == .orderedDescending || cmp == .orderedSame
                case .arrayContains:
                    if case .array(let arr) = fieldVal {
                        return arr.contains { $0 == target || $0.displayString.caseInsensitiveCompare(cleanValue) == .orderedSame }
                    }
                    return fieldVal.displayString.localizedCaseInsensitiveContains(cleanValue)
                }
            }
        }

        if let order = orderByField?.trimmingCharacters(in: .whitespacesAndNewlines), !order.isEmpty {
            results.sort { lhs, rhs in
                let lVal = lhs.fields[order] ?? .null
                let rVal = rhs.fields[order] ?? .null
                let cmp = compareFirestoreValues(lVal, rVal)
                if cmp == .orderedSame {
                    return descending ? lhs.documentId > rhs.documentId : lhs.documentId < rhs.documentId
                }
                return descending ? cmp == .orderedDescending : cmp == .orderedAscending
            }
        }

        return Array(results.prefix(max(1, min(limit, 500))))
    }

    private static func compareFirestoreValues(_ lhs: FirestoreValue, _ rhs: FirestoreValue) -> ComparisonResult {
        if let lNum = numericValue(lhs), let rNum = numericValue(rhs) {
            if lNum < rNum { return .orderedAscending }
            if lNum > rNum { return .orderedDescending }
            return .orderedSame
        }
        if case .boolean(let lBool) = lhs, case .boolean(let rBool) = rhs {
            if lBool == rBool { return .orderedSame }
            return !lBool && rBool ? .orderedAscending : .orderedDescending
        }
        return lhs.displayString.localizedCaseInsensitiveCompare(rhs.displayString)
    }

    private static func numericValue(_ value: FirestoreValue) -> Double? {
        switch value {
        case .integer(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    static func decodeFirestoreDocument(from data: Data) throws -> FirestoreDocument {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GCPAPIError.decodingError("Invalid Firestore document JSON")
        }
        return parseDocumentDict(obj)
    }

    static func decodeFirestoreDocumentsList(from data: Data) throws -> (documents: [FirestoreDocument], nextPageToken: String?) {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GCPAPIError.decodingError("Invalid Firestore documents list JSON")
        }
        let rawDocs = obj["documents"] as? [[String: Any]] ?? []
        let docs = rawDocs.map { parseDocumentDict($0) }
        let nextToken = obj["nextPageToken"] as? String
        return (docs, nextToken)
    }

    static func decodeFirestoreRunQuery(from data: Data) throws -> [FirestoreDocument] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw GCPAPIError.decodingError("Invalid Firestore runQuery response JSON")
        }
        return rows.compactMap { row in
            guard let docDict = row["document"] as? [String: Any] else { return nil }
            return parseDocumentDict(docDict)
        }
    }

    static func parseDocumentDict(_ dict: [String: Any]) -> FirestoreDocument {
        let fullName = dict["name"] as? String ?? ""
        let relativePath: String
        if let range = fullName.range(of: "/documents/") {
            relativePath = String(fullName[range.upperBound...])
        } else {
            relativePath = fullName
        }
        let docId = relativePath.split(separator: "/").last.map(String.init) ?? fullName
        let rawFields = dict["fields"] as? [String: Any] ?? [:]
        let fields = FirestoreValue.decodeFieldsREST(rawFields)
        let createTime = GCPParser.parseISO8601(dict["createTime"] as? String)
        let updateTime = GCPParser.parseISO8601(dict["updateTime"] as? String)
        return FirestoreDocument(
            name: fullName,
            documentId: docId,
            relativePath: relativePath,
            fields: fields,
            createTime: createTime,
            updateTime: updateTime
        )
    }

    static func buildStructuredQueryBody(
        collectionId: String,
        filterField: String? = nil,
        op: FirestoreQueryOperator = .equal,
        filterValueRaw: String? = nil,
        orderByField: String? = nil,
        descending: Bool = false,
        limit: Int = 50
    ) throws -> Data {
        var structuredQuery: [String: Any] = [
            "from": [["collectionId": collectionId]],
            "limit": max(1, min(limit, 500))
        ]

        let cleanField = filterField?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanValue = filterValueRaw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cleanField.isEmpty && !cleanValue.isEmpty {
            let typedValue = inferTypedValue(from: cleanValue)
            structuredQuery["where"] = [
                "fieldFilter": [
                    "field": ["fieldPath": cleanField],
                    "op": op.rawValue,
                    "value": typedValue.toRESTJSON()
                ]
            ]
        }

        if let orderField = orderByField?.trimmingCharacters(in: .whitespacesAndNewlines), !orderField.isEmpty {
            structuredQuery["orderBy"] = [
                [
                    "field": ["fieldPath": orderField],
                    "direction": descending ? "DESCENDING" : "ASCENDING"
                ]
            ]
        }

        let payload: [String: Any] = ["structuredQuery": structuredQuery]
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    static func inferTypedValue(from raw: String) -> FirestoreValue {
        let lower = raw.lowercased()
        if lower == "true" { return .boolean(true) }
        if lower == "false" { return .boolean(false) }
        if lower == "null" { return .null }
        if let intVal = Int64(raw), !raw.contains(".") {
            return .integer(intVal)
        }
        if raw.contains("."), let dblVal = Double(raw) {
            return .double(dblVal)
        }
        if (raw.hasPrefix("\"") && raw.hasSuffix("\"")) && raw.count >= 2 {
            return .string(String(raw.dropFirst().dropLast()))
        }
        return .string(raw)
    }

    static func decodeFirestoreIndexes(from data: Data) throws -> [FirestoreIndex] {
        struct Response: Decodable {
            struct IndexDTO: Decodable {
                struct FieldDTO: Decodable {
                    let fieldPath: String?
                    let order: String?
                    let arrayConfig: String?
                }
                let name: String
                let queryScope: String?
                let state: String?
                let fields: [FieldDTO]?
            }
            let indexes: [IndexDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.indexes ?? []).map { dto in
            let parts = dto.name.split(separator: "/").map(String.init)
            let group: String
            if let idx = parts.firstIndex(of: "collectionGroups"), idx + 1 < parts.count {
                group = parts[idx + 1]
            } else {
                group = "-"
            }
            let fields = (dto.fields ?? []).map { f in
                FirestoreIndexField(
                    fieldPath: f.fieldPath ?? "",
                    orderOrMode: f.order ?? f.arrayConfig ?? "ASCENDING"
                )
            }
            return FirestoreIndex(
                name: dto.name,
                collectionGroup: group,
                queryScope: dto.queryScope ?? "COLLECTION",
                state: dto.state ?? "READY",
                fields: fields
            )
        }
    }

    static func decodeFirebaseProject(from data: Data) throws -> FirebaseProjectInfo {
        struct DTO: Decodable {
            struct ResourcesDTO: Decodable {
                let hostingSite: String?
                let realtimeDatabaseInstance: String?
                let storageBucket: String?
                let locationId: String?
            }
            let projectId: String
            let projectNumber: String?
            let displayName: String?
            let state: String?
            let resources: ResourcesDTO?
        }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        return FirebaseProjectInfo(
            projectId: dto.projectId,
            projectNumber: dto.projectNumber ?? "",
            displayName: dto.displayName ?? dto.projectId,
            state: dto.state ?? "ACTIVE",
            defaultHostingSite: dto.resources?.hostingSite,
            defaultRealtimeDatabaseInstance: dto.resources?.realtimeDatabaseInstance,
            defaultStorageBucket: dto.resources?.storageBucket,
            locationId: dto.resources?.locationId
        )
    }

    static func decodeFirebaseApps(from data: Data, platform: FirebaseAppPlatform) throws -> [FirebaseAppItem] {
        struct Response: Decodable {
            struct AppDTO: Decodable {
                let appId: String
                let displayName: String?
                let bundleId: String?
                let packageName: String?
                let state: String?
                let apiKeyId: String?
            }
            let apps: [AppDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.apps ?? []).map { dto in
            FirebaseAppItem(
                appId: dto.appId,
                displayName: dto.displayName ?? dto.bundleId ?? dto.packageName ?? dto.appId,
                platform: platform,
                bundleOrPackageId: dto.bundleId ?? dto.packageName,
                state: dto.state ?? "ACTIVE",
                apiKeyId: dto.apiKeyId
            )
        }
    }

    static func decodeFirebaseAppConfig(from data: Data, app: FirebaseAppItem) throws -> FirebaseAppConfig {
        if app.platform == .web {
            if let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let text = String(data: pretty, encoding: .utf8) {
                return FirebaseAppConfig(appId: app.appId, platform: .web, filename: "firebase-config.json", rawContent: text)
            }
            return FirebaseAppConfig(appId: app.appId, platform: .web, filename: "firebase-config.json", rawContent: String(data: data, encoding: .utf8) ?? "{}")
        }
        struct MobileConfigDTO: Decodable {
            let configFilename: String?
            let configFileContents: String?
        }
        let dto = try JSONDecoder().decode(MobileConfigDTO.self, from: data)
        let defaultFilename = app.platform == .ios ? "GoogleService-Info.plist" : "google-services.json"
        let decodedText: String
        if let b64 = dto.configFileContents, let raw = Data(base64Encoded: b64) {
            decodedText = String(data: raw, encoding: .utf8) ?? "<binary \(raw.count) bytes>"
        } else {
            decodedText = String(data: data, encoding: .utf8) ?? ""
        }
        return FirebaseAppConfig(
            appId: app.appId,
            platform: app.platform,
            filename: dto.configFilename ?? defaultFilename,
            rawContent: decodedText
        )
    }

    static func decodeAuthUsers(from data: Data) throws -> [FirebaseAuthUser] {
        struct Response: Decodable {
            struct UserDTO: Decodable {
                struct ProviderDTO: Decodable {
                    let providerId: String?
                }
                let localId: String
                let email: String?
                let displayName: String?
                let phoneNumber: String?
                let emailVerified: Bool?
                let disabled: Bool?
                let createdAt: String?
                let lastLoginAt: String?
                let providerUserInfo: [ProviderDTO]?
            }
            let users: [UserDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.users ?? []).map { dto in
            let providers = (dto.providerUserInfo ?? []).compactMap(\.providerId)
            return FirebaseAuthUser(
                localId: dto.localId,
                email: dto.email,
                displayName: dto.displayName,
                phoneNumber: dto.phoneNumber,
                emailVerified: dto.emailVerified ?? false,
                disabled: dto.disabled ?? false,
                providers: providers.isEmpty ? ["password"] : providers,
                createdAt: parseEpochMillis(dto.createdAt),
                lastLoginAt: parseEpochMillis(dto.lastLoginAt)
            )
        }
    }

    static func parseEpochMillis(_ raw: String?) -> Date? {
        guard let raw, let ms = Double(raw) else { return nil }
        return Date(timeIntervalSince1970: ms / 1000.0)
    }

    static func decodeHostingSites(from data: Data) throws -> [FirebaseHostingSite] {
        struct Response: Decodable {
            struct SiteDTO: Decodable {
                let name: String
                let defaultUrl: String?
                let type: String?
            }
            let sites: [SiteDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.sites ?? []).map { dto in
            let siteId = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
            return FirebaseHostingSite(
                name: dto.name,
                siteId: siteId,
                defaultUrl: dto.defaultUrl ?? "https://\(siteId).web.app",
                type: dto.type ?? "USER_SITE"
            )
        }
    }

    static func decodeHostingReleases(from data: Data) throws -> [FirebaseHostingRelease] {
        struct Response: Decodable {
            struct ReleaseDTO: Decodable {
                struct VersionDTO: Decodable {
                    let name: String?
                    let status: String?
                }
                struct UserDTO: Decodable {
                    let email: String?
                }
                let name: String
                let type: String?
                let message: String?
                let releaseTime: String?
                let releaseUser: UserDTO?
                let version: VersionDTO?
            }
            let releases: [ReleaseDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.releases ?? []).map { dto in
            let versionId = dto.version?.name?.split(separator: "/").last.map(String.init)
                ?? dto.name.split(separator: "/").last.map(String.init)
                ?? "release"
            return FirebaseHostingRelease(
                name: dto.name,
                versionId: versionId,
                status: dto.version?.status ?? dto.type ?? "DEPLOYED",
                message: dto.message ?? "Hosting release",
                releaseTime: GCPParser.parseISO8601(dto.releaseTime),
                releaseUserEmail: dto.releaseUser?.email
            )
        }
    }

    static func decodeHostingChannels(from data: Data) throws -> [FirebaseHostingChannel] {
        struct Response: Decodable {
            struct ChannelDTO: Decodable {
                let name: String
                let url: String?
                let expireTime: String?
                let retainedReleaseCount: Int?
            }
            let channels: [ChannelDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.channels ?? []).map { dto in
            let channelId = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
            return FirebaseHostingChannel(
                name: dto.name,
                channelId: channelId,
                url: dto.url ?? "",
                expireTime: GCPParser.parseISO8601(dto.expireTime),
                retainedReleaseCount: dto.retainedReleaseCount
            )
        }
    }

    static func decodeRulesReleases(from data: Data) throws -> [FirebaseRulesRelease] {
        struct Response: Decodable {
            struct ReleaseDTO: Decodable {
                let name: String
                let rulesetName: String?
                let createTime: String?
                let updateTime: String?
            }
            let releases: [ReleaseDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.releases ?? []).map { dto in
            let short = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
            return FirebaseRulesRelease(
                name: dto.name,
                shortName: short,
                rulesetName: dto.rulesetName ?? "",
                createTime: GCPParser.parseISO8601(dto.createTime),
                updateTime: GCPParser.parseISO8601(dto.updateTime)
            )
        }
    }

    static func decodeRuleset(from data: Data) throws -> FirebaseRuleset {
        struct RulesetDTO: Decodable {
            struct SourceDTO: Decodable {
                struct FileDTO: Decodable {
                    let name: String?
                    let content: String?
                }
                let files: [FileDTO]?
            }
            let name: String
            let createTime: String?
            let source: SourceDTO?
        }
        let dto = try JSONDecoder().decode(RulesetDTO.self, from: data)
        let shortId = dto.name.split(separator: "/").last.map(String.init) ?? dto.name
        let files = (dto.source?.files ?? []).map {
            FirebaseRuleFile(name: $0.name ?? "rules", content: $0.content ?? "")
        }
        return FirebaseRuleset(
            name: dto.name,
            shortId: shortId,
            createTime: GCPParser.parseISO8601(dto.createTime),
            files: files
        )
    }

    static func decodeRemoteConfig(from data: Data, etag: String) throws -> FirebaseRemoteConfigTemplate {
        struct DTO: Decodable {
            struct VersionDTO: Decodable {
                struct UserDTO: Decodable { let email: String? }
                let versionNumber: String?
                let updateTime: String?
                let updateUser: UserDTO?
            }
            struct ParamDTO: Decodable {
                struct DefaultValDTO: Decodable {
                    let value: String?
                    let useInAppDefault: Bool?
                }
                let defaultValue: DefaultValDTO?
                let valueType: String?
                let description: String?
            }
            let version: VersionDTO?
            let parameters: [String: ParamDTO]?
        }
        let decoded = try JSONDecoder().decode(DTO.self, from: data)
        let params = (decoded.parameters ?? [:]).keys.sorted().compactMap { key -> FirebaseRemoteConfigParam? in
            guard let p = decoded.parameters?[key] else { return nil }
            let val = p.defaultValue?.value ?? (p.defaultValue?.useInAppDefault == true ? "<in-app default>" : "")
            return FirebaseRemoteConfigParam(
                key: key,
                defaultValue: val,
                valueType: p.valueType ?? "STRING",
                description: p.description ?? ""
            )
        }
        let prettyJSON: String
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: prettyData, encoding: .utf8) {
            prettyJSON = str
        } else {
            prettyJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
        return FirebaseRemoteConfigTemplate(
            etag: etag,
            versionNumber: decoded.version?.versionNumber ?? "1",
            updateTime: GCPParser.parseISO8601(decoded.version?.updateTime),
            updateUserEmail: decoded.version?.updateUser?.email,
            parameters: params,
            rawJSON: prettyJSON
        )
    }

    static func decodeRemoteConfigVersions(from data: Data) throws -> [FirebaseRemoteConfigVersion] {
        struct Response: Decodable {
            struct VersionDTO: Decodable {
                struct UserDTO: Decodable { let email: String? }
                let versionNumber: String?
                let updateTime: String?
                let updateUser: UserDTO?
                let description: String?
                let rollbackSource: String?
            }
            let versions: [VersionDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.versions ?? []).map { dto in
            FirebaseRemoteConfigVersion(
                versionNumber: dto.versionNumber ?? "0",
                updateTime: GCPParser.parseISO8601(dto.updateTime),
                updateUserEmail: dto.updateUser?.email,
                description: dto.description,
                isRollback: dto.rollbackSource != nil
            )
        }
    }

    static func decodeRealtimeDBInstances(from data: Data) throws -> [RealtimeDBInstance] {
        struct Response: Decodable {
            struct InstanceDTO: Decodable {
                let name: String
                let databaseUrl: String?
                let type: String?
                let state: String?
            }
            let instances: [InstanceDTO]?
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.instances ?? []).map { dto in
            let parts = dto.name.split(separator: "/").map(String.init)
            let instanceId = parts.last ?? dto.name
            let region: String
            if let idx = parts.firstIndex(of: "locations"), idx + 1 < parts.count {
                region = parts[idx + 1]
            } else {
                region = "us-central1"
            }
            return RealtimeDBInstance(
                name: dto.name,
                instanceId: instanceId,
                databaseUrl: dto.databaseUrl ?? "https://\(instanceId).firebaseio.com",
                region: region,
                type: dto.type ?? "DEFAULT_DATABASE",
                state: dto.state ?? "ACTIVE"
            )
        }
    }
}

// MARK: - GCPAPIClient Firestore CRUD, Queries, Indexes & Firebase REST Endpoints

extension GCPAPIClient {
    // MARK: Firestore Browser & CRUD

    func listFirestoreSubcollections(
        projectId: String,
        databaseId: String = "(default)",
        parentDocumentPath: String = "",
        token: String
    ) async throws -> [String] {
        struct Response: Decodable { let collectionIds: [String]? }
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let cleanParent = parentDocumentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/documents"
        let urlString = cleanParent.isEmpty
            ? "\(base):listCollectionIds"
            : "\(base)/\(FirebaseParser.encodePathSegments(cleanParent)):listCollectionIds"
        let data = try await rawRequest(
            urlString: urlString,
            method: "POST",
            body: Data("{\"pageSize\":100}".utf8),
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try JSONDecoder().decode(Response.self, from: data).collectionIds ?? []
    }

    func listFirestoreDocuments(
        projectId: String,
        databaseId: String = "(default)",
        collectionPath: String,
        pageSize: Int = 50,
        pageToken: String? = nil,
        token: String
    ) async throws -> (documents: [FirestoreDocument], nextPageToken: String?) {
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let cleanCol = collectionPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/documents/\(FirebaseParser.encodePathSegments(cleanCol))?pageSize=\(max(1, min(pageSize, 300)))"
        if let pageToken, !pageToken.isEmpty {
            url += "&pageToken=\(FirebaseParser.encodeQueryValue(pageToken))"
        }
        let data = try await rawRequest(
            urlString: url,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirestoreDocumentsList(from: data)
    }

    func getFirestoreDocument(
        projectId: String,
        databaseId: String = "(default)",
        documentPath: String,
        token: String
    ) async throws -> FirestoreDocument {
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let cleanDoc = documentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/documents/\(FirebaseParser.encodePathSegments(cleanDoc))"
        let data = try await rawRequest(
            urlString: url,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirestoreDocument(from: data)
    }

    func createFirestoreDocument(
        projectId: String,
        databaseId: String = "(default)",
        collectionPath: String,
        documentId: String? = nil,
        fields: [String: FirestoreValue],
        token: String
    ) async throws -> FirestoreDocument {
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let cleanCol = collectionPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/documents/\(FirebaseParser.encodePathSegments(cleanCol))"
        if let docId = documentId?.trimmingCharacters(in: .whitespacesAndNewlines), !docId.isEmpty {
            url += "?documentId=\(FirebaseParser.encodeQueryValue(docId))"
        }
        let bodyObj: [String: Any] = ["fields": FirestoreValue.encodeFieldsREST(fields)]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyObj)
        let data = try await rawRequest(
            urlString: url,
            method: "POST",
            body: bodyData,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirestoreDocument(from: data)
    }

    func updateFirestoreDocument(
        projectId: String,
        databaseId: String = "(default)",
        documentPath: String,
        fields: [String: FirestoreValue],
        merge: Bool = false,
        token: String
    ) async throws -> FirestoreDocument {
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let cleanDoc = documentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/documents/\(FirebaseParser.encodePathSegments(cleanDoc))"
        if merge && !fields.isEmpty {
            let maskParams = fields.keys.sorted().map { key in
                "updateMask.fieldPaths=\(FirebaseParser.encodeQueryValue(key))"
            }.joined(separator: "&")
            url += "?\(maskParams)"
        }
        let bodyObj: [String: Any] = ["fields": FirestoreValue.encodeFieldsREST(fields)]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyObj)
        let data = try await rawRequest(
            urlString: url,
            method: "PATCH",
            body: bodyData,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirestoreDocument(from: data)
    }

    func deleteFirestoreDocument(
        projectId: String,
        databaseId: String = "(default)",
        documentPath: String,
        token: String
    ) async throws {
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let cleanDoc = documentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/documents/\(FirebaseParser.encodePathSegments(cleanDoc))"
        _ = try await rawRequest(
            urlString: url,
            method: "DELETE",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
    }

    func runFirestoreQuery(
        projectId: String,
        databaseId: String = "(default)",
        parentPath: String = "",
        collectionId: String,
        filterField: String? = nil,
        op: FirestoreQueryOperator = .equal,
        filterValueRaw: String? = nil,
        orderByField: String? = nil,
        descending: Bool = false,
        limit: Int = 50,
        token: String
    ) async throws -> [FirestoreDocument] {
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let cleanParent = parentPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/documents"
        let urlString = cleanParent.isEmpty
            ? "\(base):runQuery"
            : "\(base)/\(FirebaseParser.encodePathSegments(cleanParent)):runQuery"
        let bodyData = try FirebaseParser.buildStructuredQueryBody(
            collectionId: collectionId,
            filterField: filterField,
            op: op,
            filterValueRaw: filterValueRaw,
            orderByField: orderByField,
            descending: descending,
            limit: limit
        )
        let data = try await rawRequest(
            urlString: urlString,
            method: "POST",
            body: bodyData,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirestoreRunQuery(from: data)
    }

    func listFirestoreIndexes(
        projectId: String,
        databaseId: String = "(default)",
        token: String
    ) async throws -> [FirestoreIndex] {
        let db = databaseId.isEmpty ? "(default)" : databaseId
        let url = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/\(db)/collectionGroups/-/indexes?pageSize=100"
        let data = try await rawRequest(
            urlString: url,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirestoreIndexes(from: data)
    }

    // MARK: Firebase Management (Project, Apps, Configs)

    func getFirebaseProject(projectId: String, token: String) async throws -> FirebaseProjectInfo {
        let data = try await rawRequest(
            urlString: "https://firebase.googleapis.com/v1beta1/projects/\(projectId)",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirebaseProject(from: data)
    }

    func listFirebaseApps(projectId: String, token: String) async throws -> [FirebaseAppItem] {
        let headers = ["x-goog-user-project": projectId]
        async let webData = try? rawRequest(urlString: "https://firebase.googleapis.com/v1beta1/projects/\(projectId)/webApps?pageSize=100", extraHeaders: headers, token: token)
        async let iosData = try? rawRequest(urlString: "https://firebase.googleapis.com/v1beta1/projects/\(projectId)/iosApps?pageSize=100", extraHeaders: headers, token: token)
        async let androidData = try? rawRequest(urlString: "https://firebase.googleapis.com/v1beta1/projects/\(projectId)/androidApps?pageSize=100", extraHeaders: headers, token: token)

        var apps: [FirebaseAppItem] = []
        if let d = await webData, let parsed = try? FirebaseParser.decodeFirebaseApps(from: d, platform: .web) {
            apps.append(contentsOf: parsed)
        }
        if let d = await iosData, let parsed = try? FirebaseParser.decodeFirebaseApps(from: d, platform: .ios) {
            apps.append(contentsOf: parsed)
        }
        if let d = await androidData, let parsed = try? FirebaseParser.decodeFirebaseApps(from: d, platform: .android) {
            apps.append(contentsOf: parsed)
        }
        return apps.sorted { $0.displayName < $1.displayName }
    }

    func getFirebaseAppConfig(projectId: String, app: FirebaseAppItem, token: String) async throws -> FirebaseAppConfig {
        let segment: String
        switch app.platform {
        case .web: segment = "webApps"
        case .ios: segment = "iosApps"
        case .android: segment = "androidApps"
        }
        let data = try await rawRequest(
            urlString: "https://firebase.googleapis.com/v1beta1/projects/\(projectId)/\(segment)/\(app.appId)/config",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeFirebaseAppConfig(from: data, app: app)
    }

    // MARK: Firebase Authentication (Identity Toolkit v1)

    func listFirebaseAuthUsers(projectId: String, maxResults: Int = 100, token: String) async throws -> [FirebaseAuthUser] {
        let data = try await rawRequest(
            urlString: "https://identitytoolkit.googleapis.com/v1/projects/\(projectId)/accounts:batchGet?maxResults=\(max(1, min(maxResults, 500)))",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeAuthUsers(from: data)
    }

    func createFirebaseAuthUser(
        projectId: String,
        email: String,
        password: String,
        displayName: String? = nil,
        token: String
    ) async throws -> FirebaseAuthUser {
        struct Body: Encodable {
            let email: String
            let password: String
            let displayName: String?
            let emailVerified: Bool
        }
        struct Response: Decodable {
            let localId: String
            let email: String?
            let displayName: String?
        }
        let cleanName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bodyData = try JSONEncoder().encode(Body(
            email: email,
            password: password,
            displayName: (cleanName?.isEmpty == false) ? cleanName : nil,
            emailVerified: false
        ))
        let data = try await rawRequest(
            urlString: "https://identitytoolkit.googleapis.com/v1/projects/\(projectId)/accounts",
            method: "POST",
            body: bodyData,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        let dto = try JSONDecoder().decode(Response.self, from: data)
        return FirebaseAuthUser(
            localId: dto.localId,
            email: dto.email ?? email,
            displayName: dto.displayName ?? cleanName,
            phoneNumber: nil,
            emailVerified: false,
            disabled: false,
            providers: ["password"],
            createdAt: Date(),
            lastLoginAt: nil
        )
    }

    func setFirebaseAuthUserDisabled(projectId: String, localId: String, disabled: Bool, token: String) async throws {
        struct Body: Encodable {
            let localId: String
            let disableUser: Bool
        }
        let bodyData = try JSONEncoder().encode(Body(localId: localId, disableUser: disabled))
        _ = try await rawRequest(
            urlString: "https://identitytoolkit.googleapis.com/v1/projects/\(projectId)/accounts:update",
            method: "POST",
            body: bodyData,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
    }

    func deleteFirebaseAuthUser(projectId: String, localId: String, token: String) async throws {
        struct Body: Encodable { let localId: String }
        let bodyData = try JSONEncoder().encode(Body(localId: localId))
        _ = try await rawRequest(
            urlString: "https://identitytoolkit.googleapis.com/v1/projects/\(projectId)/accounts:delete",
            method: "POST",
            body: bodyData,
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
    }

    // MARK: Firebase Hosting

    func listFirebaseHostingSites(projectId: String, token: String) async throws -> [FirebaseHostingSite] {
        let data = try await rawRequest(
            urlString: "https://firebasehosting.googleapis.com/v1beta1/projects/\(projectId)/sites",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeHostingSites(from: data)
    }

    func listFirebaseHostingReleases(projectId: String, siteId: String, token: String) async throws -> [FirebaseHostingRelease] {
        let data = try await rawRequest(
            urlString: "https://firebasehosting.googleapis.com/v1beta1/projects/\(projectId)/sites/\(siteId)/releases?pageSize=20",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeHostingReleases(from: data)
    }

    func listFirebaseHostingChannels(projectId: String, siteId: String, token: String) async throws -> [FirebaseHostingChannel] {
        let data = try await rawRequest(
            urlString: "https://firebasehosting.googleapis.com/v1beta1/projects/\(projectId)/sites/\(siteId)/channels?pageSize=20",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeHostingChannels(from: data)
    }

    // MARK: Firebase Security Rules

    func listFirebaseRulesReleases(projectId: String, token: String) async throws -> [FirebaseRulesRelease] {
        let data = try await rawRequest(
            urlString: "https://firebaserules.googleapis.com/v1/projects/\(projectId)/releases?pageSize=25",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeRulesReleases(from: data)
    }

    func getFirebaseRuleset(rulesetName: String, token: String) async throws -> FirebaseRuleset {
        let clean = rulesetName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = clean.split(separator: "/").map(String.init)
        let extraHeaders: [String: String]
        if let idx = parts.firstIndex(of: "projects"), idx + 1 < parts.count {
            extraHeaders = ["x-goog-user-project": parts[idx + 1]]
        } else {
            extraHeaders = [:]
        }
        let data = try await rawRequest(
            urlString: "https://firebaserules.googleapis.com/v1/\(clean)",
            extraHeaders: extraHeaders,
            token: token
        )
        return try FirebaseParser.decodeRuleset(from: data)
    }

    // MARK: Firebase Remote Config

    func getFirebaseRemoteConfig(projectId: String, token: String) async throws -> FirebaseRemoteConfigTemplate {
        let (data, http) = try await rawRequestWithHeaders(
            urlString: "https://firebaseremoteconfig.googleapis.com/v1/projects/\(projectId)/remoteConfig",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        let etag = http.value(forHTTPHeaderField: "ETag") ?? "*"
        return try FirebaseParser.decodeRemoteConfig(from: data, etag: etag)
    }

    func publishFirebaseRemoteConfig(
        projectId: String,
        rawJSON: String,
        etag: String,
        token: String
    ) async throws -> FirebaseRemoteConfigTemplate {
        let sanitizedBody = try FirebaseParser.sanitizeRemoteConfigForPublish(rawJSON)
        let (data, http) = try await rawRequestWithHeaders(
            urlString: "https://firebaseremoteconfig.googleapis.com/v1/projects/\(projectId)/remoteConfig",
            method: "PUT",
            body: sanitizedBody,
            extraHeaders: [
                "If-Match": etag.isEmpty ? "*" : etag,
                "x-goog-user-project": projectId
            ],
            token: token
        )
        let nextEtag = http.value(forHTTPHeaderField: "ETag") ?? etag
        return try FirebaseParser.decodeRemoteConfig(from: data, etag: nextEtag)
    }

    func listFirebaseRemoteConfigVersions(projectId: String, token: String) async throws -> [FirebaseRemoteConfigVersion] {
        let data = try await rawRequest(
            urlString: "https://firebaseremoteconfig.googleapis.com/v1/projects/\(projectId)/remoteConfig:listVersions?pageSize=20",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeRemoteConfigVersions(from: data)
    }

    // MARK: Firebase Realtime Database

    func listRealtimeDBInstances(projectId: String, token: String) async throws -> [RealtimeDBInstance] {
        let data = try await rawRequest(
            urlString: "https://firebasedatabase.googleapis.com/v1beta/projects/\(projectId)/locations/-/instances",
            extraHeaders: ["x-goog-user-project": projectId],
            token: token
        )
        return try FirebaseParser.decodeRealtimeDBInstances(from: data)
    }

    func readRealtimeDBNode(databaseUrl: String, path: String = "", shallow: Bool = false, token: String) async throws -> String {
        let base = databaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedPath = cleanPath.isEmpty ? "" : "/\(FirebaseParser.encodePathSegments(cleanPath))"
        let url = "\(base)\(encodedPath).json\(shallow ? "?shallow=true" : "")"
        let data = try await rawRequest(urlString: url, token: token)
        if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           JSONSerialization.isValidJSONObject(obj),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }
        return String(data: data, encoding: .utf8) ?? "null"
    }

    func writeRealtimeDBNode(databaseUrl: String, path: String = "", rawJSON: String, token: String) async throws -> String {
        let base = databaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedPath = cleanPath.isEmpty ? "" : "/\(FirebaseParser.encodePathSegments(cleanPath))"
        let url = "\(base)\(encodedPath).json"
        let data = try await rawRequest(
            urlString: url,
            method: "PUT",
            body: Data(rawJSON.utf8),
            token: token
        )
        return String(data: data, encoding: .utf8) ?? rawJSON
    }

    func deleteRealtimeDBNode(databaseUrl: String, path: String, token: String) async throws {
        let base = databaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedPath = cleanPath.isEmpty ? "" : "/\(FirebaseParser.encodePathSegments(cleanPath))"
        let url = "\(base)\(encodedPath).json"
        _ = try await rawRequest(urlString: url, method: "DELETE", token: token)
    }
}
