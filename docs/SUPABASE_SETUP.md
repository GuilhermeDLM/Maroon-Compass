# Supabase setup and verification

Cloud backup is optional. Without `MaroonCompass/SupabaseConfig.plist` the app runs in local mode and never contacts a server. This guide covers a local stack, a disposable hosted development project, the app configuration, and the tests. Never put a secret key, service-role key, JWT secret, Google client secret, or real user data in Git.

## What exists

| Piece | Path | Purpose |
| --- | --- | --- |
| Schema v1 (fixed) | `supabase/migrations/202609250001_schedule.sql` | Semesters, courses, meetings, owner RLS. One missing unique key was added; without it the file could not be applied. |
| Schema v2 | `supabase/migrations/202609260001_schedule_sync.sql` | Lossless columns, one-time events, canonical checks, read-only tables, versioned snapshot RPCs. |
| Account deletion | `supabase/functions/delete-account/index.ts` | Verifies the caller with Auth, deletes that user with the admin API. Rows cascade. |
| Database tests | `supabase/tests/database/*.test.sql` | pgTAP: RLS, privileges, ownership keys, RPC versioning, rollback, validation, cascades. |
| Client harness | `Tools/CloudHarness/run.sh` | Builds the app's portable cloud Swift sources on Linux and runs unit and live tests. |
| Local config | `supabase/config.toml` | CLI stack settings. Contains no secrets. |

## Local stack (Supabase CLI + Docker)

```sh
supabase start                     # applies both migrations, serves Auth, REST, and Edge Functions
supabase test db                   # pgTAP suites; expect "Files=2, Tests=86 ... Result: PASS"
supabase db lint --level warning   # expect "No schema errors found"
supabase db reset                  # re-apply migrations from scratch
```

`supabase status` prints the local URL and keys. The local keys are the CLI's public demo keys and are only valid for that stack. If Docker cannot reach `public.ecr.aws`, set `SUPABASE_INTERNAL_IMAGE_REGISTRY=docker.io`; that is how this branch was verified.

The local config enables Google sign-in (client ID and secret from `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID` and `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_SECRET`; placeholders are fine when you are not signing in with Google), allow-lists `marooncompass://auth/callback`, enables anonymous sign-ins (for Debug development sessions) and the email provider plus the local mail catcher (so tests can create restorable identities and exercise the same PKCE callback exchange Google uses). The app itself offers no email sign-in.

## Swift client harness

Requires Docker and the `swift:6.2-noble` image. It copies the app's portable sources (models, seed, engine, `.ics` parser, draft, and the cloud files) into a scratch package with a small CoreLocation shim, then runs XCTest in Swift 6 language mode.

```sh
Tools/CloudHarness/run.sh                                   # 44 unit tests, no network

MC_LIVE_SUPABASE_URL=http://127.0.0.1:54321 \
MC_LIVE_PUBLISHABLE_KEY=<local publishable key> \
MC_LIVE_SECRET_KEY=<local secret key> \
MC_LIVE_MAILPIT_URL=http://127.0.0.1:54324 \
Tools/CloudHarness/run.sh                                   # plus 6 live scenarios
```

The live tests create and delete users with the admin key, so they refuse any host except localhost unless `MC_LIVE_DISPOSABLE_PROJECT=yes` is also set. Never run them against a project that holds real schedules. `MC_HARNESS_FILTER` passes a regular expression to `swift test --filter`. The Google-redirect test needs the Auth container to reach `accounts.google.com` (for OpenID discovery); it skips with a message otherwise.

The cloud unit tests are also part of the iOS test target (`MaroonCompassTests/Cloud*.swift`) and run with the normal `xcodebuild … test` command.

## Disposable hosted development project (user-only step)

A hosted project needs Guilherme's Supabase account. A disposable development project exists: both migrations were applied in the SQL Editor and `delete-account` was deployed (`docs/PROJECT_STATE.md` has what was checked).

1. Create a new project in the Supabase dashboard (a dedicated development project; no real data).
2. Link and apply: `supabase link --project-ref <ref>` then `supabase db push`. If the migrations were applied another way (for example pasted into the SQL Editor), see "Migration history" below before any `db push`.
3. Run the database tests against it: `supabase test db --linked`. They insert two test users and roll everything back.
4. Deploy the function: `supabase functions deploy delete-account`. `SUPABASE_URL`, the anon/publishable key, and the service-role/secret key are injected by Supabase into the function environment; do not add them anywhere else. `config.toml` keeps gateway JWT verification on, but the function does not depend on it: it rejects a request without a bearer token (`missing_session`) and validates every token with Supabase Auth before deleting anything.
5. Auth settings for the development project:
   - Google provider and redirect allow list: see below.
   - Anonymous sign-ins: on only if you want Debug development sessions. Keep them off on any project real schedules depend on.
   - Email provider: needed only to run the live harness against this project.
6. Optionally run the live harness against it (below).

