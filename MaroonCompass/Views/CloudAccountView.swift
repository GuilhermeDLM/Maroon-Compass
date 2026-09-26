import AuthenticationServices
import SwiftUI

/// Optional account and cloud backup for the confirmed class schedule. Everything else in the
/// app works without it, and nothing here changes either copy without a confirmation.
struct CloudAccountView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CloudAccountModel?

    var body: some View {
        Group {
            if let model {
                CloudAccountContent(model: model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Account & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = CloudAccountModel(
                    services: CloudServices.shared,
                    local: AppStoreScheduleAccess(store: store),
                    stateStore: UserDefaultsCloudSyncStateStore()
                )
            }
            await model?.load()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the app retries an upload that failed while offline.
            guard phase == .active, let model else { return }
            Task { await model.refresh() }
        }
    }
}

private enum PendingCloudAction: Identifiable, Sendable {
    case restore(CloudSemesterSummary)
    case replaceCloud(CloudSemesterSummary)
    case deleteCloudCopy(CloudSemesterSummary)
    case signOut
    case deleteAccount

    var id: String {
        switch self {
        case .restore(let summary): "restore-\(summary.id)-\(summary.syncVersion)"
        case .replaceCloud(let summary): "replace-\(summary.id)-\(summary.syncVersion)"
        case .deleteCloudCopy(let summary): "delete-\(summary.id)-\(summary.syncVersion)"
        case .signOut: "sign-out"
        case .deleteAccount: "delete-account"
        }
    }

    var title: String {
        switch self {
        case .restore: "Replace this device’s schedule with the cloud copy?"
        case .replaceCloud: "Replace the cloud copy with this device’s schedule?"
        case .deleteCloudCopy(let summary): "Delete the cloud copy of \(summary.name)?"
        case .signOut: "Sign out of cloud backup?"
        case .deleteAccount: "Delete your account?"
        }
    }

    var message: String {
        switch self {
        case .restore(let summary):
            "\(summary.name), \(summary.courseCount) course\(summary.courseCount == 1 ? "" : "s"). The schedule on this device is kept so you can undo. Your Personal Plan, saved places, and reminder settings are not changed."
        case .replaceCloud(let summary):
            "The cloud copy of \(summary.name) will match this device. Your other devices will ask before they change."
        case .deleteCloudCopy:
            "This removes it from the cloud for every device. The schedule on this device is not changed."
        case .signOut:
            "Your schedule stays on this device, and your cloud copies stay in your account."
        case .deleteAccount:
            "This permanently deletes your account and every cloud schedule in it. It can’t be undone. The schedule on this device stays."
        }
    }

    var confirmLabel: String {
        switch self {
        case .restore: "Restore Cloud Copy"
        case .replaceCloud: "Replace Cloud Copy"
        case .deleteCloudCopy: "Delete Cloud Copy"
        case .signOut: "Sign Out"
        case .deleteAccount: "Delete Account"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .restore, .signOut: false
        case .replaceCloud, .deleteCloudCopy, .deleteAccount: true
        }
    }
}

private struct CloudAccountContent: View {
    @Bindable var model: CloudAccountModel
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var pendingAction: PendingCloudAction?

