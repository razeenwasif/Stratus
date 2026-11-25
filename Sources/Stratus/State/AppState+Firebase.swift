import Foundation

extension AppState {
    // MARK: - Firestore Explorer (CRUD, Subcollections, Queries, Indexes)

    func selectFirestoreDatabase(_ databaseId: String) async {
        selectedFirestoreDatabaseId = databaseId
        firestoreParentDocumentPath = ""
        selectedFirestoreCollectionPath = ""
        firestoreDocuments = []
        selectedFirestoreDocument = nil
        firestoreDocSubcollections = []
        firestoreQueryActive = false
        await loadFirestoreCollectionsAtCurrentParent(autoOpenFirst: true)
        await loadFirestoreIndexes()
    }

    func loadFirestoreCollectionsAtCurrentParent(autoOpenFirst: Bool = false) async {
        guard let projectId = selectedProject?.projectId else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId

        if auth.isDemo {
            if firestoreParentDocumentPath.isEmpty {
                firestoreCollections = firestoreDatabases.first(where: { $0.name == dbId })?.collections
                    ?? DemoDataProvider.firestoreRootCollections()
            } else {
                firestoreCollections = DemoDataProvider.firestoreSubcollections(for: firestoreParentDocumentPath)
            }
            if autoOpenFirst, let first = firestoreCollections.first {
                let targetPath = firestoreParentDocumentPath.isEmpty ? first : "\(firestoreParentDocumentPath)/\(first)"
                await openFirestoreCollection(targetPath)
            }
            return
        }

        do {
            let token = try await auth.validAccessToken()
            firestoreCollections = try await api.listFirestoreSubcollections(
                projectId: projectId,
                databaseId: dbId,
                parentDocumentPath: firestoreParentDocumentPath,
                token: token
            )
            if autoOpenFirst, let first = firestoreCollections.first {
                let targetPath = firestoreParentDocumentPath.isEmpty ? first : "\(firestoreParentDocumentPath)/\(first)"
                await openFirestoreCollection(targetPath)
            }
        } catch {
            firestoreError = error.localizedDescription
        }
    }

    func openFirestoreCollection(_ collectionPath: String) async {
        let clean = collectionPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        selectedFirestoreCollectionPath = clean
        selectedFirestoreDocument = nil
        firestoreDocSubcollections = []
        firestoreQueryActive = false
        await reloadCurrentFirestoreCollection()
    }

    func reloadCurrentFirestoreCollection() async {
        guard let projectId = selectedProject?.projectId, !selectedFirestoreCollectionPath.isEmpty else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId
        isLoadingFirestoreDocs = true
        defer { isLoadingFirestoreDocs = false }

        if auth.isDemo {
            firestoreDocuments = DemoDataProvider.firestoreDocuments(
                projectId: projectId,
                databaseId: dbId,
                collectionPath: selectedFirestoreCollectionPath
            )
            if let first = firestoreDocuments.first {
                await selectFirestoreDocument(first)
            }
            return
        }

        do {
            let token = try await auth.validAccessToken()
            let res = try await api.listFirestoreDocuments(
                projectId: projectId,
                databaseId: dbId,
                collectionPath: selectedFirestoreCollectionPath,
                pageSize: 60,
                token: token
            )
            firestoreDocuments = res.documents
            if let currentId = selectedFirestoreDocument?.documentId,
               let updatedMatch = res.documents.first(where: { $0.documentId == currentId }) {
                await selectFirestoreDocument(updatedMatch)
            } else if let first = res.documents.first {
                await selectFirestoreDocument(first)
            } else {
                selectedFirestoreDocument = nil
                firestoreDocSubcollections = []
            }
        } catch {
            firestoreError = error.localizedDescription
            showToast(error.localizedDescription, isError: true)
        }
    }

    func drillIntoDocumentSubcollection(document: FirestoreDocument, subcollection: String) async {
        firestoreParentDocumentPath = document.relativePath
        await loadFirestoreCollectionsAtCurrentParent(autoOpenFirst: false)
        await openFirestoreCollection("\(document.relativePath)/\(subcollection)")
    }

    func navigateFirestoreToRoot() async {
        firestoreParentDocumentPath = ""
        await loadFirestoreCollectionsAtCurrentParent(autoOpenFirst: true)
    }

