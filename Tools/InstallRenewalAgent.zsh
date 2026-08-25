#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
readonly SUPPORT_DIRECTORY="$HOME/Library/Application Support/Maroon Compass Renewal"
readonly INSTALLED_PROJECT_DIRECTORY="$SUPPORT_DIRECTORY/Project"
readonly STATE_DIRECTORY="$SUPPORT_DIRECTORY/State"
readonly LOG_DIRECTORY="$HOME/Library/Logs/Maroon Compass Renewal"
readonly AGENT_LABEL="com.guilhermemachado.marooncompass.renewal"
readonly SOURCE_PLIST="$PROJECT_DIRECTORY/Automation/$AGENT_LABEL.plist"
readonly INSTALLED_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
readonly LEGACY_STATE="$PROJECT_DIRECTORY/DerivedDataRenewal/renewal-state.plist"
readonly SHARED_STATE="$STATE_DIRECTORY/renewal-state.plist"
readonly DOMAIN="gui/$(id -u)"

mkdir -p "$INSTALLED_PROJECT_DIRECTORY" "$STATE_DIRECTORY" "$LOG_DIRECTORY" "$HOME/Library/LaunchAgents"

/usr/bin/rsync -a --delete \
    --exclude '.DS_Store' \
    --exclude 'DerivedData*' \
    --exclude 'Dist' \
    --exclude 'Screenshots' \
    --exclude 'tmp' \
    "$PROJECT_DIRECTORY/" "$INSTALLED_PROJECT_DIRECTORY/"

if [[ ! -f "$SHARED_STATE" && -f "$LEGACY_STATE" ]]; then
    install -m 0600 "$LEGACY_STATE" "$SHARED_STATE"
fi

plutil -lint "$SOURCE_PLIST" > /dev/null
zsh -n "$INSTALLED_PROJECT_DIRECTORY/Tools/RenewDeviceInstallation.zsh"
install -m 0644 "$SOURCE_PLIST" "$INSTALLED_PLIST"

launchctl bootout "$DOMAIN/$AGENT_LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$INSTALLED_PLIST"
launchctl enable "$DOMAIN/$AGENT_LABEL"

print "Installed and started $AGENT_LABEL."
print "Renewal source: $INSTALLED_PROJECT_DIRECTORY"
print "Shared state: $SHARED_STATE"
print "Logs: $LOG_DIRECTORY"