    var body: some View {
        List {
            if let notice = model.notice {
                Section {
                    Label(notice.message, systemImage: notice.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(notice.isError ? Color.red : Color.primary)
                    Button("Dismiss") { model.notice = nil }
                        .font(.subheadline)
                }
            }

            if !model.isConfigured {
                Section {
                    Label("Cloud backup isn’t set up in this build", systemImage: "icloud.slash")
                    Text("Your schedule, Personal Plan, reminders, and saved places work fully on this device. Nothing is sent to a server.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                switch model.account {
                case .unknown:
                    Section { ProgressView("Checking your account…") }
                case .signedOut:
                    signInSections
                case .signedIn(let user):
                    accountSections(user)
                }
            }

            Section("What cloud backup stores") {
                Label("Only your confirmed class schedule: courses, meetings, rooms, and semester dates", systemImage: "calendar")
                Label("Never schedule photos, OCR text, your Personal Plan, saved places, location, or reminders", systemImage: "hand.raised.fill")
                Label("Sent over an encrypted connection; each account can read only its own schedules", systemImage: "lock.shield.fill")
            }
            .font(.subheadline)
        }
        .overlay {
            if model.isWorking {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Working")
            }
        }
        .refreshable { await model.refresh() }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button(action.confirmLabel, role: action.isDestructive ? ButtonRole.destructive : nil) { perform(action) }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
    }

    // MARK: - Signed out

    @ViewBuilder
    private var signInSections: some View {
        Section {
            Text("Back up your confirmed class schedule and restore it on another iPhone or iPad. An account is optional; everything works on this device without one.")
                .font(.subheadline)
            Button {
                Task { await signInWithGoogle() }
            } label: {
                Label("Continue with Google", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isWorking)
        } header: {
            Text("Cloud backup")
        } footer: {
            Text("Google shares your name, email address, and profile photo with the account service. Maroon Compass never requests Gmail or Google Calendar access.")
        }

        #if DEBUG
        if model.allowsDevelopmentSessions {
            Section {
                Button("Start development session", systemImage: "hammer") {
                    Task { await model.startDevelopmentSession() }
                }
                .disabled(model.isWorking)
                Label("Debug builds only. This anonymous session can’t be restored after signing out or on another device.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } header: {
                Text("Development")
            }
        }
        #endif
    }

    // MARK: - Signed in

    @ViewBuilder
    private func accountSections(_ user: AuthUser) -> some View {
        Section("Account") {
            if user.isAnonymous {
                Label("Development session — not restorable", systemImage: "hammer.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Signed in with Google", systemImage: "person.crop.circle.badge.checkmark")
            }
        }

        Section {
            statusRows(model.overview)
        } header: {
            Text("This device’s schedule")
        } footer: {
            if let synced = model.overview?.lastSyncedAt {
                Text("Last synced \(synced.formatted(.relative(presentation: .named))).")
            }
        }

        if let others = model.overview?.otherSemesters, !others.isEmpty {
            Section("Other cloud semesters") {
                ForEach(others) { summary in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.name)
                            Text("\(summary.firstClassDate) – \(summary.lastClassDate) · \(courseCount(summary))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore") { pendingAction = .restore(summary) }
                            .disabled(model.isWorking)
                    }
                }
            }
        }

        if model.canUndoRestore, let name = model.restoreBackupName {
            Section {
                Button("Undo restore of \(name)", systemImage: "arrow.uturn.backward") {
                    Task { await model.undoRestore() }
                }
                .disabled(model.isWorking)
            } footer: {
                Text("Puts back the schedule this device had before the restore.")
            }
        }

        Section("Manage") {
            if let summary = model.overview?.state.summary {
                Button("Delete cloud copy of \(summary.name)", systemImage: "icloud.slash", role: .destructive) {
                    pendingAction = .deleteCloudCopy(summary)
                }
                .disabled(model.isWorking)
            }
            Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { pendingAction = .signOut }
                .disabled(model.isWorking)
            Button("Delete account…", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                pendingAction = .deleteAccount
            }
            .disabled(model.isWorking)
        }
    }

    @ViewBuilder
    private func statusRows(_ overview: CloudSyncOverview?) -> some View {
        if let overview {
            let blocked = overview.localLimitation != nil
            if let limitation = overview.localLimitation {
                Label("This schedule stays on this device. \(limitation.explanation)", systemImage: "lock.iphone")
                    .foregroundStyle(.secondary)
            }
            switch overview.state {
            case .noCloudCopy:
                Label("Not backed up yet", systemImage: "icloud.slash")
                uploadButton("Back up this schedule", blocked: blocked)
            case .upToDate(let summary):
                Label("Backed up · \(summary.name) · \(courseCount(summary))", systemImage: "checkmark.icloud")
            case .localChanges:
                Label("This device has changes that aren’t backed up", systemImage: "arrow.up.circle")
                uploadButton("Upload changes", blocked: blocked)
            case .remoteChanges(let summary):
                Label("Another device updated the cloud copy (\(courseCount(summary)))", systemImage: "arrow.down.circle")
                choiceButtons(summary, blocked: blocked)
            case .conflict(let summary):
                Label("This device and the cloud copy both changed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                choiceButtons(summary, blocked: blocked)
            case .cloudCopyAvailable(let summary):
                Label("A different cloud copy of \(summary.name) exists (\(courseCount(summary)))", systemImage: "icloud")
                choiceButtons(summary, blocked: blocked)
            case .cloudCopyDeleted:
                Label("The cloud copy was deleted on another device", systemImage: "icloud.slash")
                uploadButton("Back up again", blocked: blocked)
            }
        } else {
            Label("Checking cloud backup…", systemImage: "icloud")
                .foregroundStyle(.secondary)
        }
    }

    private func uploadButton(_ title: String, blocked: Bool) -> some View {
        Button(title, systemImage: "icloud.and.arrow.up") {
            Task { await model.uploadLocalChanges() }
        }
        .disabled(blocked || model.isWorking)
    }

    @ViewBuilder
    private func choiceButtons(_ summary: CloudSemesterSummary, blocked: Bool) -> some View {
        Button("Use the cloud copy…", systemImage: "icloud.and.arrow.down") { pendingAction = .restore(summary) }
            .disabled(model.isWorking)
        Button("Keep this device’s schedule…", systemImage: "iphone") { pendingAction = .replaceCloud(summary) }
            .disabled(blocked || model.isWorking)
    }

    private func courseCount(_ summary: CloudSemesterSummary) -> String {
        "\(summary.courseCount) course\(summary.courseCount == 1 ? "" : "s")"
    }

    private func perform(_ action: PendingCloudAction) {
        pendingAction = nil
        Task {
            switch action {
            case .restore(let summary): await model.restore(summary)
            case .replaceCloud(let summary): await model.replaceCloudCopy(summary)
            case .deleteCloudCopy(let summary): await model.deleteCloudCopy(summary)
            case .signOut: await model.signOut()
            case .deleteAccount: await model.deleteAccount()
            }
        }
    }

    /// Opens Supabase Auth's Google flow in an ephemeral system browser session (no cookies
    /// shared with Safari) and returns the `marooncompass://auth/callback` URL.
    private func signInWithGoogle() async {
        let session = webAuthenticationSession
        await model.signInWithGoogle { url in
            do {
                return try await session.authenticate(
                    using: url,
                    callbackURLScheme: OAuthSignInRequest.callbackScheme,
                    preferredBrowserSession: .ephemeral
                )
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                throw CancellationError()
            }
        }
    }
}
