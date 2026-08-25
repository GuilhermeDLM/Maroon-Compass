#!/bin/zsh

set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
readonly PROJECT_PATH="$PROJECT_DIRECTORY/MaroonCompass.xcodeproj"
readonly DERIVED_DATA_PATH="$PROJECT_DIRECTORY/DerivedDataRenewal"
readonly APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release-iphoneos/MaroonCompass.app"
readonly WIDGET_PATH="$APP_PATH/PlugIns/MaroonCompassWidget.appex"
readonly STATE_DIRECTORY="${MAROON_COMPASS_STATE_DIRECTORY:-$HOME/Library/Application Support/Maroon Compass Renewal/State}"
readonly STATE_PATH="$STATE_DIRECTORY/renewal-state.plist"
readonly LOCK_DIRECTORY="$STATE_DIRECTORY/renewal.lock"
readonly PROFILE_DIRECTORY="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
readonly LOCAL_CONFIG_PATH="$SCRIPT_DIRECTORY/RenewalConfig.local.zsh"

if [[ -f "$LOCAL_CONFIG_PATH" ]]; then
    source "$LOCAL_CONFIG_PATH"
fi

readonly DEVICE_IDENTIFIER="${MAROON_COMPASS_DEVICE_IDENTIFIER:-}"
readonly APP_IDENTIFIER="ASUMB3BUP7.com.guilhermemachado.MaroonCompass"
readonly WIDGET_IDENTIFIER="ASUMB3BUP7.com.guilhermemachado.MaroonCompass.Widget"
readonly REQUIRED_REMAINING_HOURS="${MAROON_COMPASS_REQUIRED_REMAINING_HOURS:-120}"

if [[ -z "$DEVICE_IDENTIFIER" ]]; then
    print -u2 "Set MAROON_COMPASS_DEVICE_IDENTIFIER in Tools/RenewalConfig.local.zsh before running device renewal."
    exit 78
fi

if [[ ! "$REQUIRED_REMAINING_HOURS" =~ '^[0-9]+$' ]] || (( REQUIRED_REMAINING_HOURS < 1 || REQUIRED_REMAINING_HOURS > 168 )); then
    print -u2 "MAROON_COMPASS_REQUIRED_REMAINING_HOURS must be an integer from 1 through 168."
    exit 64
fi

CHECK_ONLY=false
if [[ "${1:-}" == "--check-only" ]]; then
    CHECK_ONLY=true
elif [[ -n "${1:-}" ]]; then
    print -u2 "Usage: $0 [--check-only]"
    exit 64
fi

TEMPORARY_DIRECTORY=$(mktemp -d '/tmp/maroon-compass-renewal.XXXXXX')
typeset -a TEMPORARY_FILES
LOCK_OWNED=false

