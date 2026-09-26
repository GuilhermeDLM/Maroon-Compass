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

- **Real Supabase software, local only:** Supabase CLI 2.118.0 stack in Docker (Postgres 17.6, Auth, PostgREST, Edge Runtime). `supabase test db`: 86/86 pgTAP assertions pass. `supabase db lint --level warning`: no issues. The account-deletion function was exercised over HTTP. This environment did not use the hosted project.
- **Swift client on Linux:** the app's portable sources built with Swift 6.2 in language mode 6 (`Tools/CloudHarness/run.sh`). 44 unit tests pass, and 6 live scenarios pass with the real client against the local stack: lossless round trips of all three schedule shapes, returning account on a second device, conflicts and stale reviews, cross-account isolation, token expiry and server rejection, sign-out revocation, account deletion including a deleted account's still-valid token, offline retry, a development session, the Google authorize redirect (Supabase Auth sends the app's request to `accounts.google.com` with only `openid email profile`), and the PKCE callback exchange (allow-listed `marooncompass://auth/callback`, wrong verifier and replayed code rejected), using the magic-link PKCE flow in place of Google consent. The live tests accept either a `sb_secret_…` or a legacy `service_role` admin key (both verified locally). In this sandbox the Auth container needed the proxy CA installed to reach Google's discovery document; that is not a repository change.
- **iOS SDK (reported in a PR #6 comment, 2026-09-26; not run in this environment):** a disposable macOS integration of PR #3 + PR #4 + this branch's Google sign-in (one account implementation, from this branch; the callback scheme and project configuration from PR #5) passed 82/82 iPhone 17 Pro simulator tests and an unsigned Release simulator build. The reconciliation needed: `try store.restoreEmbeddedSchedule()`, keeping the "Previous schedules" Settings row, and PR #3's snapshot test using `CloudScheduleSnapshot(bundle:fallbackTerm:)`. That checkout is local and is not yet an integration PR. An earlier pre-Google run of this branch at `d4e091a` passed 76 tests (`docs/INTEGRATION_QA_2026-09-26.md` on `codex/google-auth-20260926`). No signing, installation, launch, or device test.
- **Hosted disposable project (reported in the same comment; not run in this environment):** a dedicated development project with no real data. Google provider enabled; an authorize request with `marooncompass://auth/callback` and `openid email profile` redirects to Google through the Supabase callback URL (provider routing only, not a completed login; no Gmail or Calendar scopes). Both migrations were applied in the SQL Editor and succeeded. Anonymous REST reads of `semesters` and `course_events` and the `list_schedule_semesters` RPC return 401/`42501`. `delete-account` is deployed: an unauthenticated POST returns 401, and a POST carrying only the publishable key returns 401 `missing_session` (the function's own check; no account was deleted). The URL and publishable key are only in the ignored local `SupabaseConfig.plist`. Because the SQL Editor does not record CLI migration history, repair it before any `supabase db push` (`docs/SUPABASE_SETUP.md`). pgTAP has not been run against the hosted database.
- **Not yet verified:** a completed Google consent and sign-in, the signed app on the paired iPhone, and authenticated sync and account deletion against the hosted project. Live Google sign-in has not been performed.

No build from this branch was signed or installed; the development build on the paired iPhone and its local data were not touched.

## Next safe actions

1. Open the integration PR for the tested #3 + #4 + #6 combination (one account implementation, from this branch) and rerun the simulator suite on the merged result.
2. Hosted project: record the SQL Editor migrations in the CLI history (`supabase migration repair --status applied 202609250001 202609260001 --linked`), then optionally `supabase test db --linked`. For authenticated sync and account deletion with disposable test users, run the live harness against it (`docs/SUPABASE_SETUP.md`, "Authenticated checks on the hosted project").
3. With the local `SupabaseConfig.plist`, exercise the account screen in a Debug simulator build and then on the paired iPhone: Google sign-in, cancel, decline consent, back up, second-device restore, conflict, undo, delete cloud copy, sign-out, delete account. Report live Google sign-in only after these pass.
4. Test image extraction on the paired iPhone with Apple Intelligence enabled and disabled. Report actual runtime availability; simulator compilation does not establish it.
5. The development build is installed in place. Once the phone is unlocked, verify launch and the import screen. If it fails, use the verified known-good ZIP for recovery and preserve the preference backup.
