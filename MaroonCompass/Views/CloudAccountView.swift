import SwiftUI

struct CloudAccountView: View {
    @State private var account = CloudAccountStore()
    @State private var isDeleteConfirmationPresented = false
    @State private var deletionText = ""

    var body: some View {
        Form {
            Section("Google account") {
                if !account.isConfigured {
                    Label("Cloud account setup is not complete", systemImage: "icloud.slash")
                    Text("Your schedule and personal plan continue to work on this device. A Supabase project and Google sign-in provider must be configured before you can connect an account.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if account.isSignedIn {
                    LabeledContent("Signed in", value: account.email ?? "Google account")
                    Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") {
                        Task { await account.signOut() }
                    }
                    .disabled(account.isBusy)
                } else {
                    Button("Continue with Google", systemImage: "person.crop.circle.badge.checkmark") {
                        Task { await account.signInWithGoogle() }
                    }
                    .disabled(account.isBusy)
                    Text("Maroon Compass requests your Google identity and email only. It does not read your Gmail messages or calendar.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if account.isBusy { ProgressView() }
                if let errorMessage = account.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.footnote)
                }
            }

            Section("Cloud schedule") {
                Text("Account sign-in is separate from your on-device schedule. Cloud backup and restore will appear here after the database and sync flow pass live testing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if account.isSignedIn {
                Section("Account control") {
                    Button("Delete cloud account and saved cloud data", role: .destructive) {
                        deletionText = ""
                        isDeleteConfirmationPresented = true
                    }
                    .disabled(account.isBusy)
                    Text("Deleting the cloud account does not erase this device's local schedule or personal plan.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Cloud Account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await account.refresh() }
        .sheet(isPresented: $isDeleteConfirmationPresented) {
            NavigationStack {
                Form {
                    Section {
                        Text("This permanently deletes your cloud account and saved cloud schedules. Your local schedule and personal plan remain on this device.")
                        TextField("Type DELETE to confirm", text: $deletionText)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    Section {
                        Button("Delete cloud account", role: .destructive) {
                            isDeleteConfirmationPresented = false
                            Task { await account.deleteCloudAccount() }
                        }
                        .disabled(deletionText != "DELETE")
                    }
                }
                .navigationTitle("Delete Cloud Account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isDeleteConfirmationPresented = false }
                    }
                }
            }
        }
    }
}
