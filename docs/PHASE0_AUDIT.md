# Maroon Compass — Phase 0 repository audit

**Audited:** September 25, 2026  
**Scope:** Existing native iPhone/iPad application, its private GitHub repository, and the locally paired iPhone. This is an implementation checkpoint, not a claim of App Store readiness.

## 1. How the app works today

Maroon Compass is a local-first Texas A&M day and campus companion. It boots with a verified Fall 2026 schedule. **Today** shows upcoming classes, countdowns, gaps, and route context. **Schedule** shows the week and day agenda, course details, academic exceptions, and class transitions. **Plan** holds separate personal blocks. **Map** searches campus buildings and parking plus Apple Maps places/routes. **Saved** holds favorite places and campus features. **Settings** contains an optional Howdy `.ics` import, reminder, travel, and privacy controls.

The app also contains a next-class widget, App Shortcuts, optional local notifications, and per-course Apple Calendar export. There is no screenshot/photo schedule import, manual course editor, account, backend, or cloud sync yet.

## 2. Current architecture and reusable parts

| Area | Current implementation | Reuse decision |
| --- | --- | --- |
| UI/navigation | SwiftUI six-tab `RootView`; `@Observable` main-actor `AppStore` | Keep the product shell and established views. Add schedule editing/review routes within it. |
| Schedule domain | `Course`, `MeetingPattern`, `OneTimeEvent`, `Term`, `Weekday`, `ScheduleOccurrence` in `ScheduleModels.swift` | Evolve with versioned migration. Preserve stable source meeting IDs, verified seed data, and academic exceptions. |
| Calendar logic | Pure `ScheduleEngine` expands campus-time recurrence and computes next class, gaps, conflicts | Reuse; generalize the term boundary and test more schedule shapes. |
| Schedule intake | `ICSImportService` parses Howdy calendar data into `ImportedScheduleBundle` | Reuse parser and source context. Make review/commit explicit for all new import paths. |
| Local state | `UserDefaults` stores imported schedule, assignments, preferences, favorites, and personal blocks | Preserve existing keys/data. Introduce a versioned schedule repository before mutable schedules and sync. |
| Campus data | `CampusGISService` fetches official TAMU ArcGIS buildings/parking and atomically caches JSON; `AppStore` matches known abbreviations | Reuse canonical dataset and matching; keep unknown locations unknown. |
| Routes/places | MapKit and Apple Maps services | Reuse for next-class directions after a confirmed building match. |
| Calendar export | EventKit write-only permission, one event per occurrence, local identifier tracking | Reuse the permission boundary; add a preview and more durable duplicate handling before general export. |
| Widget | WidgetKit/App Intents; embedded schedule only | Keep working seed widget. An imported/user schedule needs a deliberate shared-data capability and migration. |
| Tests | 21 preexisting `ScheduleEngineTests` covering seed, recurrence, ICS, time zone, and personal plan | Keep and expand for domain validation, persistence, manual editing, and import fixtures. |

The project has no third-party packages. It targets **iOS 18.0**, uses **Swift 6**, and was tested with **Xcode 27.0**. Existing location and Calendar usage descriptions are present. The project is intentionally iOS/iPadOS despite the parent workspace's usual macOS default.

## 3. Architectural risks and changes needed

1. **Data preservation:** Startup previously removed the imported schedule whenever the embedded seed revision changed. This is fixed in the first Phase 1 checkpoint. The imported bytes and its building assignments now survive; old seed-only assignments can still be pruned.
2. **Single-term assumptions:** `Term` and `ScheduleSeed` bind the app to one Fall 2026 semester. Add stable semester identity and boundaries while retaining current seed and exception behavior.
3. **Mutable schedule model:** Course/meeting IDs are strings tied to source data; meeting type, normalized building reference, and validation are not first-class. Add those without invalidating existing Codable records.
4. **Import confirmation:** Existing `.ics` import directly replaces active schedule. The new image path must stage a draft, mark uncertain fields, allow complete editing, and commit only after explicit confirmation.
5. **Persistence/sync:** A single `AppStore` owns state, parsing, storage, and service coordination. Extract a small, versioned schedule repository with atomic local writes and explicit migration. Add cloud sync only after local manual editing is reliable.
6. **Widget divergence:** The widget intentionally reads only the embedded seed because there is no App Group entitlement. It cannot reflect imported or manually edited classes as shipped.
7. **Calendar accuracy:** Current export expands each class occurrence into an event and tracks IDs in `UserDefaults`. A future general schedule needs a creation preview, semester/weekday rules, and robust duplicate/update behavior when classes change.
8. **Release infrastructure:** Supabase, RLS policies, Sign in with Apple entitlement, account deletion, privacy/support URLs, and App Store distribution assets are absent. They are later-phase work, not currently functional.
9. **Repository continuity:** The working source directory's local `.git` has no commits or remote and includes pre-existing staged/unstaged changes. The private `GuilhermeDLM/Maroon-Compass` repository is the durable source of truth; its `AGENTS.md` and `docs/PROJECT_STATE.md` were read. Future work should use a focused remote branch and preserve the local changes rather than resetting them.

