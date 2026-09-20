# Project state

Updated: 2026-09-19

## Current state

Maroon Compass is an implemented native iPhone/iPad Texas A&M campus companion. This snapshot includes the verified Fall 2026 schedule model, campus/map services, widgets, reminders, calendar export, private ICS import, the Personal Plan feature, and guarded Personal Team renewal tooling.

The original iOS mega prompt is preserved at `docs/source-material/MEGA_PROMPT.md`. The macOS edition is in the separate `Maroon-Compass-Mac` repository.

## Verification status

Earlier project evidence recorded successful source builds/tests and an installed device release. The 2026-09-19 renewal attempt failed safely because Xcode credentials were incomplete and preserved the previously installed profile. The GitHub migration did not retry signing, installation, or device access.

## Next safe actions

1. Run the schedule test suite against the current source.
2. Use only `Tools/RenewDeviceInstallation.zsh` for the existing device-renewal workflow.
3. Resolve the Xcode account credential blocker before attempting a new signed installation.
4. Keep the local renewal configuration and device identifier uncommitted.
