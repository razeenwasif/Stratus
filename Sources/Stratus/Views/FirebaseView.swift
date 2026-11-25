import SwiftUI
import AppKit

struct FirebaseView: View {
    @Environment(AppState.self) private var appState

    // Auth creation & search state
    @State private var authSearch = ""
    @State private var showCreateUser = false
    @State private var newUserEmail = ""
    @State private var newUserPassword = ""
    @State private var newUserName = ""
    @State private var confirmDeleteUID: String?

    // Remote Config editor state
    @State private var editingRemoteConfig = false
    @State private var remoteConfigDraft = ""

    // RTDB state
    @State private var rtdbPathInput = "/"
    @State private var rtdbEditing = false
    @State private var rtdbDraft = ""
    @State private var confirmDeleteRTDB = false

    @State private var hoveredId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Firebase")
                        .font(T3.pageTitle())
                        .foregroundStyle(T3.textPrimary)
                    Text("\(appState.selectedProject?.projectId ?? "") · Apps, Auth, Hosting, Rules, Remote Config & RTDB")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                HStack(spacing: 4) {
                    ForEach(FirebaseSubTab.allCases) { tab in
                        FilterPillButton(title: tab.title, isSelected: appState.selectedFirebaseTab == tab) {
                            appState.selectedFirebaseTab = tab
                            Task { await appState.refreshFirebaseSection() }
                        }
                    }
                }