cleanup() {
    local temporary_file
    for temporary_file in "$TEMPORARY_DIRECTORY"/*(N); do
        [[ -f "$temporary_file" ]] && /bin/rm -f "$temporary_file"
    done
    rmdir "$TEMPORARY_DIRECTORY" 2>/dev/null || true

    if [[ "$LOCK_OWNED" == true ]]; then
        /bin/rm -f "$LOCK_DIRECTORY/pid"
        rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
    fi
}
trap cleanup EXIT

acquire_lock() {
    local existing_pid=""

    mkdir -p "$STATE_DIRECTORY"
    if mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
        LOCK_OWNED=true
        print -r -- "$$" > "$LOCK_DIRECTORY/pid"
        return 0
    fi

    if [[ -f "$LOCK_DIRECTORY/pid" ]]; then
        existing_pid=$(<"$LOCK_DIRECTORY/pid")
    fi
    if [[ "$existing_pid" == <-> ]] && kill -0 "$existing_pid" 2>/dev/null; then
        print "A Maroon Compass renewal is already running (process $existing_pid); no duplicate run was started."
        exit 0
    fi

    /bin/rm -f "$LOCK_DIRECTORY/pid"
    if ! rmdir "$LOCK_DIRECTORY" 2>/dev/null || ! mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
        print -u2 "Unable to acquire the Maroon Compass renewal lock."
        exit 75
    fi
    LOCK_OWNED=true
    print -r -- "$$" > "$LOCK_DIRECTORY/pid"
}

iso_to_epoch() {
    TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" '+%s'
}

hours_remaining() {
    local expiration_epoch
    expiration_epoch=$(iso_to_epoch "$1")
    print $(( (expiration_epoch - $(date '+%s')) / 3600 ))
}

decode_profile() {
    local source_profile="$1"
    local destination_plist="$2"
    security cms -D -i "$source_profile" > "$destination_plist"
}

embedded_profile_expiration() {
    local bundle_path="$1"
    local label="$2"
    local decoded_profile="$TEMPORARY_DIRECTORY/$label.plist"

    [[ -f "$bundle_path/embedded.mobileprovision" ]] || return 1
    decode_profile "$bundle_path/embedded.mobileprovision" "$decoded_profile"
    plutil -extract ExpirationDate raw "$decoded_profile"
}

minimum_embedded_expiration() {
    local app_expiration
    local widget_expiration
    local app_epoch
    local widget_epoch

    app_expiration=$(embedded_profile_expiration "$APP_PATH" app) || return 1
    widget_expiration=$(embedded_profile_expiration "$WIDGET_PATH" widget) || return 1
    [[ -n "$app_expiration" && -n "$widget_expiration" ]] || return 1
    app_epoch=$(iso_to_epoch "$app_expiration")
    widget_epoch=$(iso_to_epoch "$widget_expiration")

    if (( app_epoch <= widget_epoch )); then
        print "$app_expiration"
    else
        print "$widget_expiration"
    fi
}

state_expiration() {
    [[ -f "$STATE_PATH" ]] || return 1
    plutil -extract profileExpiration raw "$STATE_PATH" 2>/dev/null
}

is_fresh() {
    (( $(hours_remaining "$1") >= REQUIRED_REMAINING_HOURS ))
}

restore_archived_profiles() {
    local backup_directory="$1"
    local profile
    local destination

    for profile in "$backup_directory"/*.mobileprovision(N); do
        destination="$PROFILE_DIRECTORY/${profile:t}"
        [[ -e "$destination" ]] || mv "$profile" "$destination"
    done
}

archive_matching_profiles() {
    local backup_directory="$1"
    local profile
    local decoded_profile
    local application_identifier

    mkdir -p "$backup_directory"
    for profile in "$PROFILE_DIRECTORY"/*.mobileprovision(N); do
        decoded_profile="$TEMPORARY_DIRECTORY/profile-${profile:t}.plist"
        if ! decode_profile "$profile" "$decoded_profile" 2>/dev/null; then
            continue
        fi
        application_identifier=$(plutil -extract Entitlements.application-identifier raw "$decoded_profile" 2>/dev/null || true)
        if [[ "$application_identifier" == "$APP_IDENTIFIER" || "$application_identifier" == "$WIDGET_IDENTIFIER" ]]; then
            mv "$profile" "$backup_directory/"
        fi
    done
}

build_fresh_release() {
    local backup_directory="$DERIVED_DATA_PATH/ProfileBackups/$(date -u '+%Y%m%dT%H%M%SZ')"
    local expiration

    run_release_build() {
        xcodebuild \
            -quiet \
            -project "$PROJECT_PATH" \
            -scheme MaroonCompass \
            -configuration Release \
            -destination 'generic/platform=iOS' \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -allowProvisioningUpdates \
            -allowProvisioningDeviceRegistration \
            "$@"
    }

    print "Requesting an automatically signed Release build from Xcode."
    if ! run_release_build clean build; then
        print "The first pass updated signing assets but did not finish; retrying with the refreshed profiles."
        run_release_build build
    fi

    expiration=$(minimum_embedded_expiration)
    if is_fresh "$expiration"; then
        print "Fresh signed Release build expires at $expiration."
        return 0
    fi

    print "Xcode reused a profile with only $(hours_remaining "$expiration") hours remaining; archiving the matching profiles and requesting replacements."
    archive_matching_profiles "$backup_directory"

    if ! run_release_build clean build; then
        print "The refresh pass updated signing assets but did not finish; retrying with the refreshed profiles."
        if ! run_release_build build; then
            restore_archived_profiles "$backup_directory"
            print -u2 "Renewal build failed; previous profiles were preserved."
            return 1
        fi
    fi

    expiration=$(minimum_embedded_expiration)
    if ! is_fresh "$expiration"; then
        restore_archived_profiles "$backup_directory"
        print -u2 "Xcode produced a profile with only $(hours_remaining "$expiration") hours remaining; refusing to reinstall it."
        return 1
    fi

    print "Fresh signed Release build expires at $expiration."
}

verify_release() {
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    codesign --verify --strict --verbose=2 "$WIDGET_PATH"
}

install_release() {
    local install_result="$TEMPORARY_DIRECTORY/install.json"
    local app_result="$TEMPORARY_DIRECTORY/apps.json"
    local version
    local build
    local installation_url
    local expiration
    local state_temporary="$TEMPORARY_DIRECTORY/renewal-state.plist"

    xcrun devicectl device install app \
        --device "$DEVICE_IDENTIFIER" \
        "$APP_PATH" \
        --json-output "$install_result"

    xcrun devicectl device info apps \
        --device "$DEVICE_IDENTIFIER" \
        --bundle-id com.guilhermemachado.MaroonCompass \
        --columns '*' \
        --json-output "$app_result" > /dev/null

    version=$(jq -r '.result.apps[] | select(.bundleIdentifier == "com.guilhermemachado.MaroonCompass") | .version' "$app_result")
    build=$(jq -r '.result.apps[] | select(.bundleIdentifier == "com.guilhermemachado.MaroonCompass") | .bundleVersion' "$app_result")
    installation_url=$(jq -r '.result.apps[] | select(.bundleIdentifier == "com.guilhermemachado.MaroonCompass") | .url' "$app_result")
    expiration=$(minimum_embedded_expiration)

    [[ -n "$version" && "$version" != "null" ]] || return 1
    [[ -n "$installation_url" && "$installation_url" != "null" ]] || return 1

    plutil -create xml1 "$state_temporary"
    plutil -insert profileExpiration -string "$expiration" "$state_temporary"
    plutil -insert installedAt -string "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$state_temporary"
    plutil -insert version -string "$version" "$state_temporary"
    plutil -insert build -string "$build" "$state_temporary"
    plutil -insert installationURL -string "$installation_url" "$state_temporary"
    mkdir -p "$STATE_DIRECTORY"
    mv "$state_temporary" "$STATE_PATH"

    print "Installed Maroon Compass $version ($build) wirelessly."
    print "Installed profile expires at $expiration."
    print "Installation path: $installation_url"
}

acquire_lock

if current_state_expiration=$(state_expiration); then
    print "Last confirmed installed profile expires at $current_state_expiration ($(hours_remaining "$current_state_expiration") hours remaining)."
    if is_fresh "$current_state_expiration"; then
        print "No renewal needed; the last confirmed installation is still fresh."
        exit 0
    fi
fi

if [[ -d "$APP_PATH" ]]; then
    if current_build_expiration=$(minimum_embedded_expiration 2>/dev/null); then
        print "Current local Release profile expires at $current_build_expiration ($(hours_remaining "$current_build_expiration") hours remaining)."
        if [[ "$CHECK_ONLY" == true ]]; then
            if is_fresh "$current_build_expiration"; then
                print "CHECK_RESULT=fresh-local-build"
            else
                print "CHECK_RESULT=renewal-required"
            fi
            exit 0
        fi
        if ! is_fresh "$current_build_expiration"; then
            build_fresh_release
        fi
    else
        [[ "$CHECK_ONLY" == true ]] && print "CHECK_RESULT=renewal-required" && exit 0
        build_fresh_release
    fi
else
    [[ "$CHECK_ONLY" == true ]] && print "CHECK_RESULT=renewal-required" && exit 0
    build_fresh_release
fi

verify_release
install_release
