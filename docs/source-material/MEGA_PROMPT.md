# Maroon Compass — Production iOS App Mega Prompt

Copy everything below this line into a capable coding agent. The prompt is self-contained; the attached calendar does not need to travel with it.

---

## Role and operating mode

Act as a senior iOS product team: product manager, UX designer, Swift engineer, GIS/data engineer, accessibility specialist, QA engineer, and release engineer. Build the complete app described below. Do not stop after planning, wireframes, scaffolding, or sample screens. Make reasonable, reversible product decisions without asking routine questions. If a source field is unknown, preserve it as unknown and design a polished way for the user to fill it in; never invent data.

This is explicitly an **iOS app**, which overrides any general macOS-default instruction. Build a native iPhone and iPad app with Swift and SwiftUI. Do not use React Native, Flutter, a web wrapper, or Mac Catalyst.

## Product brief

Build **Maroon Compass**, a private, local-first campus companion for a Texas A&M University student in College Station during Fall 2026. It combines:

1. An exceptionally clear weekly class schedule.
2. A complete campus map with searchable buildings, routes, accessibility features, parking, bus stops, construction, emergency resources, and essential student services.
3. Nearby on-campus dining and surrounding restaurants, discovered dynamically rather than maintained as a stale hard-coded list.
4. Contextual “what should I do next?” intelligence based on the next class, walking time, free gaps, current time, weather, and nearby useful places.

The product should feel like a professionally commissioned, calm, fast, trustworthy iOS app—not a demo. The app is unofficial and must not imply endorsement by Texas A&M University.

### Working identity

- Product name: **Maroon Compass**
- Suggested bundle identifier: `com.guilhermemachado.MaroonCompass`
- Visual character: warm, confident, collegiate, contemporary, and highly legible.
- Use an accessible deep-maroon accent inspired by the campus context, but do not copy Texas A&M logos, seals, protected marks, or trade dress without documented permission.
- Create an original app icon combining a compass/route motif with a subtle calendar grid. It must remain readable at small sizes and work in light, dark, tinted, and monochrome icon treatments where supported.
- Add a small “Unofficial student companion” label in About and source/attribution surfaces.

## Primary user outcome

At any moment, the user should be able to answer these questions within one or two taps:

- What is my next class or exam?
- When should I leave?
- Where is it?
- How do I get there?
- What free time do I have before it?
- Where can I eat, study, print, refill water, get help, or wait nearby without risking being late?
- What changes today because of a holiday, reading day, redefined class day, or finals week?

## Source-of-truth personal schedule

The following data was extracted from a Howdy-generated iCalendar file named `schedule.ics` on 2026-08-18. The source has `PRODID:-//TAMU//Howdy//EN`, method `REQUEST`, timezone `America/Chicago`, and no `LOCATION`, instructor, room, or CRN fields.

### Normal weekly schedule

Render the week in this order and use distinct, accessible course colors that remain distinguishable without color.

| Day | Time | Course | Section | Display title |
|---|---:|---|---:|---|
| Monday | 9:10–10:00 AM | POLS 207 | 502 | State and Local Government |
| Monday | 11:30 AM–12:20 PM | MATH 151 | 531 | Engineering Mathematics I |
| Monday | 3:00–3:50 PM | FYEX 101 | 537 | First Year Experience |
| Monday | 5:10–6:00 PM | ENGR 102 | 505 | Engineering Lab I – Computation |
| Monday | 6:01–7:00 PM | ENGR 102 | 505 | Engineering Lab I – Computation |
| Tuesday | 8:00–9:15 AM | CHEM 107 | 504 | General Chemistry for Engineering Students |
| Tuesday | 11:10 AM–2:00 PM | CHEM 117 | 541 | General Chemistry for Engineering Students Laboratory |
| Tuesday | 3:55–5:10 PM | MATH 151 | 531 | Engineering Mathematics I |
| Wednesday | 9:10–10:00 AM | POLS 207 | 502 | State and Local Government |
| Wednesday | 11:30 AM–12:20 PM | MATH 151 | 531 | Engineering Mathematics I |
| Wednesday | 5:10–7:00 PM | ENGR 102 | 505 | Engineering Lab I – Computation |
| Thursday | 8:00–9:15 AM | CHEM 107 | 504 | General Chemistry for Engineering Students |
| Thursday | 3:55–5:10 PM | MATH 151 | 531 | Engineering Mathematics I |
| Friday | 9:10–10:00 AM | POLS 207 | 502 | State and Local Government |

