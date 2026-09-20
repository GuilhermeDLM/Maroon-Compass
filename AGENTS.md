# Maroon Compass iOS repository instructions

Read `README.md` and `docs/PROJECT_STATE.md` before changing the app.

- This repository is the native iPhone/iPad edition. The macOS edition is maintained separately in `Maroon-Compass-Mac`.
- Preserve the app and widget bundle identities, the user's schedule and local data, academic exception handling, saved places, reminders, and Personal Team renewal safeguards.
- Never guess missing course times, rooms, travel durations, finals, or schedule changes. Use authoritative user-provided or official data.
- Keep `Tools/RenewalConfig.local.zsh`, device identifiers, signing exports, provisioning profiles, and Keychain material out of Git.
- Run schedule tests and a relevant simulator build for source changes. Treat source, signing, installation, launch, and physical-device behavior as separate gates.
- Update `docs/PROJECT_STATE.md` whenever schedule authority, signing state, or the next delivery gate changes.
- Use focused branches and commits; never force-push shared history.
