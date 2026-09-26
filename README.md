# Maroon Compass

Maroon Compass is a private, local-first iPhone and iPad campus companion for a Texas A&M University student’s Fall 2026 semester. It combines the supplied Howdy registration schedule with campus data, Apple Maps places and routes, academic-calendar exceptions, safety resources, widgets, Shortcuts, calendar export, and optional local reminders.

## Platform decision

This project intentionally targets native iOS and iPadOS, overriding the workspace’s normal macOS default because the user explicitly requested a full iOS app. It uses SwiftUI and an iOS 18.0 deployment target, building with the latest stable SDK installed locally. It does not use Mac Catalyst or a cross-platform UI framework.

## Shipped product surface

- Today dashboard with next-class countdown, campus-time awareness, academic exceptions, timeline, free-gap context, real route estimates, and calculated leave-by guidance.
- Schedule with all six courses, 12 credits, eight recurring source records, holidays, reading days, the December 1 redefined Friday schedule, finals-week missing-data handling, overlap warnings, and between-class transitions.
- Personal Plan with protected class meetings, customizable one-time and weekly blocks, weekday and date-range controls, overnight sleep support, category styling, optional notes and locations, quick-start templates, open-time suggestions, and class/personal conflict detection.
- Official Texas A&M building, garage, visitor-parking, and surface-lot search from public ArcGIS services. The map starts with a quiet visitor/garage layer while keeping the full parking inventory searchable.
- Apple Maps discovery for nearby food, coffee, groceries, and pharmacies, with configurable search anchor, walking-time filters, place details, calling, saving, sharing, and directions.
- Real MapKit route polylines for the next class and for a selected day’s class-to-class path. Walking or driving mode and a safety buffer are configurable.
- Complete Howdy course details—including enrollment status, CRN, subject, course number, section, credits, instruction mode, instructor, and every meeting location—are available from each course. Manual building overrides remain available.
- A private, on-device `.ics` re-import flow in Settings for future Howdy schedule updates; imports support `TZID`, UTC conversion, folded lines, `EXDATE`, `RDATE`, source notes, and location hints. Howdy recurrence anchors are normalized and saved locations remain intact.
- A screenshot/photo schedule import draft using Vision OCR, Foundation Models when available, validation, manual corrections, and explicit confirmation before local save. The OCR/manual path works when Apple Intelligence is unavailable.
- Per-course Apple Calendar export using write-only access, occurrence expansion, academic exceptions, and duplicate prevention.
- Home Screen and Lock Screen next-class widgets plus App Shortcuts for What’s Next, Today’s Schedule, and routing to the next confirmed class.
- Saved buildings, parking, places, class locations, recent searches, and a searchable directory of official academic, transportation, wellness, and emergency resources.
- Optional class, academic-exception, and route-aware leave reminders. Schedule and resource essentials remain usable offline.
- A high-contrast adaptive blue interaction system paired with a distinctive maroon compass-and-campus-path icon, working light/dark/tinted Home Screen renditions, Dynamic Type, VoiceOver labels, iPhone/iPad layouts, offline schedule operation, and cached campus metadata.

## Architecture

- `Models/`: schedule, occurrence, route, campus, place, location, and resource domain values.
- `Data/ScheduleSeed.swift`: normalized user schedule and verified Fall 2026 academic exceptions.
- `Services/ScheduleEngine.swift`: campus-time recurrence expansion, exception precedence, next meeting, conflicts, and free-gap calculation.
- `Services/PersonalPlanEngine.swift`: local personal recurrence expansion, overnight handling, combined agendas, conflict detection, and open-time calculation.
- `Services/ICSImporter.swift`: defensive calendar parsing and recurrence normalization.
- `Services/ScheduleImageImportService.swift`: local OCR, structured Apple Intelligence extraction, and a deterministic review fallback.
- `Models/ScheduleDraft.swift`: editable class/meeting draft and validation before any schedule is replaced.
- `Services/SupabaseScheduleRepository.swift`: the lossless cloud snapshot of a confirmed schedule and its versioned Supabase transport.
- `Services/Cloud/`: optional account and cloud backup — configuration, Supabase Auth client (Google sign-in with PKCE), Keychain session storage, session refresh, local-first sync decisions, the `AppStore` bridge, and the account screen's state. Inactive unless the build bundles `SupabaseConfig.plist`.
- `Services/CampusGISService.swift`: official building and parking ArcGIS decoding with atomic local caching.
- `Services/PlacesSearchService.swift` and `RouteService.swift`: dynamic local search, ETA enrichment, and route calculation.
- `Services/CalendarExportService.swift`: explicit per-course EventKit export and duplicate tracking.
- `Services/MaroonCompassIntents.swift`: App Intents and system Shortcuts.
- `Services/AppStore.swift`: main-actor application state, preferences, favorites, and recent-search persistence.
- `Views/`: six-tab product UI and supporting flows; iPhone keeps Today, Schedule, Plan, and Map visible while Saved and Settings remain available under More.
- `MaroonCompassWidget/`: App Intent-powered Home Screen and Lock Screen widgets.

No third-party iOS dependencies, analytics, advertising, tracking, or NetID access are used. Optional cloud backup uses Supabase over plain HTTPS (`supabase/` holds the schema, tests, and account-deletion function); builds without `MaroonCompass/SupabaseConfig.plist` run entirely in local mode. See `docs/SCHEDULE_BACKEND.md` and `docs/SUPABASE_SETUP.md`.