Preserve the two Monday ENGR 102 source meetings as separate records because their source UIDs differ. In the visual week grid, they may appear as one 5:10–7:00 PM block with a subtle internal divider and detail text explaining that the source has two adjacent components separated by one minute.

### One-time MATH 151 events

Treat these as one-time events, not semester-long weekly meetings:

| Date | Time | Course | Likely purpose |
|---|---:|---|---|
| Thursday, September 17, 2026 | 5:30–6:45 PM | MATH 151-531 | Special course meeting/exam; source does not explicitly label the purpose |
| Thursday, October 22, 2026 | 5:30–6:45 PM | MATH 151-531 | Special course meeting/exam; source does not explicitly label the purpose |
| Thursday, November 19, 2026 | 5:30–6:45 PM | MATH 151-531 | Special course meeting/exam; source does not explicitly label the purpose |

In UI copy, call these “Special MATH 151 meeting” until the user renames them. Do not assert that they are exams merely because the pattern suggests it.

### Official Fall 2026 academic-calendar rules

Use these as schedule exceptions and informational milestones. The university states that dates can change, so retain a “Verified from official calendar” source link and a last-checked date.

- August 24: first day of fall classes.
- August 28: last day to add/drop fall courses.
- September 7: Labor Day; no classes.
- September 9: official census date.
- September 21: undergraduate change-of-curriculum request deadline.
- September 25: deadline to apply for December graduation without a late fee.
- September 30: undergraduate degree-plan approval deadline.
- October 12 at noon: mid-semester grades due.
- November 4: last day to apply online for December 2026 graduation.
- November 5–20: preregistration for Spring 2027.
- November 16 at 5:00 PM: Q-drop, grade-type-change, and university-withdrawal deadline.
- November 18: Bonfire 1999 Remembrance Day; this is an observance, not a no-class day.
- November 25: reading day; no classes.
- November 26–27: Thanksgiving holiday; no classes.
- December 1: redefined day; students attend their **Friday** classes. Suppress the normal Tuesday pattern and instantiate Friday’s pattern for this date. For this user, that means POLS 207 from 9:10–10:00 AM unless the user adds other Friday events.
- December 2: classes continue, but the university’s no-regular-exams rule begins for the remaining class days, subject to stated exceptions.
- December 3: last day of fall classes. Suppress normal recurring class meetings after this date even though the raw Howdy recurrence `UNTIL` values extend into finals week.
- December 4: reading day; no classes.
- December 7–10: final examinations. The source calendar does **not** include the user’s final-exam assignments, so show a prominent but non-alarming “Final exam times not added” state and an Add/Import action. Never invent final times or locations.
- December 11–12: commencement and commissioning.
- December 14 at noon: final grades due.

### Course metadata from the 2026–2027 catalog

- **CHEM 107-504 — General Chemistry for Engineering Students**: 3 credits, 3 lecture hours. Important chemistry concepts and principles with emphasis on engineering context and applications. It is paired with CHEM 117.
- **CHEM 117-541 — General Chemistry for Engineering Students Laboratory**: 1 credit, 3 lab hours. Laboratory applications of chemistry concepts relevant to engineering and technology; CHEM 107 is a prerequisite or corequisite.
- **ENGR 102-505 — Engineering Lab I – Computation**: 2 credits, 1 lecture hour and 3 lab hours. Design and development of computer applications for engineers; computation, problem solving, software design, implementation/debugging, engineering-major exploration, professional practice, ethics, health and safety, sustainability, and pathways to success.
- **FYEX 101-537 — First Year Experience**: 0 credits, satisfactory/unsatisfactory. Self-efficacy, self-awareness, purpose, engagement in learning, and social integration in the university community.
- **MATH 151-531 — Engineering Mathematics I**: 4 credits, 3 lecture hours and 2 lab hours. Rectangular coordinates, vectors, analytic geometry, functions, limits, derivatives, applications, integration, and computer algebra.
- **POLS 207-502 — State and Local Government**: 3 credits, 3 lecture hours. State and local government and politics, with particular reference to the constitution and politics of Texas.
- Known total: **13 semester credits**.

Do not infer the user’s major, instructor, room, building, CRN, residence, meal plan, parking permit, mobility requirements, or transportation mode from this data.

### Exact embedded seed data

