# Cross-branch integration QA — 2026-09-26

## Inputs and scope

A disposable macOS checkout combined these exact GitHub heads:

- Import quality: `gpt/schedule-import-quality-20260926` at `78723e0db2140d0c2a335a20c90d53d68a2cc685` (PR #3).
- Local recovery: `codex/local-schedule-recovery-20260926` at `f0bb47730f0fc57346d3e6fdd89af36fa9e5650b` (PR #4).
- Optional Google account draft: `codex/google-auth-20260926` at `07054a4d08b2dd2cf49d7d3ed7e84da24cb57a59` (PR #5).
- Opus cloud sync: `claude/maroon-compass-backend-auth-c1m1yh` at `d4e091a4e0c0bc53b65a657145771bd071d83aae`.

The QA checkout overlaid PR #3's import source/tests/fixtures on PR #5, then overlaid Opus's cloud source/tests. It removed PR #5's duplicate `CloudAccountStore.swift` and `CloudAccountTests.swift` from this *disposable copy* only. Opus's custom session/sync architecture was used for this test; PR #5's SDK Google account implementation was not assumed to be merged.

## Required source reconciliation

1. `MaroonCompass/Services/Cloud/AppStoreScheduleAccess.swift`: change the `.embedded` rollback path to `try store.restoreEmbeddedSchedule()`. PR #4 made this API throwing so an archive write failure cannot silently lose the active schedule.
2. `MaroonCompass/Views/SettingsView.swift`: retain PR #4's “Previous schedules” navigation, handle `restoreEmbeddedSchedule()` with an error alert, and describe that the current imported schedule is archived before restoring the embedded one. Opus's Settings replacement currently drops this recovery UI.
3. `MaroonCompassTests/ScheduleDraftTests.swift`: PR #3's cloud test uses PR #2's old `CloudScheduleSnapshot(semesterID:bundle:)` signature and nested `courses[].meetings` wire format. Opus's lossless model uses `CloudScheduleSnapshot(bundle:fallbackTerm:)` and top-level `meetings` and `events`. The test was adapted to assert that a reviewed photo's weekday/time fields survive and that a calendar one-time event round-trips. The earlier “rejects lossy calendar import” assertion is obsolete because Opus now preserves those events.
4. Keep exactly one `CloudAccountView` and one session architecture. Do not merge PR #5's `CloudAccountStore` wholesale with Opus's `CloudAccountModel` / `CloudSessionManager`. Adapt Google OAuth with PKCE and `marooncompass://auth/callback` into the chosen architecture, then remove the unused Supabase Auth package/configuration if it is no longer used.

## Verification performed

- PR #3 import source and fixtures plus PR #4 and PR #5 source, before Opus overlay: simulator tests passed.
- Combined import, recovery, and Opus cloud source after the three source/test reconciliations above: **76 simulator tests passed** on Xcode 27.0, iPhone 17 Pro simulator.
- Combined unsigned **Release iOS Simulator build succeeded**.
- No simulator compiler warning or error appeared in the successful Release build.
- These are disposable-checkout results, not a pushed integrated branch, device installation, or live Supabase test. The actual integration commit needs a fresh run after Google OAuth replaces Apple-specific code.

## Outstanding gates

- Opus's current cloud account code and `supabase/config.toml` still target Sign in with Apple. The current Personal Team cannot provision that capability. The user chose Google sign-in; the decision and setup details are in `AGENTS.md` on Opus's branch and `docs/GOOGLE_AUTH_HANDOFF.md` on PR #5.
- No Supabase project or Google OAuth Web client is configured, so live login, token refresh, account deletion, RLS migration, cloud sync, offline retry, and two-device conflicts remain unverified. Do not auto-upload schedules at sign-in.
- Apple Intelligence extraction and the updated screens still need a physical iPhone launch and representative redacted schedule images. Simulator compilation does not establish runtime availability.
- Preserve the known-good signed app archive and the existing installed user data until a replacement signs, installs, launches, and is verified.
