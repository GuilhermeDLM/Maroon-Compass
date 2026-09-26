import Auth
import Foundation
import Observation

enum CloudAccountError: LocalizedError {
    case notConfigured
    case deletionFailed(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google sign-in needs a Supabase project and public project key. Your local schedule is available."
        case .deletionFailed: "The cloud account could not be deleted. Your local schedule was kept."
        }
    }
}

@MainActor
@Observable
final class CloudAccountStore {
    static let callbackURL = URL(string: "marooncompass://auth/callback")!

    private let configuration: SupabaseConfiguration?
    @ObservationIgnored private let auth: AuthClient?

    private(set) var email: String?
    private(set) var isSignedIn = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    var isConfigured: Bool { auth != nil }

    init(configuration: SupabaseConfiguration? = SupabaseConfiguration.fromBundle()) {
        self.configuration = configuration
        if let configuration {
            auth = AuthClient(
                url: configuration.projectURL.appending(path: "auth/v1"),
                headers: ["apikey": configuration.publishableKey],
                flowType: .pkce,
                redirectToURL: Self.callbackURL,
                storageKey: "maroon-compass-supabase-session",
                localStorage: KeychainLocalStorage(service: "com.guilhermemachado.MaroonCompass.auth")
            )
        } else {
            auth = nil
        }
        updateDisplayFromCachedSession()
    }

    func refresh() async {
        guard let auth else { return }
        updateDisplayFromCachedSession()
        // A cached session can be expired. The SDK refreshes it before a cloud operation.
        do { updateDisplay(try await auth.session) }
        catch { updateDisplayFromCachedSession() }
    }

    func signInWithGoogle() async {
        guard let auth else { errorMessage = CloudAccountError.notConfigured.localizedDescription; return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let session = try await auth.signInWithOAuth(
                provider: .google,
                redirectTo: Self.callbackURL,
                scopes: "openid email profile"
            )
            updateDisplay(session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        guard let auth else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await auth.signOut(scope: .local)
            updateDisplay(nil)
        } catch {
            updateDisplayFromCachedSession()
            errorMessage = error.localizedDescription
        }
    }

    func accessToken() async throws -> String {
        guard let auth else { throw CloudAccountError.notConfigured }
        return try await auth.session.accessToken
    }

    func deleteCloudAccount() async {
        guard let auth, let configuration else {
            errorMessage = CloudAccountError.notConfigured.localizedDescription
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let token = try await auth.session.accessToken
            var request = URLRequest(url: configuration.projectURL.appending(path: "functions/v1/delete-account"))
            request.httpMethod = "POST"
            request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"confirmation":"delete-my-account"}"#.utf8)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
                throw CloudAccountError.deletionFailed((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            try? await auth.signOut(scope: .local)
            updateDisplay(nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateDisplayFromCachedSession() {
        updateDisplay(auth?.currentSession)
    }

    private func updateDisplay(_ session: Session?) {
        isSignedIn = session != nil
        email = session?.user.email
    }
}