Use this JSON (or an equivalent strongly typed local resource) as the idempotent first-launch seed. Preserve source UIDs so reimporting the same calendar does not duplicate records.

```json
{
  "schemaVersion": 1,
  "source": {
    "name": "schedule.ics",
    "producer": "-//TAMU//Howdy//EN",
    "calendarMethod": "REQUEST",
    "calendarTimeZone": "America/Chicago",
    "sourceTimestampUTC": "2026-08-18T20:25:03Z",
    "locationsProvided": false
  },
  "term": {
    "institution": "Texas A&M University",
    "campus": "College Station",
    "name": "Fall 2026",
    "firstClassDate": "2026-08-24",
    "lastClassDate": "2026-12-03",
    "finalsStartDate": "2026-12-07",
    "finalsEndDate": "2026-12-10",
    "timeZone": "America/Chicago"
  },
  "meetingPatterns": [
    {"uid":"52dfe775-292f-4166-a87f-9fb574d05e0b","course":"CHEM-107-504","days":["TU","TH"],"start":"08:00","end":"09:15","sourceUntilUTC":"2026-12-10T15:15:00Z"},
    {"uid":"375e47cc-d616-4cdb-99e1-b159b2ceefc7","course":"CHEM-117-541","days":["TU"],"start":"11:10","end":"14:00","sourceUntilUTC":"2026-12-10T20:00:00Z"},
    {"uid":"021400c7-8ea4-4f5a-a69e-4e7cadec98fa","course":"ENGR-102-505","days":["MO"],"start":"17:10","end":"18:00","sourceUntilUTC":"2026-12-11T00:00:00Z"},
    {"uid":"59e3847c-c41f-47cf-b99f-a5529eda24b9","course":"ENGR-102-505","days":["WE"],"start":"17:10","end":"19:00","sourceUntilUTC":"2026-12-11T01:00:00Z"},
    {"uid":"25571d5d-ab8c-408d-81b3-f2b6553574b3","course":"ENGR-102-505","days":["MO"],"start":"18:01","end":"19:00","sourceUntilUTC":"2026-12-11T01:00:00Z"},
    {"uid":"ad304b0d-58d2-44e0-af37-1f3ead149fee","course":"FYEX-101-537","days":["MO"],"start":"15:00","end":"15:50","sourceUntilUTC":"2026-12-10T21:50:00Z"},
    {"uid":"117116d5-28bf-4d80-bdda-15d648ae23bc","course":"MATH-151-531","days":["TU","TH"],"start":"15:55","end":"17:10","sourceUntilUTC":"2026-12-10T23:10:00Z"},
    {"uid":"0abe17c7-e4fd-44a2-bf00-5499b655ddcc","course":"MATH-151-531","days":["MO","WE"],"start":"11:30","end":"12:20","sourceUntilUTC":"2026-12-10T18:20:00Z"},
    {"uid":"a132c235-725e-42e2-9df5-d47d3c06680c","course":"POLS-207-502","days":["MO","WE","FR"],"start":"09:10","end":"10:00","sourceUntilUTC":"2026-12-10T16:00:00Z"}
  ],
  "oneTimeEvents": [
    {"uid":"64574d25-5887-4949-9843-fe709564f0ce","course":"MATH-151-531","date":"2026-09-17","start":"17:30","end":"18:45","title":"Special MATH 151 meeting"},
    {"uid":"e1211fb3-71cd-4244-9f33-db890053614d","course":"MATH-151-531","date":"2026-10-22","start":"17:30","end":"18:45","title":"Special MATH 151 meeting"},
    {"uid":"e862bc29-8d2e-4822-b590-c7e4ffd3b25f","course":"MATH-151-531","date":"2026-11-19","start":"17:30","end":"18:45","title":"Special MATH 151 meeting"}
  ]
}
```

### Calendar-import correctness requirements

Support importing later `.ics` files through a document picker. Parse locally; do not upload the calendar. Support at minimum `VEVENT`, `UID`, `SUMMARY`, `LOCATION`, `DESCRIPTION`, `DTSTART`, `DTEND`, `TZID`, `RRULE`, `UNTIL`, `BYDAY`, `EXDATE`, and `RDATE`. Preserve unknown properties for diagnostics without showing noisy raw data in the main UI.

The supplied Howdy file uses a semester-start `DTSTART` of Monday, August 24 even for recurrence rules whose `BYDAY` is Tuesday/Thursday. Treat `BYDAY` plus local start/end times as authoritative for weekly placement, with August 24 as the term anchor; do not create an erroneous Monday CHEM meeting. Log this normalization in an import report.

