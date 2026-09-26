# Schedule import and backend checkpoint

## Current behavior

The app reads a selected photo locally with Vision. Foundation Models interprets the image on supported, enabled devices; an OCR parser provides a draft elsewhere. The student reviews and edits every course and meeting before confirming. Confirmation saves the structured schedule to the existing on-device store. The image and OCR text are not persisted or uploaded.

`SupabaseScheduleRepository` and the SQL migration establish a cloud transport contract. They are deliberately not called from the UI yet: there is no configured Supabase project or authenticated session, and a partial sync would put local schedule fidelity at risk. Local import works without any cloud account.

## Cloud contract

- `supabase/migrations/202609250001_schedule.sql` creates owner-scoped semesters, courses, and course meetings with composite owner foreign keys and RLS for SELECT, INSERT, UPDATE, and DELETE.
- `replace_schedule_snapshot` writes one reviewed semester atomically. The caller supplies the previously read `sync_version`; stale writes fail. The RPC runs as the caller, not a service role.
- The Swift adapter accepts only schedules that can be represented without loss. ICS recurrence exceptions, one-time events, source notes, and rich Howdy metadata currently remain local.
- Only a Supabase publishable key may enter the app. Never ship a service-role key or store a password in source control.

## Configuration and verification still required

1. Create a private Supabase project and apply the migration to a disposable development instance first.
2. Run `supabase/tests/schedule_rls.sql` with `psql -v ON_ERROR_STOP=1` against that instance. The test writes two temporary Auth users, checks cross-user reads and writes, and rolls back. This has not been executed in this checkout because no Supabase project or PostgreSQL runtime is configured.
3. Set `MCSupabaseURL` and `MCSupabasePublishableKey` in the app's generated Info.plist using local, uncommitted Xcode build settings. Do not use the production key in simulator test logs. The repository returns no configuration until both keys exist.
4. Add the auth and sync UI only after the project and RLS tests work. The installed Personal Team profile currently lacks Sign in with Apple. Enable that capability under an eligible Apple Developer team before relying on native Apple sign-in. Local mode should remain the default.
5. Exercise two-device conflict, offline retry, sign-out, account deletion, and remote restore before enabling automatic cloud sync. Do not overwrite a local schedule just because a remote copy exists.

## Model handoff

One integrator should own `main` and merge tested branches. A second model can own Supabase project setup, RLS execution, and authentication on a separate branch. A third can evaluate screenshot layouts and extraction quality with redacted or synthetic schedules, without editing the same Swift files. Share the branch name, base commit, tests, and unresolved gates at every handoff.
