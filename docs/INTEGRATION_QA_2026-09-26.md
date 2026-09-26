# Integration QA — 2026-09-26

This branch combines PR #3's import review, PR #4's local schedule history, and PR #6's Google account and cloud sync implementation. It uses one account implementation: PR #6's `CloudAccountModel` and `CloudSessionManager`. PR #5 contributed the callback URL scheme and build configuration, but its separate `CloudAccountStore` was not included.

## Reconciliation

- `AppStoreScheduleAccess.restore(.embedded)` calls the throwing `restoreEmbeddedSchedule()` method.
- Settings retains the **Previous schedules** row and presents restore failures.
- The cloud snapshot test uses `CloudScheduleSnapshot(bundle:fallbackTerm:)` and its current top-level meetings and events fields.
- The Xcode project uses PR #6's dependency-free cloud client and registers `marooncompass://auth/callback`; the unused Supabase Swift SDK dependency is absent.

## Verification

- Xcode 27.0, iPhone 17 Pro simulator: **82/82 tests passed** with a local ignored `SupabaseConfig.plist` containing only the project URL and publishable key.
- Unsigned Release iOS Simulator build: **succeeded**.
- The hosted Supabase project's two SQL migrations ran successfully in SQL Editor. Anonymous reads of `semesters`, `course_events`, and `list_schedule_semesters` returned HTTP 401 / PostgreSQL `42501`.
- Hosted Auth reports Google enabled. The authorization endpoint redirects to Google with the Supabase callback and identity-only scopes (`openid email profile`). This does not establish a completed Google login.
- The hosted `delete-account` function rejects a POST with no authorization header and a POST carrying only the publishable key; both return HTTP 401. No authenticated deletion was attempted.

The hosted migration commands were run through SQL Editor. Check or repair Supabase CLI migration history before a later `supabase db push`; do not blindly reapply these files. The hosted URL and publishable key stay in the ignored local plist. Never commit a Google client secret, service-role key, database password, or user token.

## Remaining gates

- Complete Google consent and callback on an actual signed app, then test authenticated backup, restore, conflicts, and account deletion with a disposable user.
- Verify physical Apple Intelligence availability and schedule image review on the user's device. The simulator exercises the OCR/manual path and unit logic, not a physical Apple Intelligence runtime.
- Check the signed app on a reachable unlocked iPhone while preserving its existing local data.

The known-good Maroon Compass 1.4 (5) archive was made before this work and remains separate from the source integration.
