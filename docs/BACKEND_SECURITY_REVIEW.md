# Backend and account security review

Reviewed: September 26, 2026, branch `claude/maroon-compass-backend-auth-c1m1yh`. Evidence is from a local Supabase CLI stack (Postgres 17.6, Supabase Auth, PostgREST, Edge Runtime), pgTAP, and the Linux Swift harness. Hosted-project and iOS simulator results were reported by the integrator in a PR #6 comment and are labeled as such; no device was involved.

## Findings in the previous foundation (fixed)

| Severity | Finding | Fix | Evidence |
| --- | --- | --- | --- |
| High | `202609250001` could not be applied (FK to `courses(id, user_id)` without a unique key, SQLSTATE 42830). | Added the one missing constraint. | `supabase start` now applies it. |
| High | Clients held direct INSERT/UPDATE on schedule tables; a `PATCH` changed rows without bumping `sync_version`, defeating conflict detection. | Clients now have SELECT (and DELETE on whole semesters) only; writes go through the versioned RPC. | HTTP 403 on direct `PATCH`; pgTAP privilege assertions. |
| Medium | Version conflicts raised SQLSTATE 40001, which PostgREST returns as HTTP 500; the app would report an outage, not a conflict. | Conflicts use `PT409` → HTTP 409 with stable messages. | HTTP probe before/after; pgTAP. |
| Medium | Duplicate weekdays were stored but rejected on restore, making a backup unrestorable. | Canonical-set constraints on weekdays and date lists. | HTTP 400; pgTAP. |
| Medium | Constraint errors inside the RPC (for example a duplicate ID) would surface as HTTP 409 and look like a conflict. | RPC maps integrity/data errors to `invalid_snapshot` (HTTP 400). | pgTAP. |
| Low | A deleted account's unexpired JWT hit an FK error reported as invalid input. | RPC checks the Auth user exists and returns `authentication_required` (HTTP 403); the app then fails to refresh and signs out. | pgTAP; live test. |

## Current design

- **Ownership:** every table has `user_id` with `ON DELETE CASCADE` from `auth.users` and composite foreign keys (`semester_id, user_id` and `course_id, semester_id, user_id`), so a child row cannot point at another owner's or another semester's parent. RLS policies compare `user_id` with `(select auth.uid())` for all operations.
- **Privileges:** `anon` has nothing. `authenticated` has SELECT on all four tables and DELETE on `semesters` (cascading). No client INSERT/UPDATE. Execute on the three RPCs is revoked from `public`/`anon` and granted to `authenticated`.
- **Write RPC:** `replace_schedule_snapshot` is `SECURITY DEFINER` so clients need no write privilege. It takes the owner only from `auth.uid()`, never from input; every statement filters by that owner; `search_path` is empty and all names are schema-qualified; input size is bounded (1 MB, 100 courses, 500 meetings, 1,000 events, 20 semesters per account). Tested: another account cannot create a row with a known semester ID (409 `schedule_exists`), cannot overwrite it with the correct version (409 `schedule_missing`), and the owner's data is unchanged.
- **Reads:** `get_schedule_snapshot` and `list_schedule_semesters` are `SECURITY INVOKER` under RLS with an explicit owner filter. The snapshot read is one SQL statement, so it is internally consistent.
- **Account deletion:** the Edge Function requires a bearer token and validates it with `GET /auth/v1/user` (which rejects signed-out sessions), requires a confirmation body, and deletes only the ID Auth returns. Gateway JWT verification (`verify_jwt = true`) is an extra layer, not the one relied on. The admin key exists only in the function environment. Tested locally: missing/forged token → 401, missing confirmation → 400, confirmed → Auth user and all rows removed, old refresh token rejected. Reported on the hosted development project: unauthenticated POST → 401, publishable key only → 401 `missing_session` from the function itself.
- **Client keys:** only the project URL and publishable key ship. `SupabaseConfiguration` refuses `sb_secret_…` and `service_role` JWTs and non-HTTPS URLs (plain HTTP only to localhost in Debug). The config file is git-ignored.
- **Sign-in (Google via Supabase Auth):** authorization code flow with S256 PKCE in an ephemeral `ASWebAuthenticationSession` (no cookies shared with Safari). The verifier exists only in memory for one attempt; the callback `marooncompass://auth/callback` must be on Supabase's redirect allow list, and its code is exchanged once and only with the matching verifier, so a code delivered to another app through the custom scheme is useless. Scopes are `openid email profile`; no Gmail, Calendar, or other Google API access. Google's provider tokens are never stored. Tested against real Supabase Auth: redirect to Google with identity scopes only, allow-listed callback, wrong-verifier and replayed-code rejection.
- **Tokens:** stored in one Keychain item, `AfterFirstUnlockThisDeviceOnly`, not synchronized; a fresh install clears a session left by an earlier install. `AuthSession` redacts tokens from `description`, `debugDescription`, and `Mirror`. The app does not log. Networking uses an ephemeral `URLSession` with no cache, cookies, or credential store.
- **Refresh:** single-flight (rotation-safe); an invalid refresh token signs the device out; connectivity failures keep the session; a server-rejected token triggers one refresh and one retry.
- **Development sessions:** anonymous, compiled into the UI only in Debug, labeled "not restorable", disabled by `SupabaseConfiguration` in Release, and discarded if a Release build finds one in the Keychain.
- **Data minimization:** only the confirmed class schedule is uploaded. Photos, OCR text, `.ics` diagnostic properties, Personal Plan, saved places, location, reminders, and building overrides stay local. The app stores no email or name; Supabase Auth itself keeps the Google email and profile claims in `auth.users`, which the account-deletion path removes.

## Residual risks and open items

1. **Not yet verified: a completed Google sign-in, authenticated use of the hosted project, or a device.** The integrator reports anonymous access denied and the function's rejections on the hosted development project, Google provider routing with identity scopes only, and 82/82 simulator tests with a Release simulator build. Keychain and web-authentication behavior on a signed device is untested.
2. **Access tokens are stateless until expiry** (1 hour by default). After sign-out or deletion, a copied access token can still pass PostgREST's JWT check, but it can read nothing after deletion and cannot write (RPC checks the Auth user). Shorter `jwt_expiry` reduces the window.
3. **Sign-out while offline** clears the device but cannot revoke the refresh token server-side; the app says so.
4. **Google access revocation** (a person removing the app at myaccount.google.com) does not end the Supabase session; it continues until it is signed out, deleted, or fails to refresh. Deleting the account does not revoke the Google grant either; nothing the app holds can call Google.
5. **Custom URL scheme:** any app can claim `marooncompass://`. PKCE makes an intercepted code unusable, and `ASWebAuthenticationSession` returns the callback directly to this app.
6. **Semester ID existence** is observable to another account through `schedule_exists`; IDs are random UUIDs, so this reveals nothing practical.
7. **Anonymous sign-ins** must stay disabled on any project real schedules depend on; the app cannot enforce Auth settings.