## Data and privacy

Personal blocks, confirmed class locations, reminder preferences, export identifiers, recent searches, and favorites remain on device. The class schedule also stays on device unless the student signs in and backs it up; cloud backup stores only the confirmed schedule, never screenshots, OCR text, location, or the Personal Plan. Signing out keeps the device's schedule; deleting the account removes the account and every cloud copy. Schedule screenshots and OCR text are processed locally and are never sent to the backend. Personal blocks are stored separately from the imported class schedule, so editing or deleting them cannot alter a class meeting. Campus metadata comes from public Texas A&M GIS services and is cached with its fetch date. Commercial place results and routes come from Apple Maps at runtime. Precise user location is not logged or persisted.

The widget deliberately uses the embedded verified Fall 2026 schedule. Imported calendar changes and manual room overrides remain private to the main app because this local build does not request an App Group entitlement.

Live Transportation Services vehicle data is not presented when the official service is unavailable. Maroon Compass shows an explicit unavailable state and links to Transportation Services instead of fabricating bus positions or arrival times.

## Official sources

- Academic calendar: <https://catalog.tamu.edu/undergraduate/academic-calendar/>
- Aggie Map: <https://aggiemap.tamu.edu/>
- Campus GIS: <https://gis.tamu.edu/arcgis/rest/services/FCOR/TAMU_BaseMap/MapServer>
- Transportation: <https://transport.tamu.edu/>
- Dining: <https://www.tamu.edu/campus-community/dining.html>
- Campus safety: <https://www.tamu.edu/campus-community/campus-safety.html>

Maroon Compass is an unofficial student companion and is not affiliated with or endorsed by Texas A&M University.

## Build and test

```sh
xcodebuild -project MaroonCompass.xcodeproj -scheme MaroonCompass -destination 'platform=iOS Simulator,id=575638D2-8C30-4DAF-8CA7-D15FE6A02BDA' test
xcodebuild -project MaroonCompass.xcodeproj -scheme MaroonCompass -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Backend and cloud-client checks (Docker required; see `docs/SUPABASE_SETUP.md`):

```sh
supabase start && supabase test db        # pgTAP: RLS, privileges, RPC versioning, rollback
Tools/CloudHarness/run.sh                 # cloud Swift unit tests on Linux (Swift 6 strict concurrency)
MC_LIVE_SUPABASE_URL=… MC_LIVE_PUBLISHABLE_KEY=… MC_LIVE_SECRET_KEY=… Tools/CloudHarness/run.sh   # plus live tests against a local stack
```

There are no third-party iOS dependencies or generated dependency state. Automated tests cover class recurrence, exceptions, source normalization, campus civil time, DST, complete Howdy metadata, personal weekly and one-time recurrence, overnight blocks, conflict detection, local persistence, schedule draft validation, legacy decoding, lossless cloud snapshots of every schedule shape, session refresh and sign-out, and local-first sync decisions. `DerivedData` and local screenshots are excluded from source control.

## Personal Team renewal

The locally installed iPhone build uses an Apple Personal Team provisioning profile and must be renewed periodically. `Tools/RenewDeviceInstallation.zsh` provides an idempotent renewal workflow for the paired iPhone: it checks the last confirmed installation, creates and validates fresh profiles for both the app and widget when fewer than five days remain, verifies the Release signatures, installs over the paired local-network connection, and records success only after the device reports the installed app. It never launches the app, so a locked iPhone can accept the update.

Run `Tools/RenewDeviceInstallation.zsh --check-only` for a read-only status check. A Codex scheduled run uses `Tools/RenewDeviceInstallation.zsh`. The Mac must remain powered on, awake, logged in, and connected to the network; the iPhone must be paired and reachable on the same local network.

`Automation/com.guilhermemachado.marooncompass.renewal.plist` is also installed as a per-user macOS LaunchAgent. It runs a local no-usage check when the user logs in, once per hour while the Mac is awake, and at the two Tuesday renewal times. The catch-up check uses a 30-hour safety window, performs no Xcode build or device connection while the installed profile remains healthy, and runs independently of whether Codex is open. Calendar triggers delayed by sleep run after wake; a full shutdown is covered by the next login check. The renewal script uses a shared state file and process lock so the LaunchAgent and Codex schedule cannot perform overlapping installations.

Before installing the renewal agent on a new Mac, copy `Tools/RenewalConfig.example.zsh` to `Tools/RenewalConfig.local.zsh` and set the iPhone identifier reported by `xcrun devicectl list devices`. The local file is git-ignored so a personal device identifier is never committed.

The LaunchAgent uses a self-contained source copy in `~/Library/Application Support/Maroon Compass Renewal/Project` because macOS privacy controls prevent a standalone background shell from reading Documents directly. Run `Tools/InstallRenewalAgent.zsh` after future source updates to refresh that private copy and restart the agent; installation preserves the shared renewal state.

## Repository continuity

Read [AGENTS.md](AGENTS.md) and [docs/PROJECT_STATE.md](docs/PROJECT_STATE.md) before continuing. The iOS mega prompt is preserved in `docs/source-material/MEGA_PROMPT.md`. Keep the ignored renewal configuration and device identifier local.