Convert UTC `UNTIL` values correctly across the November daylight-saving transition. All class display and recurrence logic uses the `America/Chicago` civil timezone, not the device’s current timezone. If the user travels, optionally show a secondary local-device timezone label but never shift the campus schedule silently.

Academic-calendar exceptions outrank raw weekly recurrence. Keep the original recurrence values for provenance, but generate actual occurrences using the official last-class date and exceptions listed above.

## Smart schedule organization

### Week view

- Default to a five-column Monday–Friday grid on iPad and an elegant day pager/compact week strip on iPhone.
- Keep time labels fixed while scrolling.
- Show current-time indicator, conflicts, travel buffers, one-time events, and academic-calendar exceptions.
- Use text/icon/pattern differences in addition to course color.
- Let the user zoom density from “Class blocks only” to “Full day.”
- A tap opens a course sheet with all meetings, source, notes, location state, route action, calendar export, and notification settings.

### Today and next-class intelligence

The Home screen should prioritize:

1. Next class/special event with countdown.
2. Location status: confirmed, user-entered, imported, or missing.
3. Estimated walk/drive/bus time and a “Leave by” time when enough data exists.
4. A route button.
5. Useful gap suggestions constrained by the time needed to reach the next class.
6. Today’s academic-calendar exception or milestone.

If a room is missing, show “Location not added” with a single clear Add Location action. Never route to a guessed department building.

### Useful known gaps

Use these only as an initial explanation of the feature; compute gaps dynamically from actual dated occurrences and travel buffers:

- Monday: 10:00–11:30 AM, 12:20–3:00 PM, and 3:50–5:10 PM.
- Tuesday: 9:15–11:10 AM and 2:00–3:55 PM.
- Wednesday: 10:00–11:30 AM and 12:20–5:10 PM.
- Thursday: 9:15 AM–3:55 PM; on the three special-event dates, only 20 minutes separate the normal MATH meeting and the 5:30 PM special meeting.
- Friday: normal classes end at 10:00 AM.

For a free gap, offer concise context cards such as “Enough time for lunch within a 10-minute walk,” “Quiet study nearby,” or “Leave in 18 minutes.” Only show a recommendation when travel estimates leave a configurable safety buffer. Avoid manipulative productivity scoring.

## Complete campus map

### Map experience

Use native MapKit as the primary interactive map. Center the initial experience on the Texas A&M College Station campus (approximately `30.6180, -96.3386`) and include main campus, west campus, the Health Science area, Northgate, Century Square, and nearby College Station/Bryan services. The user must be able to pan beyond that region normally.

Provide:

- Standard, hybrid, and imagery-appropriate map styles where the SDK permits.
- Search by official building name, abbreviation, number, address, category, or course-assigned location.
- Clustered, category-aware annotations.
- A polished bottom sheet with name, category, distance, walking ETA, current status when verifiable, accessibility information, favorite button, directions, share, call, and official-source link.
- “My classes” overlay and an optional day route connecting classes in order.
- Walking and driving routes through `MKDirections`; transit only when the route data is genuinely available. Never label a generic straight line as a route.
- A “Next class” map mode with the route, leave-by time, and nearby practical stops that fit the available gap.
- Graceful handling of denied or approximate location permission. The complete map and schedule must remain useful without location access.
- A visible data-attribution/source sheet.

### Official campus GIS data

Prefer official Texas A&M GIS services over scraping the Aggie Map web interface. Confirm terms of use and attribution before shipping. Query only public endpoints, cache conservatively, and provide a MapKit-only fallback.

Known official service starting points:

- Texas A&M base map ArcGIS REST service: `https://gis.tamu.edu/arcgis/rest/services/FCOR/TAMU_BaseMap/MapServer`
  - Known layers include garage parking (0), structure data (1), university buildings (2), non-university buildings (3), off-campus buildings (5), railroad (6), surface parking (9), restricted streets (11), steps (15), ramps/curb cuts (16), sidewalks (18), campus driveways (19), and road centerlines (20).
- Transportation ArcGIS REST service: `https://gis.tamu.edu/arcgis/rest/services/TS/TS_Main/MapServer`
  - Known layers include bus stops (0), route stop/start points (1), campus stops (2), construction (3), visitor kiosks (4), parking lots (6), and related transportation data.