                ActionPillButton(title: "Refresh", systemImage: "arrow.clockwise") {
                    Task { await appState.refreshFirebaseSection() }
                }
            }

            switch appState.selectedFirebaseTab {
            case .apps:
                appsView
            case .auth:
                authView
            case .hosting:
                hostingView
            case .rules:
                rulesView
            case .remoteConfig:
                remoteConfigView
            case .realtimeDB:
                realtimeDBView
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .background(T3.bg)
    }

    // MARK: - Project & Apps

    private var appsView: some View {
        Group {
            if appState.isLoadingFirebaseApps && appState.firebaseApps.isEmpty && appState.firebaseProjectInfo == nil {
                ProgressView("Loading Firebase project & apps...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.firebaseAppsError, appState.firebaseApps.isEmpty && appState.firebaseProjectInfo == nil {
                EmptyStateView(icon: "flame", title: "Firebase unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshFirebaseApps() }
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let proj = appState.firebaseProjectInfo {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("FIREBASE PROJECT")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(0.8)
                                    .foregroundStyle(T3.textTertiary)

                                HStack(spacing: 28) {
                                    MetricStatColumn(
                                        label: "Project",
                                        value: proj.displayName,
                                        subtitle: "Number \(proj.projectNumber.isEmpty ? "-" : proj.projectNumber)"
                                    )
                                    MetricStatColumn(
                                        label: "Default Hosting",
                                        value: proj.defaultHostingSite ?? "-",
                                        subtitle: proj.locationId ?? "default"
                                    )
                                    MetricStatColumn(
                                        label: "Storage Bucket",
                                        value: proj.defaultStorageBucket ?? "-",
                                        subtitle: proj.state
                                    )
                                    MetricStatColumn(
                                        label: "Realtime DB",
                                        value: proj.defaultRealtimeDatabaseInstance ?? "-",
                                        subtitle: "\(appState.firebaseApps.count) registered apps"
                                    )
                                }
                                .padding(16)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("REGISTERED APPS (\(appState.firebaseApps.count))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)

                            if appState.firebaseApps.isEmpty {
                                Text("No Web, iOS, or Android apps registered in this Firebase project.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(T3.textTertiary)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(appState.firebaseApps) { app in
                                        let isSelected = appState.selectedFirebaseAppConfig?.appId == app.appId
                                        let isHovered = hoveredId == app.id
                                        HStack(spacing: 12) {
                                            Image(systemName: app.platform.icon)
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color(hexString: app.platform.colorHex))
                                                .frame(width: 22)

                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 8) {
                                                    Text(app.displayName)
                                                        .font(.system(size: 13.5, weight: .semibold))
                                                        .foregroundStyle(T3.textPrimary)
                                                    TagPill(text: app.platform.title, color: Color(hexString: app.platform.colorHex), monospaced: true)
                                                    if let bundle = app.bundleOrPackageId {
                                                        TagPill(text: bundle, monospaced: true)
                                                    }
                                                }
                                                Text(app.appId)
                                                    .font(T3.mono(11))
                                                    .foregroundStyle(T3.textTertiary)
                                            }

                                            Spacer()

                                            ActionPillButton(title: "SDK Config", systemImage: "doc.text", tint: T3.sky) {
                                                Task { await appState.loadFirebaseAppConfig(app) }
                                            }
                                            ActionPillButton(title: "Copy App ID", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                                                appState.copyToClipboard(app.appId, label: "App ID")
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
                                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        )
                                        .contentShape(Rectangle())
                                        .onHover { hoveredId = $0 ? app.id : nil }
                                        .onTapGesture {
                                            Task { await appState.loadFirebaseAppConfig(app) }
                                        }
                                    }
                                }
                            }
                        }

                        if let cfg = appState.selectedFirebaseAppConfig {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("SDK CONFIGURATION · \(cfg.filename)")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .tracking(0.8)
                                        .foregroundStyle(T3.textTertiary)
                                    Spacer()
                                    ActionPillButton(title: "Copy \(cfg.filename)", systemImage: "doc.on.doc", tint: T3.mint) {
                                        appState.copyToClipboard(cfg.rawContent, label: cfg.filename)
                                    }
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(cfg.rawContent)
                                        .font(T3.mono(11.5))
                                        .foregroundStyle(T3.textPrimary)
                                        .textSelection(.enabled)
                                        .padding(14)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Firebase Authentication

    private var authView: some View {
        let q = authSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = appState.firebaseAuthUsers.filter { user in
            q.isEmpty
                || (user.email ?? "").lowercased().contains(q)
                || (user.displayName ?? "").lowercased().contains(q)
                || user.localId.lowercased().contains(q)
        }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BorderlessSearchField(text: $authSearch, placeholder: "Search users by email, name, or UID...", width: 320)
                Spacer()
                Text("\(filtered.count) users")
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.textTertiary)
                ActionPillButton(
                    title: showCreateUser ? "Cancel" : "New User",
                    systemImage: showCreateUser ? "xmark" : "person.badge.plus",
                    tint: showCreateUser ? T3.textSecondary : T3.mint
                ) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        showCreateUser.toggle()
                    }
                }
            }

            if showCreateUser {
                HStack(spacing: 10) {
                    TextField("", text: $newUserEmail, prompt: Text("user@domain.com").foregroundStyle(T3.textTertiary))
                        .textFieldStyle(.plain)
                        .font(T3.mono(12))
                        .foregroundStyle(T3.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 7))

                    SecureField("", text: $newUserPassword, prompt: Text("Password (min 6 chars)").foregroundStyle(T3.textTertiary))
                        .textFieldStyle(.plain)
                        .font(T3.mono(12))
                        .foregroundStyle(T3.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 7))

                    TextField("", text: $newUserName, prompt: Text("Display name (optional)").foregroundStyle(T3.textTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 7))

                    ActionPillButton(title: "Create", systemImage: "checkmark", tint: T3.mint) {
                        let email = newUserEmail
                        let pw = newUserPassword
                        let name = newUserName
                        Task {
                            await appState.createFirebaseAuthUser(email: email, password: pw, displayName: name)
                            newUserEmail = ""
                            newUserPassword = ""
                            newUserName = ""
                            showCreateUser = false
                        }
                    }
                }
                .padding(12)
                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if appState.isLoadingFirebaseAuth && appState.firebaseAuthUsers.isEmpty {
                ProgressView("Loading Firebase Auth users...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.firebaseAuthError, appState.firebaseAuthUsers.isEmpty {
                EmptyStateView(icon: "person.2", title: "Firebase Auth unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshFirebaseAuth() }
                }
            } else if filtered.isEmpty {
                EmptyStateView(icon: "person.2", title: "No users found", message: "No Firebase Authentication accounts match the current filter.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { user in
                            let isHovered = hoveredId == user.id
                            let isBusy = appState.busyFirebaseAuthUIDs.contains(user.localId)
                            HStack(spacing: 12) {
                                StatusDot(color: user.disabled ? T3.rose : T3.mint, size: 6)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(user.email ?? user.phoneNumber ?? user.localId)
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(T3.textPrimary)
                                        if let name = user.displayName, !name.isEmpty {
                                            Text(name)
                                                .font(.system(size: 12))
                                                .foregroundStyle(T3.textSecondary)
                                        }
                                        ForEach(user.providers, id: \.self) { p in
                                            TagPill(text: p, color: T3.sky, monospaced: true)
                                        }
                                        if user.emailVerified {
                                            TagPill(text: "verified", color: T3.mint, monospaced: true)
                                        }
                                        if user.disabled {
                                            TagPill(text: "disabled", color: T3.rose, monospaced: true)
                                        }
                                    }

                                    HStack(spacing: 12) {
                                        Text("UID: \(user.localId)")
                                            .font(T3.mono(11))
                                            .foregroundStyle(T3.textTertiary)
                                        if let lastLogin = user.lastLoginAt {
                                            Text("Last login \(Formatters.relativeDate(lastLogin))")
                                                .font(.system(size: 11))
                                                .foregroundStyle(T3.textTertiary)
                                        }
                                    }
                                }

                                Spacer()

                                if isHovered || isBusy || confirmDeleteUID == user.localId {
                                    ActionPillButton(title: "Copy UID", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                                        appState.copyToClipboard(user.localId, label: "UID")
                                    }
                                    ActionPillButton(
                                        title: user.disabled ? "Enable" : "Disable",
                                        systemImage: user.disabled ? "checkmark.circle" : "nosign",
                                        tint: user.disabled ? T3.mint : T3.amber,
                                        isLoading: isBusy
                                    ) {
                                        Task { await appState.toggleFirebaseAuthUserDisabled(user) }
                                    }
                                    if confirmDeleteUID == user.localId {
                                        ActionPillButton(title: "Confirm Delete", systemImage: "trash", tint: T3.rose, isLoading: isBusy) {
                                            confirmDeleteUID = nil
                                            Task { await appState.deleteFirebaseAuthUser(user) }
                                        }
                                    } else {
                                        ActionPillButton(title: "Delete", systemImage: "trash", tint: T3.rose) {
                                            confirmDeleteUID = user.localId
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                isHovered ? T3.surfaceHover : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .onHover { hoveredId = $0 ? user.id : nil }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Firebase Hosting

    private var hostingView: some View {
        Group {
            if appState.isLoadingFirebaseHosting && appState.firebaseHostingSites.isEmpty {
                ProgressView("Loading Firebase Hosting sites...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.firebaseHostingError, appState.firebaseHostingSites.isEmpty {
                EmptyStateView(icon: "globe", title: "Firebase Hosting unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshFirebaseHosting() }
                }
            } else if appState.firebaseHostingSites.isEmpty {
                EmptyStateView(icon: "globe", title: "No Hosting sites", message: "No Firebase Hosting sites configured in this project.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 8) {
                            ForEach(appState.firebaseHostingSites) { site in
                                FilterPillButton(
                                    title: site.siteId,
                                    isSelected: appState.selectedHostingSite?.siteId == site.siteId
                                ) {
                                    Task { await appState.selectFirebaseHostingSite(site) }
                                }
                            }
                            Spacer()
                            if let site = appState.selectedHostingSite {
                                Text(site.defaultUrl)
                                    .font(T3.mono(11.5))
                                    .foregroundStyle(T3.sky)
                                ActionPillButton(title: "Open", systemImage: "arrow.up.right", tint: T3.sky) {
                                    if let url = URL(string: site.defaultUrl) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("RELEASES (\(appState.firebaseHostingReleases.count))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)

                            if appState.firebaseHostingReleases.isEmpty {
                                Text("No releases yet for this site.")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(T3.textTertiary)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(appState.firebaseHostingReleases) { rel in
                                        HStack(spacing: 12) {
                                            StatusDot(color: rel.status == "FINALIZED" || rel.status == "DEPLOYED" ? T3.mint : T3.amber, size: 6)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 8) {
                                                    Text(rel.versionId)
                                                        .font(T3.mono(12.5, weight: .semibold))
                                                        .foregroundStyle(T3.textPrimary)
                                                    TagPill(text: rel.status, color: T3.mint, monospaced: true)
                                                    if let email = rel.releaseUserEmail {
                                                        Text(email)
                                                            .font(T3.mono(11))
                                                            .foregroundStyle(T3.textTertiary)
                                                    }
                                                }
                                                Text(rel.message)
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(T3.textSecondary)
                                            }
                                            Spacer()
                                            if let time = rel.releaseTime {
                                                Text(Formatters.relativeDate(time))
                                                    .font(.system(size: 11.5))
                                                    .foregroundStyle(T3.textTertiary)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("CHANNELS (\(appState.firebaseHostingChannels.count))")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(T3.textTertiary)

                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(appState.firebaseHostingChannels) { chan in
                                    HStack(spacing: 12) {
                                        Image(systemName: "arrow.triangle.branch")
                                            .font(.system(size: 12))
                                            .foregroundStyle(chan.channelId == "live" ? T3.mint : T3.indigo)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 8) {
                                                Text(chan.channelId)
                                                    .font(T3.mono(12.5, weight: .semibold))
                                                    .foregroundStyle(T3.textPrimary)
                                                if let expires = chan.expireTime {
                                                    TagPill(text: "expires \(Formatters.relativeDate(expires))", color: T3.amber, monospaced: true)
                                                } else {
                                                    TagPill(text: "production", color: T3.mint, monospaced: true)
                                                }
                                            }
                                            Text(chan.url)
                                                .font(T3.mono(11))
                                                .foregroundStyle(T3.sky)
                                        }
                                        Spacer()
                                        if let url = URL(string: chan.url), !chan.url.isEmpty {
                                            ActionPillButton(title: "Open", systemImage: "arrow.up.right", tint: T3.sky) {
                                                NSWorkspace.shared.open(url)
                                            }
                                        }
                                        ActionPillButton(title: "Copy URL", systemImage: "doc.on.doc", tint: T3.textSecondary) {
                                            appState.copyToClipboard(chan.url, label: "channel URL")
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    // MARK: - Firebase Security Rules

    private var rulesView: some View {
        Group {
            if appState.isLoadingFirebaseRules && appState.firebaseRulesReleases.isEmpty {
                ProgressView("Loading Firebase Security Rules...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.firebaseRulesError, appState.firebaseRulesReleases.isEmpty {
                EmptyStateView(icon: "lock.doc", title: "Security Rules unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshFirebaseRules() }
                }
            } else if appState.firebaseRulesReleases.isEmpty {
                EmptyStateView(icon: "lock.doc", title: "No Security Rules releases", message: "No Firestore or Storage rules releases deployed in this project.")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(appState.firebaseRulesReleases) { rel in
                            FilterPillButton(
                                title: rel.shortName,
                                isSelected: appState.selectedRulesRelease?.name == rel.name
                            ) {
                                Task { await appState.selectFirebaseRulesRelease(rel) }
                            }
                        }
                        Spacer()
                        if let ruleset = appState.activeFirebaseRuleset {
                            Text("Ruleset \(ruleset.shortId)")
                                .font(T3.mono(11))
                                .foregroundStyle(T3.textTertiary)
                        }
                    }

                    if let ruleset = appState.activeFirebaseRuleset {
                        if ruleset.files.isEmpty {
                            EmptyStateView(icon: "doc.text", title: "Empty ruleset", message: "Ruleset \(ruleset.shortId) contains no source files.")
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(ruleset.files) { file in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(file.name)
                                                    .font(T3.mono(12, weight: .semibold))
                                                    .foregroundStyle(T3.amber)
                                                Spacer()
                                                ActionPillButton(title: "Copy Rules", systemImage: "doc.on.doc", tint: T3.mint) {
                                                    appState.copyToClipboard(file.content, label: file.name)
                                                }
                                            }
                                            Text(file.content)
                                                .font(T3.mono(12))
                                                .foregroundStyle(T3.textPrimary)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(14)
                                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                    }
                                }
                                .padding(.bottom, 32)
                            }
                        }
                    } else {
                        EmptyStateView(icon: "lock.doc", title: "No ruleset loaded", message: "Select a rules release above to inspect its source rules.")
                    }
                }
            }
        }
    }

    // MARK: - Firebase Remote Config

    private var remoteConfigView: some View {
        Group {
            if appState.isLoadingFirebaseRemoteConfig && appState.firebaseRemoteConfig == nil {
                ProgressView("Loading Firebase Remote Config...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.firebaseRemoteConfigError, appState.firebaseRemoteConfig == nil {
                EmptyStateView(icon: "slider.horizontal.3", title: "Remote Config unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshFirebaseRemoteConfig() }
                }
            } else if let tpl = appState.firebaseRemoteConfig {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            TagPill(text: "v\(tpl.versionNumber)", color: T3.indigo, monospaced: true)
                            if let email = tpl.updateUserEmail {
                                Text("by \(email)")
                                    .font(T3.mono(11))
                                    .foregroundStyle(T3.textTertiary)
                            }
                            Spacer()
                            FilterPillButton(title: editingRemoteConfig ? "Parameters" : "Edit JSON", isSelected: editingRemoteConfig) {
                                if !editingRemoteConfig {
                                    remoteConfigDraft = tpl.rawJSON
                                }
                                editingRemoteConfig.toggle()
                            }
                            if editingRemoteConfig {
                                ActionPillButton(
                                    title: "Publish",
                                    systemImage: "paperplane.fill",
                                    tint: T3.mint,
                                    isLoading: appState.isPublishingRemoteConfig
                                ) {
                                    Task {
                                        await appState.publishFirebaseRemoteConfig(rawJSON: remoteConfigDraft)
                                        editingRemoteConfig = false
                                    }
                                }
                            }
                        }

                        if editingRemoteConfig {
                            TextEditor(text: $remoteConfigDraft)
                                .font(T3.mono(12))
                                .foregroundStyle(T3.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            ScrollView(.vertical, showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(tpl.parameters) { param in
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 8) {
                                                    Text(param.key)
                                                        .font(T3.mono(12.5, weight: .semibold))
                                                        .foregroundStyle(T3.textPrimary)
                                                    TagPill(text: param.valueType, color: T3.sky, monospaced: true)
                                                }
                                                if !param.description.isEmpty {
                                                    Text(param.description)
                                                        .font(.system(size: 11.5))
                                                        .foregroundStyle(T3.textMuted)
                                                }
                                            }
                                            Spacer()
                                            Text(param.defaultValue)
                                                .font(T3.mono(12))
                                                .foregroundStyle(T3.mint)
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .padding(.bottom, 32)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("VERSION HISTORY")
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(T3.textTertiary)

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(appState.firebaseRemoteConfigVersions) { ver in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text("v\(ver.versionNumber)")
                                                .font(T3.mono(12, weight: .semibold))
                                                .foregroundStyle(T3.textPrimary)
                                            if ver.isRollback {
                                                TagPill(text: "rollback", color: T3.amber, monospaced: true)
                                            }
                                            Spacer()
                                            if let time = ver.updateTime {
                                                Text(Formatters.relativeDate(time))
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(T3.textTertiary)
                                            }
                                        }
                                        if let desc = ver.description, !desc.isEmpty {
                                            Text(desc)
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(T3.textSecondary)
                                        }
                                        if let email = ver.updateUserEmail {
                                            Text(email)
                                                .font(T3.mono(10.5))
                                                .foregroundStyle(T3.textTertiary)
                                        }
                                    }
                                    .padding(10)
                                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                    .frame(width: 260)
                }
            } else {
                EmptyStateView(icon: "slider.horizontal.3", title: "Remote Config", message: "Refresh to load Remote Config template.")
            }
        }
    }

    // MARK: - Realtime Database

    private var realtimeDBView: some View {
        Group {
            if appState.isLoadingRealtimeDB && appState.realtimeDBInstances.isEmpty {
                ProgressView("Loading Realtime Database instances...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = appState.realtimeDBError, appState.realtimeDBInstances.isEmpty {
                EmptyStateView(icon: "bolt.circle", title: "Realtime Database unavailable", message: err, actionTitle: "Retry") {
                    Task { await appState.refreshRealtimeDB() }
                }
            } else if appState.realtimeDBInstances.isEmpty {
                EmptyStateView(icon: "bolt.circle", title: "No Realtime Database instances", message: "No RTDB instances provisioned in this project.")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach(appState.realtimeDBInstances) { inst in
                            FilterPillButton(
                                title: inst.instanceId,
                                isSelected: appState.selectedRealtimeDB?.instanceId == inst.instanceId
                            ) {
                                appState.selectedRealtimeDB = inst
                                Task { await appState.loadRealtimeDBNode(path: rtdbPathInput, shallow: appState.realtimeDBShallow) }
                            }
                        }
                        Spacer()
                        if let inst = appState.selectedRealtimeDB {
                            Text(inst.databaseUrl)
                                .font(T3.mono(11))
                                .foregroundStyle(T3.sky)
                        }
                    }

                    HStack(spacing: 10) {
                        TextField("", text: $rtdbPathInput, prompt: Text("/path/to/node").foregroundStyle(T3.textTertiary))
                            .textFieldStyle(.plain)
                            .font(T3.mono(12.5))
                            .foregroundStyle(T3.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .onSubmit {
                                Task { await appState.loadRealtimeDBNode(path: rtdbPathInput, shallow: appState.realtimeDBShallow) }
                            }

                        FilterPillButton(title: "Shallow", isSelected: appState.realtimeDBShallow) {
                            let next = !appState.realtimeDBShallow
                            Task { await appState.loadRealtimeDBNode(path: rtdbPathInput, shallow: next) }
                        }

                        ActionPillButton(title: "Read", systemImage: "arrow.down.circle", tint: T3.sky) {
                            Task { await appState.loadRealtimeDBNode(path: rtdbPathInput, shallow: appState.realtimeDBShallow) }
                        }

                        FilterPillButton(title: rtdbEditing ? "Cancel Edit" : "Edit JSON", isSelected: rtdbEditing) {
                            if !rtdbEditing {
                                rtdbDraft = appState.realtimeDBPayload
                            }
                            rtdbEditing.toggle()
                        }

                        if rtdbEditing {
                            ActionPillButton(title: "Save (PUT)", systemImage: "checkmark", tint: T3.mint, isLoading: appState.isMutatingRealtimeDB) {
                                Task {
                                    await appState.writeRealtimeDBNode(path: rtdbPathInput, rawJSON: rtdbDraft)
                                    rtdbEditing = false
                                }
                            }
                        } else if rtdbPathInput != "/" && !rtdbPathInput.isEmpty {
                            if confirmDeleteRTDB {
                                ActionPillButton(title: "Confirm Delete", systemImage: "trash", tint: T3.rose, isLoading: appState.isMutatingRealtimeDB) {
                                    confirmDeleteRTDB = false
                                    Task {
                                        await appState.deleteRealtimeDBNode(path: rtdbPathInput)
                                        rtdbPathInput = "/"
                                    }
                                }
                            } else {
                                ActionPillButton(title: "Delete Node", systemImage: "trash", tint: T3.rose) {
                                    confirmDeleteRTDB = true
                                }
                            }
                        }
                    }
                    .onChange(of: appState.realtimeDBPath) { _, newPath in
                        if rtdbPathInput != newPath {
                            rtdbPathInput = newPath
                        }
                        confirmDeleteRTDB = false
                    }
                    .onChange(of: rtdbPathInput) { _, _ in
                        confirmDeleteRTDB = false
                    }

                    if rtdbEditing {
                        TextEditor(text: $rtdbDraft)
                            .font(T3.mono(12.5))
                            .foregroundStyle(T3.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(appState.realtimeDBPayload.isEmpty ? "null" : appState.realtimeDBPayload)
                                .font(T3.mono(12.5))
                                .foregroundStyle(T3.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.bottom, 32)
                        }
                    }
                }
            }
        }
    }
}
