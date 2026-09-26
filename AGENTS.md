# Maroon Compass iOS repository instructions

Read `README.md` and `docs/PROJECT_STATE.md` before changing the app.

- This repository is the native iPhone/iPad edition. The macOS edition is maintained separately in `Maroon-Compass-Mac`.
- Preserve the app and widget bundle identities, the user's schedule and local data, academic exception handling, saved places, reminders, and Personal Team renewal safeguards.
- Never guess missing course times, rooms, travel durations, finals, or schedule changes. Use authoritative user-provided or official data.
- Keep `Tools/RenewalConfig.local.zsh`, device identifiers, signing exports, provisioning profiles, and Keychain material out of Git.
- Run schedule tests and a relevant simulator build for source changes. Treat source, signing, installation, launch, and physical-device behavior as separate gates.
- Update `docs/PROJECT_STATE.md` whenever schedule authority, signing state, or the next delivery gate changes.
- Use focused branches and commits; never force-push shared history.

## Current authentication decision (user instruction, 2026-09-26)

- Use Google sign-in through Supabase for this build. The user's current Apple Personal Team cannot provision Sign in with Apple, and the user explicitly chose Google instead. Keep the app fully usable in local mode without an account.
- Replace the Apple-specific account UI, identity-token grant, and `supabase/config.toml` provider setup with Google OAuth using PKCE and a system web-authentication session. Register and allow `marooncompass://auth/callback`. Request only `openid email profile`; do not request Gmail-message or Google Calendar access. Keep Google client secrets and Supabase service-role keys out of Git and the iOS app.
- Preserve the provider-independent `auth.uid()` ownership policies, snapshot sync, offline/conflict behavior, Keychain sessions, sign-out, and account deletion. Update tests and setup docs for Google.
- Codex draft PR #5 (`codex/google-auth-20260926`) contains a separate Google-auth implementation and detailed `docs/GOOGLE_AUTH_HANDOFF.md`. This branch now has its own `CloudAccountView`, `SettingsView`, and cloud session architecture; adapt that existing architecture and reconcile the branches during integration rather than adding duplicate account views or session stores.
- Live Google login needs a Google Cloud Web OAuth client, the Supabase Google provider, the Supabase callback URL in Google, and the app callback in Supabase's redirect allow list. Do not claim live auth success until those are configured and tested.
