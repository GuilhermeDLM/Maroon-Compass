import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in identity. Deliberately excludes email and name: the app never needs them.
struct AuthUser: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    /// Supabase anonymous user. Only created by Debug development sessions; never restorable.
    let isAnonymous: Bool
    let provider: String?
}

/// A Supabase Auth session. Stored only in the Keychain; its tokens are redacted from every
/// textual and reflected representation so they cannot reach logs.
struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    func needsRefresh(at now: Date, leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) <= leeway
    }
}

extension AuthSession: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var description: String {
        "AuthSession(user: \(user.id.uuidString), anonymous: \(user.isAnonymous), expiresAt: \(expiresAt), tokens: <redacted>)"
    }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["user": user, "expiresAt": expiresAt, "tokens": "<redacted>"], displayStyle: .struct)
    }
}

/// Persistent session storage. The app uses the Keychain; tests use memory.
protocol AuthSessionStore: Sendable {
    func load() throws -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear() throws
}

final class InMemoryAuthSessionStore: AuthSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AuthSession?

    init(_ session: AuthSession? = nil) { self.session = session }

    func load() throws -> AuthSession? { lock.withLock { session } }
    func save(_ session: AuthSession) throws { lock.withLock { self.session = session } }
    func clear() throws { lock.withLock { session = nil } }
}

enum CloudAuthError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case signedOut
    case offline
    case signInRejected
    case sessionExpired
    case developmentSessionsUnavailable
    case appleSignInUnavailable
    case rateLimited
    case storageFailed
    case server(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Cloud backup isn't set up in this build. Your schedule works fully on this device."
        case .signedOut: "Sign in to use cloud backup."
        case .offline: "You're offline. Nothing changed; try again when you're connected."
        case .signInRejected: "Sign-in was not accepted. Nothing changed on this device."
        case .sessionExpired: "Your cloud session ended. Sign in again; your schedule on this device is unchanged."
        case .developmentSessionsUnavailable: "Development sessions are only available in Debug builds."
        case .appleSignInUnavailable: "Sign in with Apple isn't enabled for this build yet."
        case .rateLimited: "Too many attempts. Wait a minute and try again."
        case .storageFailed: "The session couldn't be saved securely on this device."
        case .server: "The account service is unavailable. Your schedule on this device is unchanged."
        case .invalidResponse: "The account service sent an unexpected response."
        }
    }
}

/// Supabase Auth (GoTrue) and the account-deletion Edge Function over plain HTTPS.
struct SupabaseAuthClient: Sendable {
    let configuration: SupabaseConfiguration
    let transport: any HTTPTransport
    var now: @Sendable () -> Date = { Date() }

    static let deletionConfirmation = "delete-my-account"

    /// Native Sign in with Apple: exchanges Apple's identity token. `rawNonce` is the value whose
    /// SHA-256 digest was placed in the Apple authorization request.
    func signInWithApple(identityToken: String, rawNonce: String) async throws -> AuthSession {
        try await tokenGrant("id_token", body: ["provider": "apple", "id_token": identityToken, "nonce": rawNonce])
    }

    /// Anonymous Supabase user for Debug development sessions only.
    func signInAnonymously() async throws -> AuthSession {
        let request = try URLRequest.supabase(
            configuration.endpoint("auth/v1/signup"), method: "POST",
            configuration: configuration, json: [String: String]()
        )
        return try await session(from: request, rejection: .signInRejected)
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        try await tokenGrant("refresh_token", body: ["refresh_token": refreshToken], rejection: .sessionExpired)
    }

    /// Revokes this device's refresh token. An already-invalid session counts as signed out.
    func signOut(accessToken: String) async throws {
        let request = try URLRequest.supabase(
            configuration.endpoint("auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")]),
            method: "POST", configuration: configuration, accessToken: accessToken
        )
        let response = try await send(request).1
        switch response.statusCode {
        case 200...299, 401, 403, 404: return
        case 429: throw CloudAuthError.rateLimited
        default: throw CloudAuthError.server(response.statusCode)
        }
    }

    /// Deletes the Auth user through the `delete-account` Edge Function. Schedule rows cascade.
    func deleteAccount(accessToken: String) async throws {
        let request = try URLRequest.supabase(
            configuration.endpoint("functions/v1/delete-account"), method: "POST",
            configuration: configuration, accessToken: accessToken,
            json: ["confirmation": Self.deletionConfirmation]
        )
        let response = try await send(request).1
        switch response.statusCode {
        case 200...299: return
        case 401, 403: throw CloudAuthError.sessionExpired
        case 429: throw CloudAuthError.rateLimited
        default: throw CloudAuthError.server(response.statusCode)
        }
    }

    private func tokenGrant(
        _ grantType: String,
        body: [String: String],
        rejection: CloudAuthError = .signInRejected
    ) async throws -> AuthSession {
        let request = try URLRequest.supabase(
            configuration.endpoint("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grantType)]),
            method: "POST", configuration: configuration, json: body
        )
        return try await session(from: request, rejection: rejection)
    }

    private func session(from request: URLRequest, rejection: CloudAuthError) async throws -> AuthSession {
        let (data, response) = try await send(request)
        switch response.statusCode {
        case 200...299:
            break
        case 429:
            throw CloudAuthError.rateLimited
        case 400...499:
            throw rejection
        default:
            throw CloudAuthError.server(response.statusCode)
        }
        guard let payload = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !payload.accessToken.isEmpty, !payload.refreshToken.isEmpty else {
            throw CloudAuthError.invalidResponse
        }
        let expiresAt: Date
        if let absolute = payload.expiresAt {
            expiresAt = Date(timeIntervalSince1970: absolute)
        } else if let relative = payload.expiresIn {
            expiresAt = now().addingTimeInterval(relative)
        } else {
            throw CloudAuthError.invalidResponse
        }
        return AuthSession(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiresAt: expiresAt,
            user: AuthUser(
                id: payload.user.id,
                isAnonymous: payload.user.isAnonymous ?? false,
                provider: payload.user.appMetadata?.provider
            )
        )
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            if error.isConnectivityFailure { throw CloudAuthError.offline }
            throw CloudAuthError.server(0)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval?
        let expiresAt: TimeInterval?
        let user: User

        struct User: Decodable {
            let id: UUID
            let isAnonymous: Bool?
            let appMetadata: AppMetadata?

            struct AppMetadata: Decodable {
                let provider: String?
            }

            enum CodingKeys: String, CodingKey {
                case id
                case isAnonymous = "is_anonymous"
                case appMetadata = "app_metadata"
            }
        }

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }
}
