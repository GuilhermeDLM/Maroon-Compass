# Project state

Updated: 2026-09-26

## Current state

Maroon Compass is an implemented native iPhone/iPad Texas A&M campus companion. The main branch includes the verified Fall 2026 schedule, campus/map services, widgets, reminders, calendar export, private ICS import, the Personal Plan feature, and guarded Personal Team renewal tooling. The macOS edition is maintained separately in `Maroon-Compass-Mac`.

The `codex/schedule-domain-foundation-20260925` branch begins the new schedule-domain work. It prevents an embedded schedule revision from deleting a user-imported schedule or its building assignments. Existing seed-only assignments are still filtered when the seed changes. The Phase 0 findings and implementation order are in `docs/PHASE0_AUDIT.md` on this branch.

## Verification status

- Baseline simulator suite: 21/21 tests passed on Xcode 27.0, iPhone 17 Pro simulator.
- After the preservation change and two regression tests: 23/23 tests passed. The strengthened old-seed-location test then passed in a targeted rerun.
- The schedule-domain foundation was verified on the simulator. The newer schedule-import branch has separate physical installation evidence below.
- The previously known-good Maroon Compass 1.4 (5) build was renewed through `Tools/RenewDeviceInstallation.zsh` from the Application Support mirror and wirelessly reinstalled on the paired iPhone 15 Pro. The app and widget signatures passed strict verification. The confirmed installed profile expires `2026-10-03T02:52:15Z`; `--check-only` subsequently reported no renewal needed. The renewal workflow intentionally did not launch the app.

## Repository and data boundaries

The Documents source directory has a local `.git` with no commits or remote and pre-existing staged/unstaged work. Do not reset or overwrite it. The private GitHub repository is the durable source of truth. This branch was updated through the GitHub connector because terminal Git has no credential for the private repository. Keep local renewal configuration, device identifiers, profiles, signing material, and user data out of Git. Read `AGENTS.md` before further edits.

## Schedule import and backend branch checkpoint

The branch `codex/schedule-import-and-backend-20260925` extends the schedule-domain branch. It adds a screenshot/photo import sheet in Schedule and Settings, local Vision OCR, conditional Foundation Models extraction, an OCR fallback, editable course/meeting draft, validation, and explicit confirmation before replacing a locally imported schedule. The iOS deployment target remains 18.0. The app retains old Codable import compatibility.

A Supabase migration defines semesters, courses, and course meetings with owner composite foreign keys, RLS for all four CRUD operations, and an atomic snapshot RPC with an expected-version conflict check. The Swift repository can serialize a lossless subset of reviewed photo schedules, write it, and read it back. It is not connected to the UI or a live backend because no Supabase project or Auth session is configured. ICS exceptions, one-time events, and rich Howdy fields remain local until the cloud model preserves them.

Verification: 29/29 iPhone 17 Pro simulator tests passed after import changes. The later cloud read method compiled in a simulator build but has no live backend test. The SQL migration and RLS test script have not been executed; PostgreSQL and a Supabase project are unavailable in this checkout. The new source built for device, passed strict app signature verification, and installed in place on the paired iPhone 15 Pro with a Personal Team profile expiring 2026-10-03T02:52:16Z. Before and after install, the app preferences plist had the same SHA-256 (`6ef9030f1d2b0b88d160e22657e24cdf699137536df9ea1fae21cb6b8edce56e`). Programmatic launch was denied because the phone was locked; on-device Apple Intelligence availability, visible UI, and live behavior remain unverified. The known-good 1.4 (5) signed app was preserved as a local ZIP. A strict-signature-verified copy of that exact build is in the projectless task outputs with SHA-256 `c009e163bb4664bc9277acf955986eba92f73c877a8837562aec956de4db0221`; do not commit its provisioning payload to GitHub.

Work occurred in an isolated copy at `/Users/guilhermemachado/Documents/Codex/2026-09-25/also-just-for-future-reference-a/work/maroon-compass-next`. The original Documents source and the renewal mirror were not overwritten by this branch. GitHub is the durable source; terminal Git lacks private-repo credentials, so this branch was updated through the GitHub connector.

## Backend, authentication, and sync branch checkpoint (2026-09-26)

Branch `claude/maroon-compass-backend-auth-c1m1yh`, based on PR #2 head `16249d96b56e876dd518491eb51d1bfd1379f7fa`. It targets `codex/schedule-import-and-backend-20260925` until PR #1 and PR #2 merge. It does not edit the photo-import files owned by the extraction work. Details: `docs/SCHEDULE_BACKEND.md`, `docs/SUPABASE_SETUP.md`, `docs/BACKEND_SECURITY_REVIEW.md`.

What changed:

- `202609250001` could not be applied (missing unique key for a composite FK); one constraint was added. A forward migration `202609260001` makes the cloud copy lossless for the embedded Howdy schedule, `.ics` imports, and reviewed photo imports; removes client write privileges so every write is version-checked; returns conflicts as HTTP 409; and adds atomic read/list functions.
- A `delete-account` Edge Function deletes the verified caller's Auth user; schedule rows cascade.
- Swift: Supabase Auth client, Keychain session store, session manager with rotation-safe refresh, lossless snapshot, local-first sync coordinator (explicit backup/restore/replace, conflict states, undo, versioned cloud deletion, offline retry, lost-response recognition, one cloud copy per term), and an account screen linked from Settings. Following the user's decision recorded in `AGENTS.md`, sign-in is **Google through Supabase Auth**: authorization code with PKCE in an ephemeral system web-authentication session, callback `marooncompass://auth/callback`, scopes `openid email profile` only. The earlier Sign in with Apple path was removed. A labeled anonymous development session exists only in Debug builds. Without Supabase configuration (`MaroonCompass/SupabaseConfig.plist`, or the `MCSupabaseURL`/`MCSupabasePublishableKey` Info.plist keys) the app stays in local mode.
- Reconciliation: Codex draft PR #5 (`codex/google-auth-20260926`) implements Google sign-in separately with the supabase-swift SDK, an app Info.plist, and project-file changes. This branch reaches the same endpoints with no SDK or project-file change and connects sign-in to sync and deletion. The integrator should keep one account view and one session store; both branches use the same callback, scopes, and Info.plist key names.

Verification, by gate:

- **Real Supabase software, local only:** Supabase CLI 2.118.0 stack in Docker (Postgres 17.6, Auth, PostgREST, Edge Runtime). `supabase test db`: 86/86 pgTAP assertions pass. `supabase db lint --level warning`: no issues. The account-deletion function was exercised over HTTP. No hosted Supabase project was created or used.
- **Swift client on Linux:** the app's portable sources built with Swift 6.2 in language mode 6 (`Tools/CloudHarness/run.sh`). 44 unit tests pass, and 6 live scenarios pass with the real client against the local stack: lossless round trips of all three schedule shapes, returning account on a second device, conflicts and stale reviews, cross-account isolation, token expiry and server rejection, sign-out revocation, account deletion including a deleted account's still-valid token, offline retry, a development session, the Google authorize redirect (Supabase Auth sends the app's request to `accounts.google.com` with only `openid email profile`), and the PKCE callback exchange (allow-listed `marooncompass://auth/callback`, wrong verifier and replayed code rejected), using the magic-link PKCE flow in place of Google consent. In this sandbox the Auth container needed the proxy CA installed to reach Google's discovery document; that is not a repository change.
- **iOS SDK:** not available in this environment. Codex's disposable macOS integration (`docs/INTEGRATION_QA_2026-09-26.md` on `codex/google-auth-20260926`) combined this branch at `d4e091a` with PRs #3–#5 and reported 76 passing iPhone 17 Pro simulator tests and a clean Release simulator build; that covered this branch's Swift code before the Google pivot. The Google sign-in changes (`CloudAuth.swift`, `CloudSessionManager.swift`, `CloudAccountModel.swift`, `CloudAccountView.swift`) and the cross-term fix have not been compiled with the iOS SDK; the Apple-platform files were syntax-checked with `swiftc -parse` only. No signing, installation, launch, or device test.
- **Blocked on user-only configuration:** live Google sign-in needs a Google Cloud Web OAuth client, the Supabase Google provider with that client, the Supabase callback URL in Google, and `marooncompass://auth/callback` in Supabase's redirect allow list. A hosted project needs Guilherme's Supabase account. Live Google sign-in has not been performed.

No build from this branch was signed or installed; the development build on the paired iPhone and its local data were not touched.

## Next safe actions

1. On the Mac, build this branch for the simulator and run the full test suite (`xcodebuild … test`). Fix any iOS-SDK-only compile issues in the four Apple-platform files before merging. Reconcile with PR #5 so only one Google sign-in implementation ships.
2. Create a disposable hosted Supabase development project, then `supabase db push`, `supabase test db --linked`, and `supabase functions deploy delete-account`; optionally run the live harness against it with `MC_LIVE_DISPOSABLE_PROJECT=yes`.
3. Configure Google: a Web OAuth client in Google Cloud (Supabase callback as redirect URI; `openid`, `email`, `profile` only), the Supabase Google provider, and `marooncompass://auth/callback` in the redirect allow list (`docs/SUPABASE_SETUP.md`).
4. With a local `SupabaseConfig.plist` pointing at that project, exercise the account screen in a Debug simulator build and then on the paired iPhone: Google sign-in, cancel, back up, second-device restore, conflict, undo, delete cloud copy, sign-out, delete account.
5. Test image extraction on the paired iPhone with Apple Intelligence enabled and disabled. Report actual runtime availability; simulator compilation does not establish it.
6. The development build is installed in place. Once the phone is unlocked, verify launch and the import screen. If it fails, use the verified known-good ZIP for recovery and preserve the preference backup.
