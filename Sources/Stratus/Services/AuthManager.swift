import Foundation
import AppKit
import AuthenticationServices
import CryptoKit
import Observation

struct PKCEHelper: Sendable {
    let codeVerifier: String
    let codeChallenge: String

    static func generate() -> PKCEHelper {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URLEncode(Data(bytes))
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = base64URLEncode(challengeData)
        return PKCEHelper(codeVerifier: verifier, codeChallenge: challenge)
    }

    static func s256Challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AuthError: LocalizedError, Sendable {
    case gcloudNotFound
    case gcloudFailed(String)
    case missingOAuthClientId
    case oauthCancelled
    case oauthFailed(String)
    case missingManualToken
    case demoModeActive

    var errorDescription: String? {
        switch self {
        case .gcloudNotFound:
            return "gcloud CLI not found. Install Google Cloud SDK or sign in with OAuth."
        case .gcloudFailed(let msg):
            return "gcloud authentication failed: \(msg)"
        case .missingOAuthClientId:
            return "Enter a Google OAuth 2.0 Desktop Client ID before signing in."
        case .oauthCancelled:
            return "Google sign-in was cancelled."
        case .oauthFailed(let msg):
            return "OAuth error: \(msg)"
        case .missingManualToken:
            return "No manual bearer token is configured."
        case .demoModeActive:
            return "Currently running in offline Demo Mode."
        }
    }
}

@MainActor
private final class WebAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

@MainActor
@Observable
final class AuthManager {
    var mode: AuthMode = .demo
    var account: AuthAccount = AuthAccount(
        email: "demo@stratus.local",
        mode: .demo,
        projectId: "prod-platform-core",
        gcloudPath: nil,
        expiresAt: nil
    )
    var detectedGcloudPath: String?
    var oauthClientId: String
    var billingExportTable: String
    var manualTokenInput: String
    var isAuthenticating = false
    var statusMessage: String?

    private var cachedGcloudToken: String?
    private var cachedGcloudExpiry: Date?
    private var activeWebAuthSession: ASWebAuthenticationSession?

    init() {
        self.oauthClientId = KeychainStore.shared.get(.oauthClientId) ?? ""
        self.billingExportTable = KeychainStore.shared.get(.billingExportTable) ?? ""
        self.manualTokenInput = KeychainStore.shared.get(.manualToken) ?? ""
        self.detectedGcloudPath = Self.locateGcloudBinary()
    }

    var isDemo: Bool { mode == .demo }

    /// Attempts silent connection via gcloud CLI or stored OAuth refresh token on startup.
    /// Falls back cleanly to Demo Mode if no live credentials are ready.
    func autoDetectOnLaunch() async {
        detectedGcloudPath = Self.locateGcloudBinary()

        if let savedOAuthRefresh = KeychainStore.shared.get(.oauthRefreshToken),
           !savedOAuthRefresh.isEmpty,
           !oauthClientId.isEmpty {
            do {
                _ = try await refreshOAuthTokenIfNeeded()
                let email = KeychainStore.shared.get(.oauthEmail) ?? "google-oauth-user"
                mode = .oauth
                account = AuthAccount(email: email, mode: .oauth, projectId: nil, gcloudPath: detectedGcloudPath, expiresAt: nil)
                statusMessage = "Connected via Google OAuth"
                return
            } catch {
                // Fall through to gcloud / demo
            }
        }

        if let gcloudPath = detectedGcloudPath {
            if let connected = await trySilentGcloudConnect(binaryPath: gcloudPath) {
                account = connected
                mode = .gcloud
                statusMessage = "Connected via gcloud CLI"
                return
            }
        }

        switchToDemo()
    }

    func switchToDemo() {
        mode = .demo
        account = AuthAccount(
            email: "demo@stratus.local",
            mode: .demo,
            projectId: "prod-platform-core",
            gcloudPath: detectedGcloudPath,
            expiresAt: nil
        )
        statusMessage = "Offline Demo Mode active"
    }

    func connectViaGcloud() async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }

        guard let binary = Self.locateGcloudBinary() else {
            throw AuthError.gcloudNotFound
        }
        detectedGcloudPath = binary