    func selectFirestoreDocument(_ doc: FirestoreDocument) async {
        selectedFirestoreDocument = doc
        guard let projectId = selectedProject?.projectId else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId

        if auth.isDemo {
            firestoreDocSubcollections = DemoDataProvider.firestoreSubcollections(for: doc.relativePath)
            return
        }

        do {
            let token = try await auth.validAccessToken()
            firestoreDocSubcollections = (try? await api.listFirestoreSubcollections(
                projectId: projectId,
                databaseId: dbId,
                parentDocumentPath: doc.relativePath,
                token: token
            )) ?? []
        } catch {
            firestoreDocSubcollections = []
        }
    }

    func createFirestoreDocument(documentId: String?, fieldsJSON: String) async {
        guard let projectId = selectedProject?.projectId, !selectedFirestoreCollectionPath.isEmpty else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId
        isMutatingFirestore = true
        defer { isMutatingFirestore = false }

        do {
            let fields = try FirestoreValue.fields(fromPlainJSONString: fieldsJSON)
            let cleanId = documentId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveId = (cleanId?.isEmpty == false) ? cleanId! : "doc_\(UUID().uuidString.prefix(8).lowercased())"

            if auth.isDemo {
                let relPath = "\(selectedFirestoreCollectionPath)/\(effectiveId)"
                let newDoc = FirestoreDocument(
                    name: "projects/\(projectId)/databases/\(dbId)/documents/\(relPath)",
                    documentId: effectiveId,
                    relativePath: relPath,
                    fields: fields,
                    createTime: Date(),
                    updateTime: Date()
                )
                firestoreDocuments.insert(newDoc, at: 0)
                await selectFirestoreDocument(newDoc)
                showToast("Created document \(effectiveId) (demo)")
                return
            }

            let token = try await auth.validAccessToken()
            let created = try await api.createFirestoreDocument(
                projectId: projectId,
                databaseId: dbId,
                collectionPath: selectedFirestoreCollectionPath,
                documentId: (cleanId?.isEmpty == false) ? cleanId : nil,
                fields: fields,
                token: token
            )
            firestoreDocuments.insert(created, at: 0)
            await selectFirestoreDocument(created)
            showToast("Created document \(created.documentId)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func saveFirestoreDocument(_ doc: FirestoreDocument, fieldsJSON: String) async {
        guard let projectId = selectedProject?.projectId else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId
        isMutatingFirestore = true
        defer { isMutatingFirestore = false }

        do {
            let fields = try FirestoreValue.fields(fromPlainJSONString: fieldsJSON)

            if auth.isDemo {
                let updated = FirestoreDocument(
                    name: doc.name,
                    documentId: doc.documentId,
                    relativePath: doc.relativePath,
                    fields: fields,
                    createTime: doc.createTime,
                    updateTime: Date()
                )
                if let idx = firestoreDocuments.firstIndex(where: { $0.id == doc.id }) {
                    firestoreDocuments[idx] = updated
                }
                selectedFirestoreDocument = updated
                showToast("Saved \(doc.documentId) (demo)")
                return
            }

            let token = try await auth.validAccessToken()
            let updated = try await api.updateFirestoreDocument(
                projectId: projectId,
                databaseId: dbId,
                documentPath: doc.relativePath,
                fields: fields,
                token: token
            )
            if let idx = firestoreDocuments.firstIndex(where: { $0.id == doc.id }) {
                firestoreDocuments[idx] = updated
            }
            selectedFirestoreDocument = updated
            showToast("Saved \(doc.documentId)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func deleteFirestoreDocument(_ doc: FirestoreDocument) async {
        guard let projectId = selectedProject?.projectId else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId
        isMutatingFirestore = true
        defer { isMutatingFirestore = false }

        if auth.isDemo {
            firestoreDocuments.removeAll { $0.id == doc.id }
            selectedFirestoreDocument = firestoreDocuments.first
            showToast("Deleted \(doc.documentId) (demo)")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            try await api.deleteFirestoreDocument(
                projectId: projectId,
                databaseId: dbId,
                documentPath: doc.relativePath,
                token: token
            )
            firestoreDocuments.removeAll { $0.id == doc.id }
            if let next = firestoreDocuments.first {
                await selectFirestoreDocument(next)
            } else {
                selectedFirestoreDocument = nil
                firestoreDocSubcollections = []
            }
            showToast("Deleted \(doc.documentId)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func runFirestoreStructuredQuery(
        fieldPath: String,
        op: FirestoreQueryOperator,
        valueRaw: String,
        orderBy: String,
        descending: Bool,
        limit: Int
    ) async {
        guard let projectId = selectedProject?.projectId, !selectedFirestoreCollectionPath.isEmpty else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId
        let collectionId = selectedFirestoreCollectionPath.split(separator: "/").last.map(String.init) ?? selectedFirestoreCollectionPath
        let parentSegments = selectedFirestoreCollectionPath.split(separator: "/").dropLast()
        let parentPath = parentSegments.joined(separator: "/")

        isLoadingFirestoreDocs = true
        defer { isLoadingFirestoreDocs = false }

        if auth.isDemo {
            let base = DemoDataProvider.firestoreDocuments(
                projectId: projectId,
                databaseId: dbId,
                collectionPath: selectedFirestoreCollectionPath
            )
            let cleanField = fieldPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanVal = valueRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanField.isEmpty || cleanVal.isEmpty {
                firestoreDocuments = Array(base.prefix(max(1, limit)))
            } else {
                firestoreDocuments = base.filter { doc in
                    guard let fieldVal = doc.fields[cleanField] else { return false }
                    let candidate = fieldVal.displayString.lowercased()
                    let target = cleanVal.lowercased()
                    switch op {
                    case .equal: return candidate == target
                    case .notEqual: return candidate != target
                    case .arrayContains: return candidate.contains(target)
                    default: return candidate.contains(target)
                    }
                }
            }
            firestoreQueryActive = true
            selectedFirestoreDocument = firestoreDocuments.first
            return
        }

        do {
            let token = try await auth.validAccessToken()
            let results = try await api.runFirestoreQuery(
                projectId: projectId,
                databaseId: dbId,
                parentPath: parentPath,
                collectionId: collectionId,
                filterField: fieldPath,
                op: op,
                filterValueRaw: valueRaw,
                orderByField: orderBy.isEmpty ? nil : orderBy,
                descending: descending,
                limit: limit,
                token: token
            )
            firestoreDocuments = results
            firestoreQueryActive = true
            if let first = results.first {
                await selectFirestoreDocument(first)
            } else {
                selectedFirestoreDocument = nil
                firestoreDocSubcollections = []
            }
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func clearFirestoreQuery() async {
        firestoreQueryActive = false
        await reloadCurrentFirestoreCollection()
    }

    func loadFirestoreIndexes() async {
        guard let projectId = selectedProject?.projectId else { return }
        let dbId = selectedFirestoreDatabaseId.isEmpty ? "(default)" : selectedFirestoreDatabaseId

        if auth.isDemo {
            firestoreIndexes = DemoDataProvider.firestoreIndexes(projectId: projectId, databaseId: dbId)
            return
        }

        do {
            let token = try await auth.validAccessToken()
            firestoreIndexes = (try? await api.listFirestoreIndexes(projectId: projectId, databaseId: dbId, token: token)) ?? []
        } catch {
            firestoreIndexes = []
        }
    }

    // MARK: - Firebase Section

    func refreshFirebaseSection() async {
        switch selectedFirebaseTab {
        case .apps: await refreshFirebaseApps()
        case .auth: await refreshFirebaseAuth()
        case .hosting: await refreshFirebaseHosting()
        case .rules: await refreshFirebaseRules()
        case .remoteConfig: await refreshFirebaseRemoteConfig()
        case .realtimeDB: await refreshRealtimeDB()
        }
    }

    func refreshFirebaseApps() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingFirebaseApps = true
        firebaseAppsError = nil
        defer { isLoadingFirebaseApps = false }

        if auth.isDemo {
            firebaseProjectInfo = DemoDataProvider.firebaseProject(for: projectId)
            firebaseApps = DemoDataProvider.firebaseApps(for: projectId)
            if selectedFirebaseAppConfig == nil, let first = firebaseApps.first {
                selectedFirebaseAppConfig = DemoDataProvider.firebaseAppConfig(for: first, projectId: projectId)
            }
            return
        }

        do {
            let token = try await auth.validAccessToken()
            async let projTask = api.getFirebaseProject(projectId: projectId, token: token)
            async let appsTask = api.listFirebaseApps(projectId: projectId, token: token)
            firebaseProjectInfo = try await projTask
            firebaseApps = try await appsTask
        } catch {
            firebaseAppsError = error.localizedDescription
        }
    }

    func loadFirebaseAppConfig(_ app: FirebaseAppItem) async {
        guard let projectId = selectedProject?.projectId else { return }
        if auth.isDemo {
            selectedFirebaseAppConfig = DemoDataProvider.firebaseAppConfig(for: app, projectId: projectId)
            return
        }
        do {
            let token = try await auth.validAccessToken()
            selectedFirebaseAppConfig = try await api.getFirebaseAppConfig(projectId: projectId, app: app, token: token)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: Firebase Auth

    func refreshFirebaseAuth() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingFirebaseAuth = true
        firebaseAuthError = nil
        defer { isLoadingFirebaseAuth = false }

        if auth.isDemo {
            firebaseAuthUsers = DemoDataProvider.firebaseAuthUsers()
            return
        }

        do {
            let token = try await auth.validAccessToken()
            firebaseAuthUsers = try await api.listFirebaseAuthUsers(projectId: projectId, token: token)
        } catch {
            firebaseAuthError = error.localizedDescription
        }
    }

    func createFirebaseAuthUser(email: String, password: String, displayName: String) async {
        guard let projectId = selectedProject?.projectId else { return }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, password.count >= 6 else {
            showToast("Email required and password must be at least 6 characters", isError: true)
            return
        }

        if auth.isDemo {
            let newUser = FirebaseAuthUser(
                localId: "uid_\(UUID().uuidString.prefix(8).lowercased())",
                email: cleanEmail,
                displayName: displayName.isEmpty ? nil : displayName,
                phoneNumber: nil,
                emailVerified: false,
                disabled: false,
                providers: ["password"],
                createdAt: Date(),
                lastLoginAt: nil
            )
            firebaseAuthUsers.insert(newUser, at: 0)
            showToast("Created user \(cleanEmail) (demo)")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            let created = try await api.createFirebaseAuthUser(
                projectId: projectId,
                email: cleanEmail,
                password: password,
                displayName: displayName,
                token: token
            )
            firebaseAuthUsers.insert(created, at: 0)
            showToast("Created user \(cleanEmail)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func toggleFirebaseAuthUserDisabled(_ user: FirebaseAuthUser) async {
        guard let projectId = selectedProject?.projectId else { return }
        busyFirebaseAuthUIDs.insert(user.localId)
        defer { busyFirebaseAuthUIDs.remove(user.localId) }
        let nextDisabled = !user.disabled

        if auth.isDemo {
            if let idx = firebaseAuthUsers.firstIndex(where: { $0.localId == user.localId }) {
                let u = firebaseAuthUsers[idx]
                firebaseAuthUsers[idx] = FirebaseAuthUser(
                    localId: u.localId,
                    email: u.email,
                    displayName: u.displayName,
                    phoneNumber: u.phoneNumber,
                    emailVerified: u.emailVerified,
                    disabled: nextDisabled,
                    providers: u.providers,
                    createdAt: u.createdAt,
                    lastLoginAt: u.lastLoginAt
                )
            }
            showToast("\(user.email ?? user.localId) \(nextDisabled ? "disabled" : "enabled") (demo)")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            try await api.setFirebaseAuthUserDisabled(
                projectId: projectId,
                localId: user.localId,
                disabled: nextDisabled,
                token: token
            )
            showToast("\(user.email ?? user.localId) \(nextDisabled ? "disabled" : "enabled")")
            await refreshFirebaseAuth()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func deleteFirebaseAuthUser(_ user: FirebaseAuthUser) async {
        guard let projectId = selectedProject?.projectId else { return }
        busyFirebaseAuthUIDs.insert(user.localId)
        defer { busyFirebaseAuthUIDs.remove(user.localId) }

        if auth.isDemo {
            firebaseAuthUsers.removeAll { $0.localId == user.localId }
            showToast("Deleted user \(user.email ?? user.localId) (demo)")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            try await api.deleteFirebaseAuthUser(projectId: projectId, localId: user.localId, token: token)
            firebaseAuthUsers.removeAll { $0.localId == user.localId }
            showToast("Deleted user \(user.email ?? user.localId)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: Firebase Hosting

    func refreshFirebaseHosting() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingFirebaseHosting = true
        firebaseHostingError = nil
        defer { isLoadingFirebaseHosting = false }

        if auth.isDemo {
            firebaseHostingSites = DemoDataProvider.firebaseHostingSites(for: projectId)
            let site = selectedHostingSite ?? firebaseHostingSites.first
            if let site {
                await selectFirebaseHostingSite(site)
            }
            return
        }

        do {
            let token = try await auth.validAccessToken()
            firebaseHostingSites = try await api.listFirebaseHostingSites(projectId: projectId, token: token)
            if let current = selectedHostingSite,
               let match = firebaseHostingSites.first(where: { $0.siteId == current.siteId }) {
                await selectFirebaseHostingSite(match)
            } else if let first = firebaseHostingSites.first {
                await selectFirebaseHostingSite(first)
            }
        } catch {
            firebaseHostingError = error.localizedDescription
        }
    }

    func selectFirebaseHostingSite(_ site: FirebaseHostingSite) async {
        selectedHostingSite = site
        guard let projectId = selectedProject?.projectId else { return }

        if auth.isDemo {
            firebaseHostingReleases = DemoDataProvider.firebaseHostingReleases(for: site.siteId)
            firebaseHostingChannels = DemoDataProvider.firebaseHostingChannels(for: site.siteId)
            return
        }

        do {
            let token = try await auth.validAccessToken()
            async let rels = try? api.listFirebaseHostingReleases(projectId: projectId, siteId: site.siteId, token: token)
            async let chans = try? api.listFirebaseHostingChannels(projectId: projectId, siteId: site.siteId, token: token)
            firebaseHostingReleases = await rels ?? []
            firebaseHostingChannels = await chans ?? []
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: Firebase Security Rules

    func refreshFirebaseRules() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingFirebaseRules = true
        firebaseRulesError = nil
        defer { isLoadingFirebaseRules = false }

        if auth.isDemo {
            firebaseRulesReleases = DemoDataProvider.firebaseRulesReleases(for: projectId)
            if let first = selectedRulesRelease ?? firebaseRulesReleases.first {
                await selectFirebaseRulesRelease(first)
            }
            return
        }

        do {
            let token = try await auth.validAccessToken()
            firebaseRulesReleases = try await api.listFirebaseRulesReleases(projectId: projectId, token: token)
            if let current = selectedRulesRelease,
               let match = firebaseRulesReleases.first(where: { $0.name == current.name }) {
                await selectFirebaseRulesRelease(match)
            } else if let first = firebaseRulesReleases.first {
                await selectFirebaseRulesRelease(first)
            }
        } catch {
            firebaseRulesError = error.localizedDescription
        }
    }

    func selectFirebaseRulesRelease(_ release: FirebaseRulesRelease) async {
        selectedRulesRelease = release
        if auth.isDemo {
            activeFirebaseRuleset = DemoDataProvider.firebaseRuleset(for: release.rulesetName)
            return
        }
        guard !release.rulesetName.isEmpty else {
            activeFirebaseRuleset = nil
            return
        }
        do {
            let token = try await auth.validAccessToken()
            activeFirebaseRuleset = try await api.getFirebaseRuleset(rulesetName: release.rulesetName, token: token)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: Firebase Remote Config

    func refreshFirebaseRemoteConfig() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingFirebaseRemoteConfig = true
        firebaseRemoteConfigError = nil
        defer { isLoadingFirebaseRemoteConfig = false }

        if auth.isDemo {
            firebaseRemoteConfig = DemoDataProvider.firebaseRemoteConfig()
            firebaseRemoteConfigVersions = DemoDataProvider.firebaseRemoteConfigVersions()
            return
        }

        do {
            let token = try await auth.validAccessToken()
            async let tplTask = api.getFirebaseRemoteConfig(projectId: projectId, token: token)
            async let versTask = try? api.listFirebaseRemoteConfigVersions(projectId: projectId, token: token)
            firebaseRemoteConfig = try await tplTask
            firebaseRemoteConfigVersions = await versTask ?? []
        } catch {
            firebaseRemoteConfigError = error.localizedDescription
        }
    }

    func publishFirebaseRemoteConfig(rawJSON: String) async {
        guard let projectId = selectedProject?.projectId else { return }
        isPublishingRemoteConfig = true
        defer { isPublishingRemoteConfig = false }

        if auth.isDemo {
            do {
                let parsed = try FirebaseParser.decodeRemoteConfig(from: Data(rawJSON.utf8), etag: "etag-demo-published")
                firebaseRemoteConfig = parsed
                showToast("Published Remote Config template (demo)")
            } catch {
                showToast("Invalid Remote Config JSON: \(error.localizedDescription)", isError: true)
            }
            return
        }

        do {
            let token = try await auth.validAccessToken()
            let etag = firebaseRemoteConfig?.etag ?? "*"
            let published = try await api.publishFirebaseRemoteConfig(
                projectId: projectId,
                rawJSON: rawJSON,
                etag: etag,
                token: token
            )
            firebaseRemoteConfig = published
            firebaseRemoteConfigVersions = (try? await api.listFirebaseRemoteConfigVersions(projectId: projectId, token: token)) ?? firebaseRemoteConfigVersions
            showToast("Published Remote Config v\(published.versionNumber)")
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    // MARK: Firebase Realtime Database

    func refreshRealtimeDB() async {
        guard let projectId = selectedProject?.projectId else { return }
        isLoadingRealtimeDB = true
        realtimeDBError = nil
        defer { isLoadingRealtimeDB = false }

        if auth.isDemo {
            realtimeDBInstances = DemoDataProvider.realtimeDBInstances(for: projectId)
            if selectedRealtimeDB == nil, let first = realtimeDBInstances.first {
                selectedRealtimeDB = first
            }
            await loadRealtimeDBNode(path: realtimeDBPath, shallow: realtimeDBShallow)
            return
        }

        do {
            let token = try await auth.validAccessToken()
            realtimeDBInstances = try await api.listRealtimeDBInstances(projectId: projectId, token: token)
            if selectedRealtimeDB == nil, let first = realtimeDBInstances.first {
                selectedRealtimeDB = first
            }
            if selectedRealtimeDB != nil {
                await loadRealtimeDBNode(path: realtimeDBPath, shallow: realtimeDBShallow)
            }
        } catch {
            realtimeDBError = error.localizedDescription
        }
    }

    func loadRealtimeDBNode(path: String, shallow: Bool) async {
        realtimeDBPath = path.isEmpty ? "/" : path
        realtimeDBShallow = shallow
        guard let instance = selectedRealtimeDB else { return }

        if auth.isDemo {
            realtimeDBPayload = DemoDataProvider.realtimeDBSampleNode(path: realtimeDBPath, shallow: shallow)
            return
        }

        do {
            let token = try await auth.validAccessToken()
            realtimeDBPayload = try await api.readRealtimeDBNode(
                databaseUrl: instance.databaseUrl,
                path: realtimeDBPath,
                shallow: shallow,
                token: token
            )
        } catch {
            realtimeDBError = error.localizedDescription
            showToast(error.localizedDescription, isError: true)
        }
    }

    func writeRealtimeDBNode(path: String, rawJSON: String) async {
        guard let instance = selectedRealtimeDB else { return }
        isMutatingRealtimeDB = true
        defer { isMutatingRealtimeDB = false }

        if auth.isDemo {
            realtimeDBPath = path.isEmpty ? "/" : path
            realtimeDBPayload = rawJSON
            showToast("Updated RTDB node \(realtimeDBPath) (demo)")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            _ = try await api.writeRealtimeDBNode(
                databaseUrl: instance.databaseUrl,
                path: path,
                rawJSON: rawJSON,
                token: token
            )
            showToast("Updated RTDB node \(path)")
            await loadRealtimeDBNode(path: path, shallow: false)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    func deleteRealtimeDBNode(path: String) async {
        guard let instance = selectedRealtimeDB else { return }
        isMutatingRealtimeDB = true
        defer { isMutatingRealtimeDB = false }

        if auth.isDemo {
            realtimeDBPayload = "null"
            showToast("Deleted RTDB node \(path) (demo)")
            return
        }

        do {
            let token = try await auth.validAccessToken()
            try await api.deleteRealtimeDBNode(databaseUrl: instance.databaseUrl, path: path, token: token)
            showToast("Deleted RTDB node \(path)")
            await loadRealtimeDBNode(path: "/", shallow: realtimeDBShallow)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }
}
