import SwiftUI

struct FirestoreExplorerView: View {
    @Environment(AppState.self) private var appState

    enum ViewMode: String, CaseIterable, Identifiable {
        case documents = "Documents"
        case indexes = "Indexes"
        var id: String { rawValue }
    }

    @State private var mode: ViewMode = .documents
    @State private var showQueryBar = false
    @State private var queryField = ""
    @State private var queryOp: FirestoreQueryOperator = .equal
    @State private var queryValue = ""
    @State private var queryOrderBy = ""
    @State private var queryDescending = false
    @State private var queryLimit = 50

    @State private var editingJSON = false
    @State private var docJSONDraft = "{}"
    @State private var confirmDeleteDocId: String?

    @State private var showCreateCollection = false
    @State private var newCollectionName = ""
    @State private var newCollectionDocId = ""
    @State private var newCollectionDocJSON = "{\n  \"created\": true\n}"

    @State private var showCreateSubcollection = false
    @State private var newSubcollectionName = ""
    @State private var newSubcollectionDocId = ""
    @State private var newSubcollectionDocJSON = "{\n  \"created\": true\n}"

    @State private var showCreateDoc = false
    @State private var newDocId = ""
    @State private var newDocJSON = "{\n  \"name\": \"example\",\n  \"active\": true\n}"

    var body: some View {
        Group {
            if appState.isLoadingFirestore && appState.firestoreDatabases.isEmpty {
                ProgressView("Loading Firestore databases...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.firestoreError, appState.firestoreDatabases.isEmpty {
                EmptyStateView(icon: "flame", title: "Firestore unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshFirestore() }
                }
            } else if appState.firestoreDatabases.isEmpty {
                EmptyStateView(icon: "flame", title: "No Firestore databases", message: "No Firestore databases configured in this project.")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    topControlBar

                    if mode == .indexes {
                        indexesView
                    } else {
                        threeColumnBrowser
                    }
                }
            }
        }
        .onChange(of: appState.selectedFirestoreDocument?.id) { _, _ in
            editingJSON = false
            confirmDeleteDocId = nil
            showCreateSubcollection = false
        }
    }