        let token = try await fetchGcloudToken(binaryPath: binary)
        let activeAccount = (try? await runCommand(binary, arguments: ["config", "get-value", "account"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultProject = (try? await runCommand(binary, arguments: ["config", "get-value", "project"]))?.trimmingCharacters(in: .whitespacesAndNewlines)

        cachedGcloudToken = token
        cachedGcloudExpiry = Date().addingTimeInterval(45 * 60)

        let email = (activeAccount?.isEmpty == false && activeAccount != "(unset)")
            ? activeAccount!
            : "gcloud-adc-user"
        let project = (defaultProject?.isEmpty == false && defaultProject != "(unset)") ? defaultProject : nil

        mode = .gcloud
        account = AuthAccount(
            email: email,
            mode: .gcloud,
            projectId: project,
            gcloudPath: binary,
            expiresAt: cachedGcloudExpiry
        )
        statusMessage = "Connected via gcloud CLI"
    }

    func connectWithManualToken(_ token: String) {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        manualTokenInput = cleaned
        KeychainStore.shared.set(cleaned, for: .manualToken)
        mode = .manualToken
        account = AuthAccount(
            email: "bearer-token-session",
            mode: .manualToken,
            projectId: nil,
            gcloudPath: detectedGcloudPath,
            expiresAt: nil
        )
        statusMessage = "Connected with manual Bearer token"
    }

    func saveOAuthAndBillingConfig(clientId: String, billingTable: String) {
        let trimmedId = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTable = billingTable.trimmingCharacters(in: .whitespacesAndNewlines)
        oauthClientId = trimmedId
        billingExportTable = trimmedTable
        if trimmedId.isEmpty {
            KeychainStore.shared.delete(.oauthClientId)
        } else {
            KeychainStore.shared.set(trimmedId, for: .oauthClientId)
        }
        if trimmedTable.isEmpty {
            KeychainStore.shared.delete(.billingExportTable)
        } else {
            KeychainStore.shared.set(trimmedTable, for: .billingExportTable)
        }
    }

    func signInWithOAuth() async throws {
        let trimmedClient = oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClient.isEmpty else {
            throw AuthError.missingOAuthClientId
        }
        KeychainStore.shared.set(trimmedClient, for: .oauthClientId)

        isAuthenticating = true
        defer { isAuthenticating = false }

        let pkce = PKCEHelper.generate()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClient),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.defaultRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/userinfo.email"),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            throw AuthError.oauthFailed("Invalid authorization URL")
        }

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: OAuthConfig.redirectScheme
            ) { url, error in
                if let error {
                    let nsErr = error as NSError
                    if nsErr.domain == ASWebAuthenticationSessionErrorDomain &&
                        nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.oauthCancelled)
                    } else {
                        continuation.resume(throwing: AuthError.oauthFailed(error.localizedDescription))
                    }
                    return
                }
                guard let url else {
                    continuation.resume(throwing: AuthError.oauthFailed("Missing callback URL"))
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = WebAuthPresentationContext.shared
            session.prefersEphemeralWebBrowserSession = false
            self.activeWebAuthSession = session
            if !session.start() {
                continuation.resume(throwing: AuthError.oauthFailed("Unable to start browser authentication session"))
            }
        }
        activeWebAuthSession = nil

        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
            let errParam = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "error" })?.value
            throw AuthError.oauthFailed(errParam ?? "Authorization code missing")
        }

        let tokenResponse = try await exchangeOAuthCode(
            code: code,
            clientId: trimmedClient,
            verifier: pkce.codeVerifier
        )

        persistOAuthToken(tokenResponse)
        let email = (try? await fetchUserEmail(accessToken: tokenResponse.accessToken)) ?? "google-oauth-user"
        KeychainStore.shared.set(email, for: .oauthEmail)

        mode = .oauth
        account = AuthAccount(
            email: email,
            mode: .oauth,
            projectId: nil,
            gcloudPath: detectedGcloudPath,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 3600))
        )
        statusMessage = "Signed in via Google OAuth"
    }

    func signOutOAuth() {
        KeychainStore.shared.delete(.oauthAccessToken)
        KeychainStore.shared.delete(.oauthRefreshToken)
        KeychainStore.shared.delete(.oauthExpiresAt)
        KeychainStore.shared.delete(.oauthEmail)
        KeychainStore.shared.delete(.manualToken)
        cachedGcloudToken = nil
        cachedGcloudExpiry = nil
        manualTokenInput = ""
        switchToDemo()
    }

    func validAccessToken() async throws -> String {
        switch mode {
        case .demo:
            throw AuthError.demoModeActive
        case .manualToken:
            guard !manualTokenInput.isEmpty else { throw AuthError.missingManualToken }
            return manualTokenInput
        case .oauth:
            return try await refreshOAuthTokenIfNeeded()
        case .gcloud:
            if let token = cachedGcloudToken,
               let expiry = cachedGcloudExpiry,
               expiry.timeIntervalSinceNow > 120 {
                return token
            }
            guard let binary = detectedGcloudPath ?? Self.locateGcloudBinary() else {
                throw AuthError.gcloudNotFound
            }
            let fresh = try await fetchGcloudToken(binaryPath: binary)
            cachedGcloudToken = fresh
            cachedGcloudExpiry = Date().addingTimeInterval(45 * 60)
            return fresh
        }
    }

    // MARK: - Private Helpers

    private func trySilentGcloudConnect(binaryPath: String) async -> AuthAccount? {
        do {
            let token = try await fetchGcloudToken(binaryPath: binaryPath)
            cachedGcloudToken = token
            cachedGcloudExpiry = Date().addingTimeInterval(45 * 60)
            let activeAccount = (try? await runCommand(binaryPath, arguments: ["config", "get-value", "account"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultProject = (try? await runCommand(binaryPath, arguments: ["config", "get-value", "project"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let email = (activeAccount?.isEmpty == false && activeAccount != "(unset)")
                ? activeAccount!
                : "gcloud-adc-user"
            let project = (defaultProject?.isEmpty == false && defaultProject != "(unset)") ? defaultProject : nil
            return AuthAccount(
                email: email,
                mode: .gcloud,
                projectId: project,
                gcloudPath: binaryPath,
                expiresAt: cachedGcloudExpiry
            )
        } catch {
            return nil
        }
    }

    private func fetchGcloudToken(binaryPath: String) async throws -> String {
        if let token = try? await runCommand(binaryPath, arguments: ["auth", "print-access-token"]),
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let adcToken = try? await runCommand(binaryPath, arguments: ["auth", "application-default", "print-access-token"]),
           !adcToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return adcToken.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let adcRefresh = try await refreshLocalADCFile() {
            return adcRefresh
        }
        throw AuthError.gcloudFailed("No active session. Run 'gcloud auth login' or sign in with OAuth.")
    }

    private func refreshLocalADCFile() async throws -> String? {
        let adcURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/gcloud/application_default_credentials.json")
        guard let data = try? Data(contentsOf: adcURL),
              let adc = try? JSONDecoder().decode(ADCFile.self, from: data),
              let clientId = adc.clientId,
              let refreshToken = adc.refreshToken else {
            return nil
        }
        var params = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        if let secret = adc.clientSecret {
            params["client_secret"] = secret
        }
        let resp = try await postFormToken(params: params)
        return resp.accessToken
    }

    private func exchangeOAuthCode(code: String, clientId: String, verifier: String) async throws -> OAuthTokenResponse {
        try await postFormToken(params: [
            "code": code,
            "client_id": clientId,
            "redirect_uri": OAuthConfig.defaultRedirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ])
    }

    private func refreshOAuthTokenIfNeeded() async throws -> String {
        if let existing = KeychainStore.shared.get(.oauthAccessToken),
           let expiryStr = KeychainStore.shared.get(.oauthExpiresAt),
           let epoch = Double(expiryStr),
           Date(timeIntervalSince1970: epoch).timeIntervalSinceNow > 120 {
            return existing
        }
        guard let refreshToken = KeychainStore.shared.get(.oauthRefreshToken),
              !refreshToken.isEmpty,
              !oauthClientId.isEmpty else {
            throw AuthError.oauthFailed("Session expired. Please sign in again.")
        }
        let refreshed = try await postFormToken(params: [
            "client_id": oauthClientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        persistOAuthToken(refreshed)
        return refreshed.accessToken
    }

    private func persistOAuthToken(_ token: OAuthTokenResponse) {
        KeychainStore.shared.set(token.accessToken, for: .oauthAccessToken)
        if let refresh = token.refreshToken, !refresh.isEmpty {
            KeychainStore.shared.set(refresh, for: .oauthRefreshToken)
        }
        let expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn ?? 3600)).timeIntervalSince1970
        KeychainStore.shared.set(String(expiresAt), for: .oauthExpiresAt)
    }

    private func postFormToken(params: [String: String]) async throws -> OAuthTokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "Unknown token error"
            throw AuthError.oauthFailed(text)
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private func fetchUserEmail(accessToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        struct UserInfo: Decodable { let email: String? }
        return try JSONDecoder().decode(UserInfo.self, from: data).email ?? "google-user"
    }

    static func locateGcloudBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            "\(home)/google-cloud-sdk/bin/gcloud",
            "/opt/homebrew/share/google-cloud-sdk/bin/gcloud"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private func runCommand(_ executable: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            // Ensure PATH includes Homebrew so python3 / gcloud helpers work in bundled .app launches
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus != 0 {
                let errMsg = String(data: errData, encoding: .utf8) ?? "Exit code \(process.terminationStatus)"
                throw AuthError.gcloudFailed(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return String(data: outData, encoding: .utf8) ?? ""
        }.value
    }
}
