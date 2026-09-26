# Schedule import and cloud backup

## Local import (unchanged)

The app reads a selected photo locally with Vision. Foundation Models interprets the image on supported, enabled devices; an OCR parser provides a draft elsewhere. The student reviews and edits every course and meeting before confirming. Confirmation saves the structured schedule to the existing on-device store. The image and OCR text are not persisted or uploaded. Local import works without any account.

## Cloud backup model

Cloud backup is optional and local-first. The device's schedule is always the one the app uses; the cloud holds a copy only when the student asks for it. Accounts use Google sign-in through Supabase Auth (PKCE, identity scopes only; see `docs/SUPABASE_SETUP.md`); ownership is the Supabase user ID, never the email address.

- **What is stored:** the confirmed class schedule — term, courses (including Howdy metadata), weekly meetings (including EXDATE/RDATE lists, UNTIL text, notes, rooms), and one-time events — keyed by the app's own identifiers so a restored schedule keeps building assignments and calendar-export tracking. The embedded Howdy schedule, `.ics` imports, and reviewed photo imports all round-trip without loss (tested against the real database).
- **What is never stored:** photos, OCR text, `.ics` diagnostic properties, Personal Plan, saved places, favorites, location, reminders, manual building overrides.
- **Schedules the cloud cannot represent** (for example a calendar that repeats an event UID, or a meeting that crosses midnight) stay local, and the account screen says why. Nothing is dropped or rewritten to make it fit. Weekday and date lists are stored sorted and de-duplicated, which does not change their meaning.

## Sync rules

The device remembers the cloud version and content it last agreed with. Each refresh compares the device, that record, and the cloud:

| Device changed | Cloud changed | State | What the student can do |
| --- | --- | --- | --- |
| no | no | Up to date | — |
| yes | no | Local changes | Upload changes |
| no | yes | Remote changes | Restore the cloud copy, or keep this device's schedule |
| yes | yes | Conflict (unless both are now identical) | Restore the cloud copy, or keep this device's schedule |
| not linked, cloud copy of this term differs | | Cloud copy available | Restore it, or replace it with this device's schedule |
| not linked, no cloud copy of this term | | Not backed up | Back up |
| linked, cloud copy deleted elsewhere | | Deleted | Back up again |

- Nothing is overwritten automatically. Every write names the version the student reviewed; if the cloud moved on, the write fails and the screen shows the latest state.
- Restoring saves the previous local schedule first. "Undo restore" is offered only while the local schedule is still exactly what was restored.
- A second device with the identical schedule links silently (no write). A different schedule on a second device never creates a duplicate: the database allows one semester per term start date per account.
- An upload that fails for connectivity is retried the next time the account screen loads or refreshes, including when the app returns to the foreground with that screen open, and only while the situation is still "not backed up" or "local changes". There is no background sync. A write whose response was lost is recognized on the next refresh instead of being sent again.
- Signing out keeps the device's schedule and the cloud copies, and forgets sync metadata. Deleting the account deletes the Auth user and, by cascade, every cloud row; the device's schedule is not changed. Deleting the cloud copy removes only that semester, and only at the reviewed version.

## Database contract

See `supabase/migrations/202609260001_schedule_sync.sql`.

- `replace_schedule_snapshot(p_semester_id, p_expected_version, p_snapshot)` — atomic replace; `p_expected_version` is null only when creating. Returns `{semester_id, sync_version, updated_at}`. Errors: 409 `schedule_version_conflict` / `schedule_exists` / `schedule_missing`; 400 `invalid_snapshot` / `semester_limit_reached`; 403 `authentication_required`.
- `get_schedule_snapshot(p_semester_id)` — the full snapshot from one database snapshot, or null.
- `list_schedule_semesters()` — summaries with version, update time, and course count.
- `DELETE /rest/v1/semesters?id=eq.<id>&sync_version=eq.<v>` with `Prefer: return=representation` — versioned deletion under RLS.

Snapshot format 1 uses snake_case keys matching `CloudScheduleSnapshot` in `MaroonCompass/Services/SupabaseScheduleRepository.swift`. Times are `HH:mm`, dates `yyyy-MM-dd`, timestamps UTC with milliseconds.

## Code map

| Concern | File |
| --- | --- |
| Configuration, transport, formats | `MaroonCompass/Services/Cloud/CloudConfiguration.swift` |
| Auth client (Google PKCE, refresh, sign-out, deletion), session model, errors | `MaroonCompass/Services/Cloud/CloudAuth.swift` |
| Session state and refresh | `MaroonCompass/Services/Cloud/CloudSessionManager.swift` |
| Keychain storage, app services | `MaroonCompass/Services/Cloud/KeychainSessionStore.swift` |
| Snapshot and REST repository | `MaroonCompass/Services/SupabaseScheduleRepository.swift` |
| Sync decisions and actions | `MaroonCompass/Services/Cloud/CloudScheduleSync.swift` |
| Bridge to `AppStore` | `MaroonCompass/Services/Cloud/AppStoreScheduleAccess.swift` |
| UI state | `MaroonCompass/Services/Cloud/CloudAccountModel.swift` |
| Screen | `MaroonCompass/Views/CloudAccountView.swift` (linked from Settings) |

Setup and verification commands are in `docs/SUPABASE_SETUP.md`; the security review is in `docs/BACKEND_SECURITY_REVIEW.md`.

## Model handoff

One integrator owns `main` and merges tested branches. The backend branch owns `supabase/**`, the cloud Swift files above, their tests, and these documents. Screenshot extraction work should avoid those files; the backend branch does not edit `ScheduleImageImportService.swift`, `ScheduleDraft.swift`, or `ScheduleImportView.swift`. Share the branch name, base commit, tests, and unresolved gates at every handoff.
