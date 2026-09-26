# Integration QA — 2026-09-26

This branch combines PR #3's import review, PR #4's local schedule history, and PR #6's Google account and cloud sync implementation. It uses one account implementation: PR #6's `CloudAccountModel` and `CloudSessionManager`. PR #5 contributed the callback URL scheme and build configuration, but its separate `CloudAccountStore` was not included.

## Reconciliation

- `AppStoreScheduleAccess.restore(.embedded)` calls the throwing `restoreEmbeddedSchedule()` method.
- Settings retains the **Previous schedules** row and presents restore failures.
- The cloud snapshot test uses `CloudScheduleSnapshot(bundle:fallbackTerm:)` and its current top-level meetings and events fields.
- The Xcode project uses PR #6's dependency-free cloud client and registers `marooncompass://auth/callback`; the unused Supabase Swift SDK dependency is absent.
- Physical iPhone testing found that the on-device model sometimes split a course code from its section and added a duplicate or unrelated course. OCR had the two visible courses correct. AI suggestions are now reconciled against OCR course identities, fill only missing fields, and cannot add unmatched courses. The review screen still requires confirmation.

## Verification

- Xcode 27.0, iPhone 17 Pro simulator: **84/84 tests passed** with a local ignored `SupabaseConfig.plist` containing only the project URL and publishable key. The [integration CI run](https://github.com/GuilhermeDLM/Maroon-Compass/actions/runs/36262658336) also passed on the preceding integration commit.
- Unsigned Release iOS Simulator build: **succeeded** after the AI reconciliation change.
- A signed Debug build installed and launched on an iPhone 15 Pro running iOS 27.0. A physical device test reported `SystemLanguageModel.default.availability == .available`. On a synthetic screenshot, `usedAppleIntelligence` was true; after reconciliation the draft contained exactly the two visible courses with OCR-confirmed codes and sections. A temporary diagnostic test was removed after this verification.
- The hosted Supabase project's two SQL migrations ran successfully in SQL Editor. Anonymous reads of `semesters`, `course_events`, and `list_schedule_semesters` returned HTTP 401 / PostgreSQL `42501`.
- Hosted Auth reports Google enabled. The authorization endpoint redirects to Google with the Supabase callback and identity-only scopes (`openid email profile`). This does not establish a completed Google login.
- Google Cloud's OAuth app remains in Testing mode; the project owner's Google account is saved as its one test user.
- The hosted `delete-account` function rejects a POST with no authorization header and a POST carrying only the publishable key; both return HTTP 401. No authenticated deletion was attempted.

The hosted migration commands were run through SQL Editor. A read-only query confirmed `supabase_migrations.schema_migrations` does not yet exist. Before a later `supabase db push`, link this disposable project and use [Supabase migration repair](https://supabase.com/docs/guides/deployment/database-migrations#step-3-if-the-migration-history-table-is-wrong) to mark `202609250001` and `202609260001` as applied without rerunning their SQL. Then verify `supabase migration list`. The hosted URL and publishable key stay in the ignored local plist. Never commit a Google client secret, service-role key, database password, or user token.

## Remaining gates

- Complete Google consent and callback on an actual signed app, then test authenticated backup, restore, conflicts, and account deletion with a disposable user.
- Review at least one real schedule image on the iPhone. The synthetic physical test establishes model availability and execution, not accuracy on a real schedule.
- Check the signed app's interactive account flow and confirm existing local schedule data remains visible. The pre-install app container was copied and archived before installation.

The known-good Maroon Compass 1.4 (5) archive was made before this work and remains separate from the source integration.