- Official building directory: `https://aggiemap.tamu.edu/directory`
- Official interactive map: `https://aggiemap.tamu.edu/`

When supported, request GeoJSON with an output spatial reference of WGS84 (`outSR=4326`). Keep network DTOs separate from app domain models. Store source layer ID, source feature ID, fetch date, geometry version, and attribution. Do not silently merge similarly named buildings.

For official campus features not exposed by a stable documented endpoint—such as accessible entrances, emergency phones, live bus positions, construction, lactation rooms, or sustainability infrastructure—either:

1. Use a verified public official service with attribution and error handling, or
2. Deep-link to the exact official Aggie Map layer/page.

Never reverse-engineer private endpoints, scrape authenticated pages, require a NetID password, or ship copied proprietary map tiles.

### Map categories and filters

Include these organized categories; hide categories with no verified data instead of showing empty/fake pins:

- **Classes:** all confirmed course locations, next class, today’s route.
- **Academic:** university buildings, libraries, computer labs, tutoring/help centers, advising, study spaces, printers/scanners.
- **Food:** dining halls, campus retail dining, coffee, convenience markets, nearby restaurants, groceries, food pantry/resources.
- **Transportation:** bus stops/routes, visitor parking, garages/lots, bike parking/repair, accessible paths/entrances, ramps, curb cuts, construction and closures.
- **Health & wellness:** student health, counseling, pharmacy/urgent care searches, recreation, quiet/wellness spaces.
- **Safety:** blue-light emergency phones when an official layer is available, University Police, safety escort information, emergency medical services.
- **Essentials:** restrooms where verified, accessible/gender-inclusive restrooms where verified, water refill, ATMs, mail/shipping, charging, vending, lost and found.
- **Campus life:** Memorial Student Center, recreation, major landmarks, museums, gardens, athletics, student services, and visitor resources.

### Restaurants and dining

Do not hard-code a supposedly complete restaurant list. Businesses, hours, and status change. Use `MKLocalSearch`/MapKit points of interest at runtime for restaurants, cafés, bakeries, groceries, pharmacies, and convenience stores in and around campus. Offer these filters when the returned data supports them:

- Open now.
- Walking time: under 10, 20, or 30 minutes.
- Near current location, near next class, or near a chosen building.
- Restaurant, coffee, quick bite, grocery, pharmacy, or convenience.
- Dietary/cuisine tags only when verified by the place source; never infer allergens or claim a venue is safe for an allergy.
- Meal-plan/Dining Dollars/Maroon Meals acceptance only for official on-campus dining data that explicitly supports the claim.

Use Apple Maps place cards/attribution as required. For on-campus hours, menus, payment forms, and meal-plan information, link to the official Aggie Dining source. Show “Hours may vary; verify before leaving” if real-time status cannot be established.

## Student resource hub

Include a compact, searchable resource directory with source links and `tel:` actions. Seed the following verified information with `lastVerified: 2026-08-18`, but structure it so a future app release can update it safely:

- Emergency: **911**.
- Texas A&M University Police, non-emergency: **979-845-2345**.
- University Emergency Medical Services: **979-845-1525**.
- Corps of Cadets safety escort: **979-845-6789**. The official campus-safety page currently describes service during fall/spring from evening to morning on weekdays and all day on weekends; show the official page because hours can change.
- Dial-A-Nurse: **979-458-8379**.
- Student counseling after-hours: **979-845-2700**.
- University Health Services general contact: **979-458-4584**.
- Facilities/AggieWorks: **979-845-4311**.
- Transportation help line: **979-847-7433**.
- Parking/customer assistance: **979-862-7275**.
- Motorist assistance/enforcement dispatch: **979-845-0057**.
- University operator: **979-845-3211**.

Emergency and safety actions must be unmistakable, accessible, and resistant to accidental taps. Make clear that the app is not an emergency service. Do not add a custom emergency workflow that delays calling 911.

Also include official links for food resources, The 12th Can/pocket pantries, University Health Services, counseling, libraries, academic success, disability resources, student assistance, dining, transportation, maps, and current students. Keep the UI practical and nonjudgmental.

## Information architecture

Use five primary destinations:

1. **Today** — next class, leave-by time, today timeline, exception banner, useful gap suggestions, weather/travel note.
2. **Schedule** — day/week/agenda views, course details, special events, academic calendar, import/export.
3. **Map** — full map, search, layers, next-class route, day route, campus resource filters.
4. **Saved** — favorite buildings/places, recent searches, saved routes, pinned resources.
5. **Settings** — schedule data, location permissions, notifications, travel preferences, accessibility preferences, calendar integration, data sources, privacy, About.