    private var topControlBar: some View {
        HStack(spacing: 10) {
            ForEach(appState.firestoreDatabases) { db in
                FilterPillButton(
                    title: "\(db.name) · \(db.location)",
                    isSelected: appState.selectedFirestoreDatabaseId == db.name
                ) {
                    Task { await appState.selectFirestoreDatabase(db.name) }
                }
            }

            // Clickable multi-level breadcrumbs
            let segments = appState.selectedFirestoreCollectionPath
                .split(separator: "/")
                .map(String.init)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    Button {
                        Task { await appState.navigateFirestoreToRoot() }
                    } label: {
                        Text("root")
                            .font(T3.mono(11.5, weight: .semibold))
                            .foregroundStyle(appState.firestoreParentDocumentPath.isEmpty ? T3.textPrimary : T3.sky)
                    }
                    .buttonStyle(.plain)

                    ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(T3.textTertiary)
                        let isCollectionSeg = (idx % 2 == 0)
                        let targetCollection = isCollectionSeg
                            ? segments[0...idx].joined(separator: "/")
                            : segments[0..<idx].joined(separator: "/")
                        Button {
                            Task { await appState.navigateFirestoreBreadcrumb(toCollectionPath: targetCollection) }
                        } label: {
                            Text(seg)
                                .font(T3.mono(11.5, weight: idx == segments.count - 1 ? .semibold : .regular))
                                .foregroundStyle(isCollectionSeg ? T3.mint : T3.amber)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Spacer()

            HStack(spacing: 4) {
                ForEach(ViewMode.allCases) { m in
                    FilterPillButton(title: m.rawValue, isSelected: mode == m) {
                        mode = m
                        if m == .indexes {
                            Task { await appState.loadFirestoreIndexes() }
                        }
                    }
                }
            }
        }
    }

    private var threeColumnBrowser: some View {
        HStack(alignment: .top, spacing: 20) {
            // Column 1: Collections
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(appState.firestoreParentDocumentPath.isEmpty ? "COLLECTIONS" : "SUBCOLLECTIONS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(T3.textTertiary)
                    Spacer()
                    ActionPillButton(title: "New", systemImage: showCreateCollection ? "xmark" : "folder.badge.plus", tint: T3.amber) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showCreateCollection.toggle()
                        }
                    }
                }
                .padding(.horizontal, 6)

                if showCreateCollection {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("", text: $newCollectionName, prompt: Text("Collection name").foregroundStyle(T3.textTertiary))
                            .textFieldStyle(.plain)
                            .font(T3.mono(11.5))
                            .foregroundStyle(T3.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                        TextField("", text: $newCollectionDocId, prompt: Text("First doc ID (optional)").foregroundStyle(T3.textTertiary))
                            .textFieldStyle(.plain)
                            .font(T3.mono(11.5))
                            .foregroundStyle(T3.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                        TextEditor(text: $newCollectionDocJSON)
                            .font(T3.mono(11))
                            .foregroundStyle(T3.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .frame(height: 68)
                            .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                        ActionPillButton(title: "Create", systemImage: "checkmark", tint: T3.mint, isLoading: appState.isMutatingFirestore) {
                            let col = newCollectionName
                            let docId = newCollectionDocId
                            let json = newCollectionDocJSON
                            Task {
                                await appState.createFirestoreCollectionAndDocument(
                                    collectionName: col,
                                    documentId: docId.isEmpty ? nil : docId,
                                    fieldsJSON: json
                                )
                                newCollectionName = ""
                                newCollectionDocId = ""
                                showCreateCollection = false
                            }
                        }
                    }
                    .padding(8)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(appState.firestoreCollections, id: \.self) { col in
                            let fullPath = appState.firestoreParentDocumentPath.isEmpty
                                ? col
                                : "\(appState.firestoreParentDocumentPath)/\(col)"
                            let isSelected = appState.selectedFirestoreCollectionPath == fullPath
                            Button {
                                Task { await appState.openFirestoreCollection(fullPath) }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(isSelected ? T3.amber : T3.textTertiary)
                                    Text(col)
                                        .font(T3.mono(12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? T3.textPrimary : T3.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected ? T3.surfaceActive : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 195)

            // Column 2: Documents + Structured Query
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("DOCUMENTS (\(appState.firestoreDocuments.count))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(T3.textTertiary)

                    if appState.firestoreQueryActive {
                        TagPill(text: "filtered", color: T3.indigo, monospaced: true)
                    }

                    Spacer()

                    ActionPillButton(title: "Query", systemImage: "line.3.horizontal.decrease.circle", tint: showQueryBar ? T3.indigo : T3.textSecondary) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showQueryBar.toggle()
                        }
                    }

                    ActionPillButton(title: "New", systemImage: "plus", tint: T3.mint) {
                        showCreateDoc.toggle()
                    }
                }

                if showQueryBar {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            TextField("", text: $queryField, prompt: Text("field (e.g. plan)").foregroundStyle(T3.textTertiary))
                                .textFieldStyle(.plain)
                                .font(T3.mono(11.5))
                                .foregroundStyle(T3.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                            Picker("", selection: $queryOp) {
                                ForEach(FirestoreQueryOperator.allCases) { op in
                                    Text(op.symbol).tag(op)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 85)

                            TextField("", text: $queryValue, prompt: Text("value").foregroundStyle(T3.textTertiary))
                                .textFieldStyle(.plain)
                                .font(T3.mono(11.5))
                                .foregroundStyle(T3.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))
                        }
                        HStack(spacing: 6) {
                            TextField("", text: $queryOrderBy, prompt: Text("orderBy (optional)").foregroundStyle(T3.textTertiary))
                                .textFieldStyle(.plain)
                                .font(T3.mono(11.5))
                                .foregroundStyle(T3.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                            FilterPillButton(title: queryDescending ? "DESC" : "ASC", isSelected: queryDescending) {
                                queryDescending.toggle()
                            }

                            Picker("", selection: $queryLimit) {
                                Text("25").tag(25)
                                Text("50").tag(50)
                                Text("100").tag(100)
                            }
                            .labelsHidden()
                            .frame(width: 60)

                            ActionPillButton(title: "Run", systemImage: "play.fill", tint: T3.mint) {
                                Task {
                                    await appState.runFirestoreStructuredQuery(
                                        fieldPath: queryField,
                                        op: queryOp,
                                        valueRaw: queryValue,
                                        orderBy: queryOrderBy,
                                        descending: queryDescending,
                                        limit: queryLimit
                                    )
                                }
                            }
                            if appState.firestoreQueryActive {
                                ActionPillButton(title: "Clear", systemImage: "xmark", tint: T3.textSecondary) {
                                    queryField = ""
                                    queryValue = ""
                                    queryOrderBy = ""
                                    queryDescending = false
                                    Task { await appState.clearFirestoreQuery() }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                if showCreateDoc {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CREATE DOCUMENT IN \(appState.selectedFirestoreCollectionPath)")
                                .font(T3.mono(10.5, weight: .semibold))
                                .foregroundStyle(T3.mint)
                            Spacer()
                            Button { showCreateDoc = false } label: {
                                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(T3.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("", text: $newDocId, prompt: Text("Document ID (optional — auto-generated if blank)").foregroundStyle(T3.textTertiary))
                            .textFieldStyle(.plain)
                            .font(T3.mono(12))
                            .foregroundStyle(T3.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                        TextEditor(text: $newDocJSON)
                            .font(T3.mono(11.5))
                            .foregroundStyle(T3.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 105)
                            .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                        HStack {
                            Spacer()
                            ActionPillButton(title: "Create Document", systemImage: "checkmark", tint: T3.mint, isLoading: appState.isMutatingFirestore) {
                                let id = newDocId
                                let json = newDocJSON
                                Task {
                                    await appState.createFirestoreDocument(documentId: id.isEmpty ? nil : id, fieldsJSON: json)
                                    newDocId = ""
                                    showCreateDoc = false
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                if appState.isLoadingFirestoreDocs && appState.firestoreDocuments.isEmpty {
                    ProgressView("Loading documents...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.firestoreDocuments.isEmpty {
                    EmptyStateView(icon: "doc", title: "No documents", message: "No documents matched in \(appState.selectedFirestoreCollectionPath).")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(appState.firestoreDocuments) { doc in
                                let isSelected = appState.selectedFirestoreDocument?.id == doc.id
                                Button {
                                    Task { await appState.selectFirestoreDocument(doc) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(doc.documentId)
                                                .font(T3.mono(12, weight: .semibold))
                                                .foregroundStyle(isSelected ? T3.textPrimary : T3.textSecondary)
                                                .lineLimit(1)
                                            Spacer()
                                            if let updated = doc.updateTime {
                                                Text(Formatters.relativeDate(updated))
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(T3.textTertiary)
                                            }
                                        }
                                        Text(doc.summaryLine)
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        isSelected ? T3.surfaceActive : T3.surfaceSubtle,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            if appState.firestoreNextPageToken != nil {
                                ActionPillButton(
                                    title: "Load More",
                                    systemImage: "arrow.down.circle",
                                    tint: T3.sky,
                                    isLoading: appState.isLoadingFirestoreDocs
                                ) {
                                    Task { await appState.loadMoreFirestoreDocuments() }
                                }
                                .padding(.top, 6)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .frame(minWidth: 270, maxWidth: 360)

            // Column 3: Document Inspector & Editor
            VStack(alignment: .leading, spacing: 12) {
                if let doc = appState.selectedFirestoreDocument {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.documentId)
                                .font(T3.mono(14, weight: .semibold))
                                .foregroundStyle(T3.textPrimary)
                            Text(doc.relativePath)
                                .font(T3.mono(11))
                                .foregroundStyle(T3.textTertiary)
                        }
                        Spacer()

                        ActionPillButton(title: "Copy Path", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                            appState.copyToClipboard(doc.relativePath, label: "document path")
                        }

                        ActionPillButton(title: "+ Sub", systemImage: "folder.badge.plus", tint: T3.amber) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showCreateSubcollection.toggle()
                            }
                        }

                        FilterPillButton(title: editingJSON ? "Fields" : "Edit JSON", isSelected: editingJSON) {
                            if !editingJSON {
                                docJSONDraft = FirestoreValue.prettyJSONString(from: doc.fields)
                            }
                            editingJSON.toggle()
                        }

                        if editingJSON {
                            ActionPillButton(title: "Save", systemImage: "checkmark", tint: T3.mint, isLoading: appState.isMutatingFirestore) {
                                Task {
                                    await appState.saveFirestoreDocument(doc, fieldsJSON: docJSONDraft)
                                    editingJSON = false
                                }
                            }
                        }

                        if confirmDeleteDocId == doc.id {
                            ActionPillButton(title: "Confirm Delete", systemImage: "trash", tint: T3.rose, isLoading: appState.isMutatingFirestore) {
                                confirmDeleteDocId = nil
                                Task { await appState.deleteFirestoreDocument(doc) }
                            }
                        } else {
                            ActionPillButton(title: "Delete", systemImage: "trash", tint: T3.rose) {
                                confirmDeleteDocId = doc.id
                            }
                        }
                    }

                    if showCreateSubcollection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CREATE SUBCOLLECTION UNDER \(doc.documentId)")
                                .font(T3.mono(10.5, weight: .semibold))
                                .foregroundStyle(T3.amber)
                            HStack(spacing: 8) {
                                TextField("", text: $newSubcollectionName, prompt: Text("Subcollection name").foregroundStyle(T3.textTertiary))
                                    .textFieldStyle(.plain)
                                    .font(T3.mono(12))
                                    .foregroundStyle(T3.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))

                                TextField("", text: $newSubcollectionDocId, prompt: Text("Doc ID (optional)").foregroundStyle(T3.textTertiary))
                                    .textFieldStyle(.plain)
                                    .font(T3.mono(12))
                                    .foregroundStyle(T3.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))
                            }
                            TextEditor(text: $newSubcollectionDocJSON)
                                .font(T3.mono(11.5))
                                .foregroundStyle(T3.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(height: 80)
                                .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 6))
                            HStack {
                                Spacer()
                                ActionPillButton(title: "Create Subcollection", systemImage: "checkmark", tint: T3.mint, isLoading: appState.isMutatingFirestore) {
                                    let sub = newSubcollectionName
                                    let subDocId = newSubcollectionDocId
                                    let subJSON = newSubcollectionDocJSON
                                    Task {
                                        await appState.createFirestoreCollectionAndDocument(
                                            collectionName: sub,
                                            parentDocumentPath: doc.relativePath,
                                            documentId: subDocId.isEmpty ? nil : subDocId,
                                            fieldsJSON: subJSON
                                        )
                                        newSubcollectionName = ""
                                        newSubcollectionDocId = ""
                                        showCreateSubcollection = false
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }

                    if !appState.firestoreDocSubcollections.isEmpty {
                        HStack(spacing: 8) {
                            Text("SUBCOLLECTIONS")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.7)
                                .foregroundStyle(T3.textTertiary)
                            ForEach(appState.firestoreDocSubcollections, id: \.self) { sub in
                                ActionPillButton(title: sub, systemImage: "folder.fill", tint: T3.amber) {
                                    Task { await appState.drillIntoDocumentSubcollection(document: doc, subcollection: sub) }
                                }
                            }
                        }
                    }

                    if editingJSON {
                        TextEditor(text: $docJSONDraft)
                            .font(T3.mono(12))
                            .foregroundStyle(T3.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(doc.fields.keys.sorted(), id: \.self) { key in
                                    if let val = doc.fields[key] {
                                        HStack(alignment: .top, spacing: 10) {
                                            Text(key)
                                                .font(T3.mono(12, weight: .semibold))
                                                .foregroundStyle(T3.sky)
                                                .frame(width: 130, alignment: .leading)
                                            TagPill(text: val.typeLabel, monospaced: true)
                                            Text(val.displayString)
                                                .font(T3.mono(12))
                                                .foregroundStyle(T3.textPrimary)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                            }
                            .padding(.bottom, 32)
                        }
                    }
                } else {
                    EmptyStateView(icon: "doc.text.magnifyingglass", title: "Select a document", message: "Choose a document to inspect fields, edit JSON, or browse subcollections.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var indexesView: some View {
        Group {
            if appState.firestoreIndexes.isEmpty {
                EmptyStateView(icon: "list.bullet.indent", title: "No composite indexes", message: "No composite indexes found in database \(appState.selectedFirestoreDatabaseId).")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.firestoreIndexes) { idx in
                            HStack(spacing: 12) {
                                StatusDot(color: idx.state == "READY" ? T3.mint : T3.amber, size: 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(idx.collectionGroup)
                                            .font(T3.mono(13, weight: .semibold))
                                            .foregroundStyle(T3.textPrimary)
                                        TagPill(text: idx.queryScope, color: T3.sky, monospaced: true)
                                        TagPill(text: idx.state, color: idx.state == "READY" ? T3.mint : T3.amber, monospaced: true)
                                    }
                                    FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 4) {
                                        ForEach(Array(idx.fields.enumerated()), id: \.offset) { _, f in
                                            TagPill(text: "\(f.fieldPath) (\(f.orderOrMode))", monospaced: true)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }
}
