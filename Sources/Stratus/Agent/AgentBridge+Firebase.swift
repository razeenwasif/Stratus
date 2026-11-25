import Foundation

extension AgentBridge {
    private func resolveFirebasePid(_ explicit: String?) async throws -> String {
        if let explicit, !explicit.isEmpty { return explicit }
        if let acct = auth.account.projectId, !acct.isEmpty { return acct }
        if auth.isDemo { return DemoDataProvider.projects.first?.projectId ?? "prod-platform-core" }
        let token = try await auth.validAccessToken()
        if let first = try await api.listProjects(token: token).first?.projectId { return first }
        throw AgentBridgeError.missingArgument("projectId")
    }

    // MARK: - Firebase Agent Bridge

    func firebase(
        projectId: String?,
        action: String,
        appId: String? = nil,
        email: String? = nil,
        password: String? = nil,
        displayName: String? = nil,
        localId: String? = nil,
        siteId: String? = nil,
        rulesetName: String? = nil,
        rawJSON: String? = nil,
        etag: String? = nil,
        databaseUrl: String? = nil,
        path: String? = nil,
        shallow: Bool = false,
        demo: Bool = false
    ) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveFirebasePid(projectId)
        let iso = ISO8601DateFormatter()

        switch action {
        case "project":
            let info: FirebaseProjectInfo
            if auth.isDemo {
                info = DemoDataProvider.firebaseProject(for: pid)
            } else {
                let token = try await auth.validAccessToken()
                info = try await api.getFirebaseProject(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(info.projectId),
                "projectNumber": .string(info.projectNumber),
                "displayName": .string(info.displayName),
                "state": .string(info.state),
                "defaultHostingSite": info.defaultHostingSite.map(AnyCodableValue.string) ?? .null,
                "defaultRealtimeDatabaseInstance": info.defaultRealtimeDatabaseInstance.map(AnyCodableValue.string) ?? .null,
                "defaultStorageBucket": info.defaultStorageBucket.map(AnyCodableValue.string) ?? .null,
                "locationId": info.locationId.map(AnyCodableValue.string) ?? .null
            ])

        case "apps":
            let apps: [FirebaseAppItem]
            if auth.isDemo {
                apps = DemoDataProvider.firebaseApps(for: pid)
            } else {
                let token = try await auth.validAccessToken()
                apps = try await api.listFirebaseApps(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "count": .int(apps.count),
                "apps": .array(apps.map { a in
                    .object([
                        "appId": .string(a.appId),
                        "displayName": .string(a.displayName),
                        "platform": .string(a.platform.rawValue),
                        "bundleOrPackageId": a.bundleOrPackageId.map(AnyCodableValue.string) ?? .null,
                        "state": .string(a.state)
                    ])
                })
            ])

        case "app_config":
            let targetId = try req(appId, name: "appId")
            let cfg: FirebaseAppConfig
            if auth.isDemo {
                let apps = DemoDataProvider.firebaseApps(for: pid)
                let match = apps.first(where: { $0.appId == targetId }) ?? FirebaseAppItem(appId: targetId, displayName: targetId, platform: .web, bundleOrPackageId: nil, state: "ACTIVE", apiKeyId: nil)
                cfg = DemoDataProvider.firebaseAppConfig(for: match, projectId: pid)
            } else {
                let token = try await auth.validAccessToken()
                let apps = try await api.listFirebaseApps(projectId: pid, token: token)
                let match = apps.first(where: { $0.appId == targetId }) ?? {
                    let guessedPlatform: FirebaseAppPlatform = targetId.contains(":ios:") ? .ios : (targetId.contains(":android:") ? .android : .web)
                    return FirebaseAppItem(appId: targetId, displayName: targetId, platform: guessedPlatform, bundleOrPackageId: nil, state: "ACTIVE", apiKeyId: nil)
                }()
                cfg = try await api.getFirebaseAppConfig(projectId: pid, app: match, token: token)
            }
            return .object([
                "appId": .string(cfg.appId),
                "platform": .string(cfg.platform.rawValue),
                "filename": .string(cfg.filename),
                "content": .string(cfg.rawContent)
            ])

        case "auth_list":
            let users: [FirebaseAuthUser]
            if auth.isDemo {
                users = DemoDataProvider.firebaseAuthUsers()
            } else {
                let token = try await auth.validAccessToken()
                users = try await api.listFirebaseAuthUsers(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "count": .int(users.count),
                "users": .array(users.map { u in
                    .object([
                        "localId": .string(u.localId),
                        "email": u.email.map(AnyCodableValue.string) ?? .null,
                        "displayName": u.displayName.map(AnyCodableValue.string) ?? .null,
                        "emailVerified": .bool(u.emailVerified),
                        "disabled": .bool(u.disabled),
                        "providers": .array(u.providers.map(AnyCodableValue.string)),
                        "lastLoginAt": u.lastLoginAt.map { .string(iso.string(from: $0)) } ?? .null
                    ])
                })
            ])

        case "auth_create":
            let userEmail = try req(email, name: "email")
            let userPass = try req(password, name: "password")
            if auth.isDemo {
                return .object([
                    "status": .string("simulated"),
                    "localId": .string("uid_demo_new"),
                    "email": .string(userEmail)
                ])
            }
            let token = try await auth.validAccessToken()
            let created = try await api.createFirebaseAuthUser(projectId: pid, email: userEmail, password: userPass, displayName: displayName, token: token)
            return .object([
                "status": .string("created"),
                "localId": .string(created.localId),
                "email": created.email.map(AnyCodableValue.string) ?? .null
            ])

        case "auth_disable", "auth_enable":
            let uid = try req(localId, name: "localId")
            let disable = (action == "auth_disable")
            if !auth.isDemo {
                let token = try await auth.validAccessToken()
                try await api.setFirebaseAuthUserDisabled(projectId: pid, localId: uid, disabled: disable, token: token)
            }
            return .object([
                "localId": .string(uid),
                "disabled": .bool(disable),
                "status": .string(auth.isDemo ? "simulated" : "updated")
            ])

        case "auth_delete":
            let uid = try req(localId, name: "localId")
            if !auth.isDemo {
                let token = try await auth.validAccessToken()
                try await api.deleteFirebaseAuthUser(projectId: pid, localId: uid, token: token)
            }
            return .object([
                "localId": .string(uid),
                "status": .string(auth.isDemo ? "simulated" : "deleted")
            ])

        case "hosting_sites":
            let sites: [FirebaseHostingSite]
            if auth.isDemo {
                sites = DemoDataProvider.firebaseHostingSites(for: pid)
            } else {
                let token = try await auth.validAccessToken()
                sites = try await api.listFirebaseHostingSites(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "sites": .array(sites.map {
                    .object(["siteId": .string($0.siteId), "defaultUrl": .string($0.defaultUrl), "type": .string($0.type)])
                })
            ])

        case "hosting_releases":
            let targetSite = (siteId?.isEmpty == false) ? siteId! : pid
            let rels: [FirebaseHostingRelease]
            if auth.isDemo {
                rels = DemoDataProvider.firebaseHostingReleases(for: targetSite)
            } else {
                let token = try await auth.validAccessToken()
                rels = try await api.listFirebaseHostingReleases(projectId: pid, siteId: targetSite, token: token)
            }
            return .object([
                "siteId": .string(targetSite),
                "releases": .array(rels.map {
                    .object([
                        "versionId": .string($0.versionId),
                        "status": .string($0.status),
                        "message": .string($0.message),
                        "releaseUser": $0.releaseUserEmail.map(AnyCodableValue.string) ?? .null,
                        "releaseTime": $0.releaseTime.map { .string(iso.string(from: $0)) } ?? .null
                    ])
                })
            ])

        case "hosting_channels":
            let targetSite = (siteId?.isEmpty == false) ? siteId! : pid
            let chans: [FirebaseHostingChannel]
            if auth.isDemo {
                chans = DemoDataProvider.firebaseHostingChannels(for: targetSite)
            } else {
                let token = try await auth.validAccessToken()
                chans = try await api.listFirebaseHostingChannels(projectId: pid, siteId: targetSite, token: token)
            }
            return .object([
                "siteId": .string(targetSite),
                "channels": .array(chans.map {
                    .object([
                        "channelId": .string($0.channelId),
                        "url": .string($0.url),
                        "expireTime": $0.expireTime.map { .string(iso.string(from: $0)) } ?? .null
                    ])
                })
            ])

        case "rules_list":
            let releases: [FirebaseRulesRelease]
            if auth.isDemo {
                releases = DemoDataProvider.firebaseRulesReleases(for: pid)
            } else {
                let token = try await auth.validAccessToken()
                releases = try await api.listFirebaseRulesReleases(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "releases": .array(releases.map {
                    .object([
                        "name": .string($0.shortName),
                        "rulesetName": .string($0.rulesetName),
                        "updateTime": $0.updateTime.map { .string(iso.string(from: $0)) } ?? .null
                    ])
                })
            ])

        case "rules_get":
            let targetRuleset: String
            if let rulesetName, !rulesetName.isEmpty {
                targetRuleset = rulesetName
            } else if auth.isDemo {
                targetRuleset = DemoDataProvider.firebaseRulesReleases(for: pid).first?.rulesetName ?? "projects/\(pid)/rulesets/rs_firestore_84a1"
            } else {
                let token = try await auth.validAccessToken()
                let rels = try await api.listFirebaseRulesReleases(projectId: pid, token: token)
                guard let first = rels.first?.rulesetName, !first.isEmpty else {
                    throw AgentBridgeError.missingArgument("rulesetName")
                }
                targetRuleset = first
            }
            let ruleset: FirebaseRuleset
            if auth.isDemo {
                ruleset = DemoDataProvider.firebaseRuleset(for: targetRuleset)
            } else {
                let token = try await auth.validAccessToken()
                ruleset = try await api.getFirebaseRuleset(rulesetName: targetRuleset, token: token)
            }
            return .object([
                "name": .string(ruleset.name),
                "files": .array(ruleset.files.map { .object(["name": .string($0.name), "content": .string($0.content)]) })
            ])

        case "remote_config_get":
            let tpl: FirebaseRemoteConfigTemplate
            if auth.isDemo {
                tpl = DemoDataProvider.firebaseRemoteConfig()
            } else {
                let token = try await auth.validAccessToken()
                tpl = try await api.getFirebaseRemoteConfig(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "etag": .string(tpl.etag),
                "versionNumber": .string(tpl.versionNumber),
                "parameters": .array(tpl.parameters.map {
                    .object(["key": .string($0.key), "valueType": .string($0.valueType), "defaultValue": .string($0.defaultValue), "description": .string($0.description)])
                }),
                "rawJSON": .string(tpl.rawJSON)
            ])

        case "remote_config_publish":
            let body = try req(rawJSON, name: "rawJSON")
            if auth.isDemo {
                let parsed = try FirebaseParser.decodeRemoteConfig(from: Data(body.utf8), etag: etag ?? "etag-demo")
                return .object(["status": .string("simulated"), "versionNumber": .string(parsed.versionNumber), "parameterCount": .int(parsed.parameters.count)])
            }
            let token = try await auth.validAccessToken()
            let tpl = try await api.publishFirebaseRemoteConfig(projectId: pid, rawJSON: body, etag: etag ?? "*", token: token)
            return .object(["status": .string("published"), "versionNumber": .string(tpl.versionNumber), "etag": .string(tpl.etag)])

        case "remote_config_versions":
            let vers: [FirebaseRemoteConfigVersion]
            if auth.isDemo {
                vers = DemoDataProvider.firebaseRemoteConfigVersions()
            } else {
                let token = try await auth.validAccessToken()
                vers = try await api.listFirebaseRemoteConfigVersions(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "versions": .array(vers.map {
                    .object([
                        "versionNumber": .string($0.versionNumber),
                        "updateUser": $0.updateUserEmail.map(AnyCodableValue.string) ?? .null,
                        "description": $0.description.map(AnyCodableValue.string) ?? .null,
                        "isRollback": .bool($0.isRollback)
                    ])
                })
            ])

        case "rtdb_instances":
            let insts: [RealtimeDBInstance]
            if auth.isDemo {
                insts = DemoDataProvider.realtimeDBInstances(for: pid)
            } else {
                let token = try await auth.validAccessToken()
                insts = try await api.listRealtimeDBInstances(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "instances": .array(insts.map {
                    .object(["instanceId": .string($0.instanceId), "databaseUrl": .string($0.databaseUrl), "region": .string($0.region), "state": .string($0.state)])
                })
            ])

        case "rtdb_get":
            let nodePath = path ?? "/"
            if auth.isDemo {
                let json = DemoDataProvider.realtimeDBSampleNode(path: nodePath, shallow: shallow)
                return .object(["path": .string(nodePath), "shallow": .bool(shallow), "data": .string(json)])
            }
            let token = try await auth.validAccessToken()
            let targetUrl: String
            if let databaseUrl, !databaseUrl.isEmpty {
                targetUrl = databaseUrl
            } else {
                let insts = try await api.listRealtimeDBInstances(projectId: pid, token: token)
                guard let firstUrl = insts.first?.databaseUrl else { throw AgentBridgeError.missingArgument("databaseUrl") }
                targetUrl = firstUrl
            }
            let json = try await api.readRealtimeDBNode(databaseUrl: targetUrl, path: nodePath, shallow: shallow, token: token)
            return .object(["databaseUrl": .string(targetUrl), "path": .string(nodePath), "data": .string(json)])

        case "rtdb_set":
            let nodePath = path ?? "/"
            let body = try req(rawJSON, name: "rawJSON")
            if auth.isDemo {
                return .object(["status": .string("simulated"), "path": .string(nodePath)])
            }
            let token = try await auth.validAccessToken()
            let targetUrl: String
            if let databaseUrl, !databaseUrl.isEmpty {
                targetUrl = databaseUrl
            } else {
                let insts = try await api.listRealtimeDBInstances(projectId: pid, token: token)
                guard let firstUrl = insts.first?.databaseUrl else { throw AgentBridgeError.missingArgument("databaseUrl") }
                targetUrl = firstUrl
            }
            _ = try await api.writeRealtimeDBNode(databaseUrl: targetUrl, path: nodePath, rawJSON: body, token: token)
            return .object(["status": .string("written"), "databaseUrl": .string(targetUrl), "path": .string(nodePath)])

        case "rtdb_delete":
            let nodePath = try req(path, name: "path")
            if auth.isDemo {
                return .object(["status": .string("simulated"), "path": .string(nodePath)])
            }
            let token = try await auth.validAccessToken()
            let targetUrl: String
            if let databaseUrl, !databaseUrl.isEmpty {
                targetUrl = databaseUrl
            } else {
                let insts = try await api.listRealtimeDBInstances(projectId: pid, token: token)
                guard let firstUrl = insts.first?.databaseUrl else { throw AgentBridgeError.missingArgument("databaseUrl") }
                targetUrl = firstUrl
            }
            try await api.deleteRealtimeDBNode(databaseUrl: targetUrl, path: nodePath, token: token)
            return .object(["status": .string("deleted"), "databaseUrl": .string(targetUrl), "path": .string(nodePath)])

        default:
            throw AgentBridgeError.invalidArgument("Unknown firebase action: \(action)")
        }
    }

    // MARK: - Firestore Agent Bridge

    func firestore(
        projectId: String?,
        databaseId: String = "(default)",
        action: String,
        collectionPath: String? = nil,
        documentPath: String? = nil,
        documentId: String? = nil,
        fieldsJSON: String? = nil,
        merge: Bool = true,
        filterField: String? = nil,
        filterOp: String? = nil,
        filterValue: String? = nil,
        orderBy: String? = nil,
        descending: Bool = false,
        limit: Int = 50,
        demo: Bool = false
    ) async throws -> AnyCodableValue {
        await ensureInitialized(forceDemo: demo)
        let pid = try await resolveFirebasePid(projectId)
        let dbId = databaseId.isEmpty ? "(default)" : databaseId

        switch action {
        case "databases":
            let dbs: [FirestoreDatabase]
            if auth.isDemo {
                dbs = DemoDataProvider.firestoreDatabases()
            } else {
                let token = try await auth.validAccessToken()
                dbs = try await api.listFirestoreDatabases(projectId: pid, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "databases": .array(dbs.map {
                    .object(["name": .string($0.name), "location": .string($0.location), "type": .string($0.type), "collections": .array($0.collections.map(AnyCodableValue.string))])
                })
            ])

        case "collections":
            let parentDoc = documentPath ?? ""
            let cols: [String]
            if auth.isDemo {
                cols = parentDoc.isEmpty ? DemoDataProvider.firestoreRootCollections() : DemoDataProvider.firestoreSubcollections(for: parentDoc)
            } else {
                let token = try await auth.validAccessToken()
                cols = try await api.listFirestoreSubcollections(projectId: pid, databaseId: dbId, parentDocumentPath: parentDoc, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "databaseId": .string(dbId),
                "parentDocumentPath": .string(parentDoc),
                "collections": .array(cols.map(AnyCodableValue.string))
            ])

        case "list":
            let col = try req(collectionPath, name: "collectionPath")
            let docs: [FirestoreDocument]
            if auth.isDemo {
                docs = DemoDataProvider.firestoreDocuments(projectId: pid, databaseId: dbId, collectionPath: col)
            } else {
                let token = try await auth.validAccessToken()
                docs = try await api.listFirestoreDocuments(projectId: pid, databaseId: dbId, collectionPath: col, pageSize: limit, token: token).documents
            }
            return .object([
                "collectionPath": .string(col),
                "count": .int(docs.count),
                "documents": .array(docs.map(encodeDoc))
            ])

        case "get":
            let docPath = try req(documentPath, name: "documentPath")
            let doc: FirestoreDocument
            if auth.isDemo {
                let parts = docPath.split(separator: "/").map(String.init)
                let col = parts.dropLast().joined(separator: "/")
                let id = parts.last ?? docPath
                doc = DemoDataProvider.firestoreDocuments(projectId: pid, databaseId: dbId, collectionPath: col).first(where: { $0.documentId == id })
                    ?? FirestoreDocument(name: "projects/\(pid)/databases/\(dbId)/documents/\(docPath)", documentId: id, relativePath: docPath, fields: [:], createTime: nil, updateTime: nil)
            } else {
                let token = try await auth.validAccessToken()
                doc = try await api.getFirestoreDocument(projectId: pid, databaseId: dbId, documentPath: docPath, token: token)
            }
            return encodeDoc(doc)

        case "create":
            let col = try req(collectionPath, name: "collectionPath")
            let raw = try req(fieldsJSON, name: "fieldsJSON")
            let fields = try FirestoreValue.fields(fromPlainJSONString: raw)
            if auth.isDemo {
                let id = documentId ?? "doc_demo_\(Int.random(in: 100...999))"
                return .object(["status": .string("simulated"), "documentId": .string(id), "relativePath": .string("\(col)/\(id)")])
            }
            let token = try await auth.validAccessToken()
            let created = try await api.createFirestoreDocument(projectId: pid, databaseId: dbId, collectionPath: col, documentId: documentId, fields: fields, token: token)
            return encodeDoc(created)

        case "update":
            let docPath = try req(documentPath, name: "documentPath")
            let raw = try req(fieldsJSON, name: "fieldsJSON")
            let fields = try FirestoreValue.fields(fromPlainJSONString: raw)
            if auth.isDemo {
                return .object(["status": .string("simulated"), "relativePath": .string(docPath)])
            }
            let token = try await auth.validAccessToken()
            let updated = try await api.updateFirestoreDocument(projectId: pid, databaseId: dbId, documentPath: docPath, fields: fields, merge: merge, token: token)
            return encodeDoc(updated)

        case "delete":
            let docPath = try req(documentPath, name: "documentPath")
            if !auth.isDemo {
                let token = try await auth.validAccessToken()
                try await api.deleteFirestoreDocument(projectId: pid, databaseId: dbId, documentPath: docPath, token: token)
            }
            return .object(["status": .string(auth.isDemo ? "simulated" : "deleted"), "relativePath": .string(docPath)])

        case "query":
            let col = try req(collectionPath, name: "collectionPath")
            let op = FirestoreQueryOperator(rawValue: (filterOp ?? "EQUAL").uppercased()) ?? .equal
            let docs: [FirestoreDocument]
            if auth.isDemo {
                let base = DemoDataProvider.firestoreDocuments(projectId: pid, databaseId: dbId, collectionPath: col)
                docs = FirebaseParser.filterAndSortDocuments(
                    base,
                    filterField: filterField,
                    op: op,
                    filterValueRaw: filterValue,
                    orderByField: orderBy,
                    descending: descending,
                    limit: limit
                )
            } else {
                let parts = col.trimmingCharacters(in: CharacterSet(charactersIn: "/")).split(separator: "/").map(String.init)
                let colId = parts.last ?? col
                let parentPath = parts.dropLast().joined(separator: "/")
                let token = try await auth.validAccessToken()
                docs = try await api.runFirestoreQuery(
                    projectId: pid,
                    databaseId: dbId,
                    parentPath: parentPath,
                    collectionId: colId,
                    filterField: filterField,
                    op: op,
                    filterValueRaw: filterValue,
                    orderByField: orderBy,
                    descending: descending,
                    limit: limit,
                    token: token
                )
            }
            return .object([
                "collectionPath": .string(col),
                "count": .int(docs.count),
                "documents": .array(docs.map(encodeDoc))
            ])

        case "indexes":
            let idxs: [FirestoreIndex]
            if auth.isDemo {
                idxs = DemoDataProvider.firestoreIndexes(projectId: pid, databaseId: dbId)
            } else {
                let token = try await auth.validAccessToken()
                idxs = try await api.listFirestoreIndexes(projectId: pid, databaseId: dbId, token: token)
            }
            return .object([
                "projectId": .string(pid),
                "databaseId": .string(dbId),
                "indexes": .array(idxs.map { idx in
                    .object([
                        "collectionGroup": .string(idx.collectionGroup),
                        "queryScope": .string(idx.queryScope),
                        "state": .string(idx.state),
                        "fields": .array(idx.fields.map { .object(["fieldPath": .string($0.fieldPath), "mode": .string($0.orderOrMode)]) })
                    ])
                })
            ])

        default:
            throw AgentBridgeError.invalidArgument("Unknown firestore action: \(action)")
        }
    }

    private func req(_ value: String?, name: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentBridgeError.missingArgument(name)
        }
        return value
    }

    private func encodeDoc(_ doc: FirestoreDocument) -> AnyCodableValue {
        var fieldObj: [String: AnyCodableValue] = [:]
        for (k, v) in doc.fields {
            fieldObj[k] = v.toCodableValue()
        }
        return .object([
            "documentId": .string(doc.documentId),
            "relativePath": .string(doc.relativePath),
            "fields": .object(fieldObj)
        ])
    }
}