### Migration history

The CLI records applied migrations in `supabase_migrations.schema_migrations`. The SQL Editor does not, so a later `supabase db push` would try to apply both files again, and `202609250001` would fail on existing tables. Record them instead of reapplying:

```sh
supabase link --project-ref <ref>
supabase migration list --linked         # both versions listed under Local only
supabase migration repair --status applied 202609250001 202609260001 --linked
supabase migration list --linked         # both versions now under Local and Remote
```

Only mark a version applied after confirming that exact file ran successfully. Afterwards `supabase db push` applies only newer migrations.

### Authenticated checks on the hosted project

The live harness signs in as throwaway users, so it covers authenticated sync and account deletion without a Google account. It creates users with the admin key and deletes them, so use only a disposable project. Pass keys as environment variables in your shell, never in a file in the repository:

```sh
MC_LIVE_SUPABASE_URL=https://<ref>.supabase.co \
MC_LIVE_PUBLISHABLE_KEY=<publishable key> \
MC_LIVE_SECRET_KEY=<secret key> \
MC_LIVE_DISPOSABLE_PROJECT=yes \
MC_HARNESS_FILTER='CloudLiveIntegrationTests/test(RealServer|ReturningAccount|TokenExpiry|GoogleAuthorize)' \
Tools/CloudHarness/run.sh
```

This needs the email provider enabled (test users sign in with a password; `@example.invalid` addresses, pre-confirmed, so no mail is sent). It runs round trips of all three schedule shapes, a second device, conflicts, cross-account isolation, token expiry, sign-out, account deletion through the deployed function, and the Google redirect. The offline and development-session scenario also needs anonymous sign-ins, and the PKCE callback scenario needs the local mail catcher, so the filter leaves them out. The admin key may be a `sb_secret_…` key or a legacy `service_role` key. Turn the email provider (and anonymous sign-ins, if enabled) back off afterwards if the project will be used with the app.

## App configuration

Copy `Configuration/SupabaseConfig.example.plist` to `MaroonCompass/SupabaseConfig.plist` (git-ignored) and fill in:

- `ProjectURL`: `https://<ref>.supabase.co`. Debug builds also accept `http://127.0.0.1:54321` for a local stack.
- `PublishableKey`: the publishable (`sb_publishable_…`) or legacy anon key. The app refuses `sb_secret_…` and `service_role` keys.
- `AllowDevelopmentSessions`: `true` to offer anonymous development sessions. Ignored in Release builds.

The file-system-synchronized `MaroonCompass` group bundles the plist automatically; no project-file change is needed. Delete the file to return to local mode. If the integrator adopts the `MCSUPABASE_URL` / `MCSUPABASE_PUBLISHABLE_KEY` build settings from `codex/google-auth-20260926` (Info.plist keys `MCSupabaseURL` / `MCSupabasePublishableKey`), the app reads those when the plist is absent; empty values mean local mode.

## Google sign-in (user-only configuration)

Accounts use Google through Supabase Auth (user decision, 2026-09-26; the Personal Team cannot provision Sign in with Apple). The app opens Supabase's `/auth/v1/authorize?provider=google` in an ephemeral system web-authentication session with an S256 PKCE challenge and scopes `openid email profile`. Supabase sends the browser to Google and back to `marooncompass://auth/callback?code=…`; the app exchanges that one-time code with its in-memory verifier (`grant_type=pkce`). No Gmail, Google Calendar, or other Google API scope is requested, and the app never stores Google's own tokens. No entitlement or Apple capability is needed.

1. Google Auth Platform (Google Cloud console): configure the consent screen (app name, support email, the `openid`, `email`, `profile` scopes only). Create an OAuth client of type **Web application**. Add the Supabase callback `https://<project-ref>.supabase.co/auth/v1/callback` to its authorized redirect URIs. For a local stack, also add `http://127.0.0.1:54321/auth/v1/callback`.
2. Supabase dashboard → Authentication → Providers → Google: enable it and paste the client ID and client secret. The secret lives only in Supabase (or, locally, in `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_SECRET`); never in Git or the app.
3. Supabase dashboard → Authentication → URL Configuration: add `marooncompass://auth/callback` to the redirect URLs. Without it Supabase redirects to the site URL and sign-in cannot finish.
4. Put the project URL and publishable key in `SupabaseConfig.plist` (above).
5. Verify on a simulator and then the paired iPhone: first sign-in, cancel, decline on the consent screen, sign-out, sign-in again, a second device, restore, and account deletion. Do not report live Google sign-in as working until these pass.

`ASWebAuthenticationSession` intercepts the callback scheme itself, so this code does not need a `CFBundleURLTypes` entry. Registering the scheme in Info.plist (as `codex/google-auth-20260926` does) is harmless.

Deleting the account deletes the Supabase user and every cloud schedule. The Google account itself is unaffected; people can remove the app's access at myaccount.google.com.
