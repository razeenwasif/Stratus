import Foundation

enum AuthMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case gcloud
    case oauth
    case manualToken
    case demo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gcloud: return "gcloud CLI"
        case .oauth: return "Google OAuth"
        case .manualToken: return "Bearer Token"
        case .demo: return "Demo Mode"
        }
    }
}

struct AuthAccount: Sendable, Hashable {
    var email: String
    var mode: AuthMode
    var projectId: String?
    var gcloudPath: String?
    var expiresAt: Date?
}

struct OAuthConfig: Sendable, Hashable {
    static let defaultRedirectURI = "com.stratus.gcp:/oauth2redirect"
    static let redirectScheme = "com.stratus.gcp"

    var clientId: String
    var redirectURI: String
    var billingExportTable: String
}

struct OAuthTokenResponse: Sendable, Codable {
    let accessToken: String
    let expiresIn: Int?
    let refreshToken: String?
    let tokenType: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
    }
}

struct ADCFile: Sendable, Codable {
    let clientId: String?
    let clientSecret: String?
    let refreshToken: String?
    let type: String?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case refreshToken = "refresh_token"
        case type
    }
}