## 4. Proposed final architecture

`ScheduleEngine` remains the deterministic read model. A versioned local `ScheduleRepository` owns semesters, courses, meetings, source provenance, revisions, and atomic persistence. Import adapters (`ICS`, Vision OCR, and conditional Foundation Models) produce a **draft** plus field-level uncertainty, never a saved schedule. One validator checks time, weekday, duplicate, conflict, building, and semester rules. The review/editor owns the explicit commit. `CampusGISService` resolves confirmed building references. `CalendarExportService` consumes confirmed schedule data only. A later `SyncService` translates repository changes to authenticated Supabase rows with RLS and conflict rules; local data remains usable offline. Authentication and sync state stay separate from screen state.

The current models, views, seed, calendar engine, campus services, and working integrations should be adapted incrementally. No broad rewrite is warranted.

## 5. Exact implementation sequence

1. **Phase 1 — domain:** Complete migration-safe semester, course, meeting, time, type, and building-reference values. Add deterministic validation and regression tests for today/next/conflicts/gaps and legacy decoding. Keep the existing seed and widget behavior intact.
2. **Phase 2 — manual schedule:** Build local add/edit/delete for courses and meetings. Add a versioned repository, import staging, explicit save, migration tests, and offline recovery.
3. **Phase 3 — photo import:** Add PhotosPicker and image preview, local Vision OCR, deterministic parsing, conditional structured Foundation Models interpretation, field-level uncertainty, editable review, and explicit confirmation. Evaluate realistic fixture images field by field.
4. **Phase 4 — daily experience:** Feed confirmed schedules into existing Today/Schedule/Map views, resolve building codes against campus GIS, and retain useful unknown-location states.
5. **Phase 5 — Calendar:** Preview optional exports, create correct bounded recurrences or verified occurrence sets, and make re-export/update behavior predictable.
6. **Phase 6 — backend:** Create a Supabase project configuration boundary, SQL migrations, ownership relationships, and RLS policies/tests. Keep screenshots local.
7. **Phase 7 — authentication/sync:** Add Sign in with Apple, guest mode, sign-out, account deletion, offline-first sync, retry, and conflict handling after the required Apple capability and backend are available.
8. **Phase 8 — polish:** Complete accessibility, loading/failure states, design consistency, performance review, and dark/light mode QA.
9. **Phase 9 — TestFlight:** Use a distribution-capable Apple Developer Program team; validate real supported/unsupported devices, permission denial, offline behavior, auth, deletion, and reinstall.
10. **Phase 10 — release audit:** Review security, privacy, RLS, accessibility, crashes, signing, metadata, and policy requirements; resolve all critical/high findings before submission.

## 6. Apple access and availability checked now

- The paired **iPhone 15 Pro runs iOS 27.0** with Developer Mode enabled. Hardware/OS meet the broad prerequisites for newer Apple Intelligence features, but the phone's Apple Intelligence setting and on-device model readiness were **not** verified. The implementation must check `SystemLanguageModel.availability` at runtime. [Apple Foundation Models availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images) can process schedules on device. [PhotosPicker](https://developer.apple.com/videos/play/wwdc2023/10053/) grants access to selected images without broad photo-library permission. Both should remain useful when generative models are unavailable.
- The existing [Calendar integration uses write-only EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store). The usage description is configured; each person still controls the iOS permission prompt.
- Current provisioning is a **Personal Team** installation. Its profile had about 44 hours remaining, so the guarded renewal workflow rebuilt, strictly verified, and wirelessly reinstalled the known-good **1.4 (5)** build. The renewed installed profile expires **October 3, 2026 at 02:52 UTC**. The renewal script intentionally did not launch the app. [Apple says Personal Team profiles expire after seven days](https://developer.apple.com/support/compare-memberships/).
- The app has **no Sign in with Apple or App Group entitlement**, and neither feature is wired into this build. [Apple requires a Sign in with Apple capability](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple) and [an App Group for shared app/widget storage](https://developer.apple.com/documentation/Xcode/configuring-app-groups). A paid [Apple Developer Program membership is needed for TestFlight/App Store distribution](https://developer.apple.com/support/compare-memberships/); current Personal Team signing cannot submit a public release.

## 7. Verification for the first Phase 1 checkpoint

- Baseline: **21/21 simulator tests passed**.
- After the imported-schedule preservation fix and two regression tests: **23/23 simulator tests passed**. The strengthened old-seed-location test was then rerun and passed.
- This is source and simulator evidence. It does not claim that the new source is signed or installed on the physical iPhone.
