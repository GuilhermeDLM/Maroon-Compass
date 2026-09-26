# Project state

Updated: 2026-09-25

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

## Next safe actions

1. Create a disposable Supabase project, apply the migration, and run `supabase/tests/schedule_rls.sql`; fix any policy or RPC failures before enabling client sync.
2. Configure only project URL and publishable key for local builds. Add Auth session handling, Sign in with Apple under an eligible team, sign-out and account deletion, and explicit restore/conflict UI. Keep local mode independent.
3. Test image extraction on the paired iPhone with Apple Intelligence enabled and disabled, plus representative redacted schedule screenshots. Report actual runtime availability; simulator compilation does not establish it.
4. Add a versioned local history/rollback path before enabling recurring cloud sync, then verify offline retry and two-device conflicts.
5. The development build is now installed in place. Once the phone is unlocked, verify launch and the import screen, then test Apple Intelligence availability. If it fails, use the verified known-good ZIP for recovery and preserve the preference backup.

## Separate import-quality PR — 2026-09-26

The focused branch `gpt/schedule-import-quality-20260926` was created from PR #2
head `16249d96b56e876dd518491eb51d1bfd1379f7fa`. Its first pushed code
checkpoint is `0fa89ee77b72e5dab5adf69e5bc6a803712790c8`, in draft PR #3
targeting PR #2. The PR head shown by GitHub is authoritative after later
documentation or fix commits.

This branch changes `ScheduleDraft.swift`, `ScheduleImageImportService.swift`,
`ScheduleImportView.swift`, the existing QA launch route in `RootView.swift`,
focused tests, generated synthetic PNG fixtures, and `docs/IMPORT_QA.md`.
It does not change Settings, Supabase, Auth, sync, signing, or cloud UI. New
behavior protects an edited draft before another image replaces it, shows
field errors inline, blocks a room without a building and overlapping or
duplicate meetings, and keeps adjacent meetings valid. The OCR fallback now
associates repeated course headers with the correct course and transcribes
visible building/room text without normalizing ambiguous characters.

The synthetic fixtures and evaluation protocol are described in
`docs/IMPORT_QA.md`. The first GitHub Xcode 27 workflow run
<https://github.com/GuilhermeDLM/Maroon-Compass/actions/runs/36221399933>
compiled the Debug targets but produced no test output after nine minutes;
it was canceled and the workflow was changed to run simulator tests serially.
No new test count, simulator UI result, signed build, physical install,
physical launch, or Apple Intelligence accuracy is claimed from that run.
The Windows checkout has no Swift/Xcode toolchain. Continue with the serial
workflow result, fix any failures on this branch, inspect the compiled
light/dark import screenshots, then have the integrator handle signing and
device verification. Keep PR #3 draft until those source and simulator gates
are recorded.