On iPad, adapt to `NavigationSplitView` and take advantage of the wider map/schedule canvas. On iPhone, use a stable tab bar and sheets that preserve map context.

## First-run experience

Keep onboarding short and useful:

1. Explain that the Fall 2026 schedule is already loaded from the provided Howdy file.
2. Show a review screen with all six courses, 13 credits, and the three special MATH events.
3. Clearly identify that **all class locations are missing from the source**.
4. Offer “Add locations now” with official building search, or “Do this later.”
5. Ask for location permission only when the user activates ETA/navigation; explain the immediate benefit. Request When In Use, not Always.
6. Ask for notifications only when the user enables class/leave reminders.
7. Offer optional Calendar access/export only from the relevant feature. Do not request contacts, photos, microphone, camera, tracking, or unrelated permissions.

The app must be useful even if every optional permission is denied.

## Course-location workflow

Because the source contains no locations, make assignment polished:

- Search official campus buildings by name, number, or abbreviation.
- Let the user select a building, then enter an optional room.
- Show the chosen pin and official building identity before saving.
- Allow one location per meeting component, because a course may meet in different rooms on different days.
- Track provenance: imported, official-campus-directory selection, map-search selection, or manual coordinate.
- Allow clear/edit/undo.
- If the same course has several meetings, offer “Apply to all meetings” but do not default to doing so.

## Notifications, widgets, and system integration

- Local notifications for class start, user-defined prep time, special events, academic deadlines, and calculated leave-by time.
- Recalculate pending leave reminders when the user changes a location, travel mode, safety buffer, or schedule. Do not use continuous background location polling.
- A small/medium Home Screen and Lock Screen widget for next class and countdown, powered by WidgetKit and App Intents.
- App Intents: “What’s next?”, “Navigate to next class,” and “Show today’s schedule.”
- Optional EventKit export with stable identifiers and duplicate prevention. Do not modify the user’s system calendar unless they explicitly choose an export/add action.
- Deep links such as `marooncompass://today`, `/schedule/date/2026-09-17`, `/course/MATH-151-531`, and `/map/next`.
- If WeatherKit is available and properly entitled, show rain/heat context that affects walking. Otherwise omit it cleanly; never show fabricated weather.

## Visual and interaction design

- Use SwiftUI, semantic system colors, SF Symbols, and system typography.
- Build a small design system for spacing, corner radii, elevation/material, course colors, map annotation states, and feedback.
- Use maroon as an accent, not as a wall of dark color.
- Design complete light and dark appearances.
- Support Dynamic Type including accessibility sizes, VoiceOver, Voice Control, Switch Control, Reduce Motion, Increase Contrast, and Differentiate Without Color.
- Minimum 44×44-point interactive targets.
- Ensure the schedule remains comprehensible with grayscale or color-blindness.
- Use haptics sparingly for meaningful state changes, not decoration.
- Provide polished empty/loading/offline/error/permission-denied/no-results states.
- Avoid gamification, streaks, shame-based copy, mascots, fake social features, placeholder stats, or dead controls.

## Technical architecture

Use the simplest production architecture that cleanly separates domain logic, persistence, networking/GIS, and presentation.

Suggested technologies:

- SwiftUI for UI.
- Swift 6 strict concurrency where supported by the installed toolchain.
- MapKit and CoreLocation.
- SwiftData for local models and migrations.
- EventKit for optional calendar integration.
- UserNotifications.
- WidgetKit and App Intents.
- WeatherKit only if entitlement/configuration is available.
- `URLSession` with actors for official GIS/resource fetching.
- `OSLog` with privacy annotations; never log precise user location, full schedule content, or imported calendar text by default.

Suggested modules/services:

- `ScheduleDomain`: courses, meeting patterns, occurrence generation, exceptions, free-gap calculation.
- `CalendarImport`: RFC 5545 subset parser, normalization report, idempotent merge.
- `AcademicCalendar`: official term exceptions and milestone data.
- `CampusGIS`: ArcGIS REST clients, geometry decoding, attribution, caching.
- `PlacesSearch`: MapKit local search and nearby categories.
- `Routing`: ETA, travel modes, safety buffers, leave-by calculations.
- `ResourceDirectory`: verified contacts and official links.
- `Persistence`: SwiftData models, schema versions, migrations, favorites.
- `Notifications`: local scheduling and reconciliation.
- `DesignSystem`: colors, components, accessibility behavior.

