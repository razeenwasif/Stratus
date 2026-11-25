import SwiftUI

struct AuthSettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: AuthMode = .gcloud
    @State private var clientIdText = ""
    @State private var billingTableText = ""
    @State private var bearerTokenText = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Google Cloud Connection")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(T3.textPrimary)
                    Text("Authenticate via local gcloud CLI, native OAuth 2.0, or explore in Demo Mode.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(T3.textMuted)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(T3.textSecondary)
                        .padding(7)
                        .background(T3.surfaceHover, in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ForEach(AuthMode.allCases) { mode in
                    FilterPillButton(title: mode.displayName, isSelected: selectedTab == mode) {
                        selectedTab = mode
                        errorMessage = nil
                    }
                }
            }

            Group {
                switch selectedTab {
                case .gcloud:
                    gcloudPanel
                case .oauth:
                    oauthPanel
                case .manualToken:
                    manualTokenPanel
                case .demo:
                    demoPanel
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(T3.rose)
            }

            // Optional BigQuery Billing Export Table for exact invoice spend in Overview
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("BIGQUERY BILLING EXPORT TABLE (OPTIONAL · EXACT INVOICE SPEND)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(T3.textTertiary)
                    Spacer()
                    Button("Save") {
                        appState.auth.saveOAuthAndBillingConfig(clientId: clientIdText, billingTable: billingTableText)
                        appState.showToast("Saved billing export table")
                        Task { await appState.refreshOverview() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(T3.sky)
                }

                TextField("", text: $billingTableText, prompt: Text("my-billing-project.billing_export.gcp_billing_export_v1_XXXXXX").foregroundStyle(T3.textTertiary))
                    .textFieldStyle(.plain)
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.textPrimary)
                    .padding(10)
                    .background(T3.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                StatusDot(color: appState.auth.isDemo ? T3.indigo : T3.mint, size: 6)
                Text("Active: \(appState.auth.mode.displayName) (\(appState.auth.account.email))")
                    .font(T3.mono(11.5))
                    .foregroundStyle(T3.textSecondary)
                Spacer()
                ActionPillButton(title: "Done", tint: T3.textPrimary) {
                    dismiss()
                }
            }
        }
        .padding(28)
        .frame(width: 580)
        .background(T3.bgSheet)
        .onAppear {
            selectedTab = appState.auth.mode
            clientIdText = appState.auth.oauthClientId
            billingTableText = appState.auth.billingExportTable
            bearerTokenText = appState.auth.manualTokenInput
        }
    }

    private var gcloudPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Auto-detects your local Google Cloud SDK session (`gcloud auth print-access-token` and Application Default Credentials).")
                .font(.system(size: 12.5))
                .foregroundStyle(T3.textSecondary)

            HStack {
                Text("CLI Binary")
                    .font(.system(size: 12))
                    .foregroundStyle(T3.textTertiary)
                Spacer()
                Text(appState.auth.detectedGcloudPath ?? "Not found in standard paths")
                    .font(T3.mono(11.5))
                    .foregroundStyle(appState.auth.detectedGcloudPath != nil ? T3.mint : T3.amber)
            }

            ActionPillButton(
                title: "Connect via gcloud CLI",
                systemImage: "terminal.fill",
                tint: T3.mint,
                isLoading: appState.auth.isAuthenticating
            ) {
                errorMessage = nil
                Task {
                    do {
                        try await appState.auth.connectViaGcloud()
                        await appState.reconnectAndReload()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private var oauthPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in natively via ASWebAuthenticationSession with PKCE. Create an OAuth Desktop/iOS Client ID in Google Cloud Console and add the redirect URI below.")
                .font(.system(size: 12))
                .foregroundStyle(T3.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("OAUTH CLIENT ID")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(T3.textTertiary)
                TextField("", text: $clientIdText, prompt: Text("1234567890-xxxx.apps.googleusercontent.com").foregroundStyle(T3.textTertiary))
                    .textFieldStyle(.plain)
                    .font(T3.mono(12))
                    .foregroundStyle(T3.textPrimary)
                    .padding(10)
                    .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Text("Redirect URI:")
                    .font(.system(size: 11.5))
                    .foregroundStyle(T3.textTertiary)
                Text(OAuthConfig.defaultRedirectURI)
                    .font(T3.mono(11))
                    .foregroundStyle(T3.sky)
                Spacer()
                Button("Copy") {
                    appState.copyToClipboard(OAuthConfig.defaultRedirectURI, label: "Redirect URI")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(T3.textSecondary)
            }

            HStack(spacing: 10) {
                ActionPillButton(
                    title: "Sign in with Google",
                    systemImage: "person.badge.key.fill",
                    tint: T3.indigo,
                    isLoading: appState.auth.isAuthenticating
                ) {
                    errorMessage = nil
                    appState.auth.saveOAuthAndBillingConfig(clientId: clientIdText, billingTable: billingTableText)
                    Task {
                        do {
                            try await appState.auth.signInWithOAuth()
                            await appState.reconnectAndReload()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                if appState.auth.mode == .oauth {
                    ActionPillButton(title: "Sign Out", tint: T3.rose) {
                        appState.auth.signOutOAuth()
                        Task { await appState.reconnectAndReload() }
                    }
                }
            }
        }
    }

    private var manualTokenPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a short-lived OAuth2 Bearer access token (stored in macOS Keychain).")
                .font(.system(size: 12.5))
                .foregroundStyle(T3.textSecondary)

            SecureField("ya29.a0AfB_by...", text: $bearerTokenText)
                .textFieldStyle(.plain)
                .font(T3.mono(12))
                .foregroundStyle(T3.textPrimary)
                .padding(10)
                .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 8))

            ActionPillButton(title: "Use Access Token", systemImage: "checkmark.circle", tint: T3.sky) {
                appState.auth.connectWithManualToken(bearerTokenText)
                Task {
                    await appState.reconnectAndReload()
                    dismiss()
                }
            }
        }
    }

    private var demoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Explore Stratus with realistic sample infrastructure, daily spend charts, Compute VMs, Cloud Run services, GCS buckets, BigQuery results, and Cloud Logging without connecting a live GCP account.")
                .font(.system(size: 12.5))
                .foregroundStyle(T3.textSecondary)

            ActionPillButton(title: "Activate Demo Mode", systemImage: "sparkles", tint: T3.indigo) {
                Task {
                    await appState.switchToDemoMode()
                    dismiss()
                }
            }
        }
    }
}