Core models should include at least:

- `Term`
- `Course`
- `MeetingPattern`
- `DatedOccurrence`
- `OneTimeEvent`
- `AcademicException`
- `CourseLocation`
- `CampusFeature`
- `PlaceResult`
- `FavoritePlace`
- `ResourceContact`
- `TravelPreference`
- `ImportRecord`
- `SourceAttribution`

Do not introduce a backend, account system, analytics SDK, ad SDK, or third-party location tracker. No cloud sync is required for v1. If iCloud/CloudKit is considered later, it must be opt-in and preserve a fully local mode.

## Privacy and security

- All schedule and favorite data stays on device by default.
- No analytics, tracking, ads, telemetry, or crash upload unless the user explicitly requests it in a future scope.
- Never store or request Texas A&M NetID credentials.
- Never scrape the authenticated Howdy portal.
- Use HTTPS and App Transport Security.
- Validate imported files, cap file size/event counts, handle malformed recurrence rules, and avoid path traversal or decompression hazards.
- Treat restaurant details and campus GIS as untrusted network data; decode defensively.
- Store no secrets in source. If an Apple entitlement/service key is needed, document configuration without committing private credentials.
- Explain why location, notifications, or calendar access is requested and handle denial without degraded core functionality.

## Offline and failure behavior

- The complete personal schedule, academic exceptions, saved course locations, resource contacts, and favorites must work offline.
- Cache last-known campus feature metadata and show its age/attribution. Do not cache Apple Maps content in a way that violates terms.
- If campus GIS is unavailable, show the MapKit base map, saved locations, and official Aggie Map link.
- If routing fails, show destination and allow opening Apple Maps; do not make up an ETA.
- If restaurant search fails, keep on-campus official dining/resource links visible.
- If location permission is denied, support route planning from any manually chosen start.
- Network error copy must be actionable and preserve the user’s current context.

## Data freshness

- Every remotely sourced campus layer/resource should carry a source and last-updated/fetched timestamp.
- Use reasonable cache TTLs and conditional requests where available.
- Official sources outrank crowdsourced data for campus buildings, closures, safety, contacts, and meal-plan claims.
- Apple Maps is the runtime source for surrounding commercial places.
- Never show “open now,” live bus positions, construction status, or emergency availability without a fresh source and clear timestamp.

## Testing and verification

Create meaningful unit, integration, UI, and snapshot/visual tests. At minimum verify:

### Schedule and import tests

- The seed creates exactly six courses, nine normal meeting-pattern records, three one-time events, and 13 credits.
- CHEM 107 appears Tuesday/Thursday only, not Monday August 24.
- The two Monday ENGR source records are preserved without creating an overlap warning for their one-minute boundary.
- The three MATH special events occur only on September 17, October 22, and November 19.
- `America/Chicago` behavior remains correct before and after the November 1, 2026 daylight-saving transition.
- Labor Day, November 25, and Thanksgiving suppress classes.
- December 1 shows the Friday pattern and suppresses the Tuesday pattern.
- No recurring normal class appears after December 3.
- Finals week shows missing-final-times state instead of invented meetings.
- Reimporting the same UIDs is idempotent.
- A later event with the same UID and higher sequence updates instead of duplicates.
- Malformed or oversized ICS files fail safely with a useful report.

### Schedule intelligence tests

- Free gaps are calculated from dated occurrences, not hard-coded strings.
- Travel/safety buffers prevent recommendations that could make the user late.
- Unknown course location never produces a route or leave-by estimate.
- Notification reconciliation removes stale reminders after schedule/location changes.

### Map/data tests

- ArcGIS geometries are transformed/decoded into WGS84 correctly.
- Campus features preserve layer/feature identifiers and attribution.
- Stale/offline/cache/fallback states render correctly.
- Restaurant search respects selected anchor (current location, next class, or chosen building).
- No unsupported claim such as allergy-safe, meal-plan-eligible, open now, or live appears without source data.

### UI and accessibility tests

- Today, week schedule, course detail, map, place sheet, missing-location onboarding, offline, no-results, and permission-denied states.
- Small iPhone, large iPhone, and representative iPad layouts.
- Light, dark, increased contrast, Reduce Motion, and largest Dynamic Type sizes.
- VoiceOver order/labels/values for schedule blocks, maps, filters, contact actions, and emergency actions.
- Keyboard navigation on iPad.

## Build and delivery requirements

- Create a complete Xcode project with a stable checked-in shared scheme.
- Prefer an iOS 18.0 deployment target for broad compatibility unless the installed toolchain or a required API justifies a different target; document the decision.
- Build against the latest stable SDK installed in the environment.
- Support iPhone and iPad orientations appropriate to each layout.
- Use Swift Package Manager only for a dependency with clear value, an acceptable license, active maintenance, and a pinned version. Prefer Apple frameworks.
- Add a real app icon and complete privacy usage descriptions.
- Include a concise README with product purpose, architecture, data sources/attributions, privacy model, build/test commands, and how the embedded schedule/academic exceptions are updated.
- Include a data-source/attribution screen in the app.
- Build the Release configuration, run all tests, eliminate new actionable warnings, and visually inspect the actual running app in multiple representative states.
- Verify the exact Release artifact/simulator build delivered. If a physically connected, authorized iPhone and signing identity are available, install and launch it there; otherwise launch and verify on an iPhone simulator and clearly state the device-install limitation without pretending it was installed.
- Do not publish, submit to the App Store, create paid accounts, or use private credentials without explicit authorization.

## Acceptance criteria

The app is done only when all of the following are true:

1. The supplied Fall 2026 schedule is visible, accurate, organized, and exception-aware.
2. All source unknowns—especially rooms/buildings—are honestly represented and easy to complete.
3. The map covers the full College Station campus and surrounding useful areas, with building search, layers, saved locations, and reliable fallbacks.
4. Restaurants and nearby essentials are discovered dynamically with distance/ETA-aware filtering.
5. The next-class and free-gap experiences never recommend something that conflicts with the schedule or a required travel buffer.
6. Academic redefined days, holidays, reading days, and finals states behave correctly.
7. The app works meaningfully offline and with every optional permission denied.
8. Safety resources are accurate, sourced, accessible, and do not delay 911.
9. No NetID credentials, private portal scraping, analytics, ads, or fake real-time data exist.
10. Accessibility, light/dark appearance, iPhone/iPad adaptation, error states, and visual polish meet a professional production standard.
11. Automated tests cover the schedule edge cases above and pass.
12. A verified Release build exists and the exact delivered build has been launched and inspected.

## Official research sources

Use these as initial authoritative sources, then verify them during implementation because university data can change:

- Fall 2026 academic calendar: `https://catalog.tamu.edu/undergraduate/academic-calendar/`
- Texas A&M maps hub: `https://www.tamu.edu/maps/`
- Official Aggie Map: `https://aggiemap.tamu.edu/`
- Official building directory: `https://aggiemap.tamu.edu/directory`
- Campus base-map ArcGIS service: `https://gis.tamu.edu/arcgis/rest/services/FCOR/TAMU_BaseMap/MapServer`
- Transportation ArcGIS service: `https://gis.tamu.edu/arcgis/rest/services/TS/TS_Main/MapServer`
- Transportation Services: `https://transport.tamu.edu/`
- Dining overview: `https://www.tamu.edu/campus-community/dining.html`
- Campus safety: `https://www.tamu.edu/campus-community/campus-safety.html`
- Public safety contacts: `https://em.tamu.edu/emergency-communications/public-safety-contacts.html`
- University Health Services: `https://uhs.tamu.edu/`
- Food resources: `https://studentlife.tamu.edu/support/food-resources/`
- Current-student resources: `https://www.tamu.edu/current-students/`
- Course catalogs:
  - `https://catalog.tamu.edu/undergraduate/course-descriptions/chem/`
  - `https://catalog.tamu.edu/undergraduate/course-descriptions/engr/`
  - `https://catalog.tamu.edu/undergraduate/course-descriptions/fyex/`
  - `https://catalog.tamu.edu/undergraduate/course-descriptions/math/`
  - `https://catalog.tamu.edu/undergraduate/course-descriptions/pols/`

## Final instruction

Begin by restating a concise implementation plan and the acceptance criteria you will use internally. Then inspect the development environment, create the native project, implement every core flow, test it, run it, visually inspect it, and deliver a short evidence-based completion report. Do not return only code snippets or instructions for the user to finish the app. Do not invent missing schedule or campus data. Make the smallest complete, trustworthy, polished product that fully satisfies this prompt.

---

End of mega prompt.
