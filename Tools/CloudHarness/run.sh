#!/usr/bin/env bash
# Builds the app's portable cloud sources on Linux (Swift 6, strict concurrency) and runs:
#   - the cloud unit tests from MaroonCompassTests (no network), and
#   - live integration tests against a Supabase stack when MC_LIVE_SUPABASE_URL is set.
#
# Usage (from the repository root):
#   Tools/CloudHarness/run.sh                       # unit tests only
#   MC_LIVE_SUPABASE_URL=http://127.0.0.1:54321 \
#   MC_LIVE_PUBLISHABLE_KEY=sb_publishable_... \
#   MC_LIVE_SECRET_KEY=sb_secret_... \
#   Tools/CloudHarness/run.sh                       # plus live tests (local `supabase start` only)
#
# MC_LIVE_SECRET_KEY is the local CLI stack's admin key, used only by the tests to create and
# expire disposable users. Never point the live tests at a production project.
#
# Requires Docker with the official `swift:6.2-noble` image. Sources are copied into a scratch
# package; nothing is written to the repository.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${MC_HARNESS_WORKDIR:-$(mktemp -d)}"
IMAGE="${MC_SWIFT_IMAGE:-swift:6.2-noble}"

APP_SOURCES=(
  MaroonCompass/Models/ScheduleModels.swift
  MaroonCompass/Models/ScheduleDraft.swift
  MaroonCompass/Data/ScheduleSeed.swift
  MaroonCompass/Services/ScheduleEngine.swift
  MaroonCompass/Services/ICSImportService.swift
  MaroonCompass/Services/SupabaseScheduleRepository.swift
  MaroonCompass/Services/Cloud/CloudConfiguration.swift
  MaroonCompass/Services/Cloud/CloudAuth.swift
  MaroonCompass/Services/Cloud/CloudSessionManager.swift
  MaroonCompass/Services/Cloud/CloudScheduleSync.swift
  MaroonCompass/Services/Cloud/CloudAccountModel.swift
)
TEST_SOURCES=(
  MaroonCompassTests/CloudTestSupport.swift
  MaroonCompassTests/CloudScheduleSnapshotTests.swift
  MaroonCompassTests/CloudSessionTests.swift
  MaroonCompassTests/CloudSyncTests.swift
)

rm -rf "$WORK/Sources" "$WORK/Tests"
mkdir -p "$WORK/Sources/CoreLocation" "$WORK/Sources/MaroonCompass" "$WORK/Tests/MaroonCompassTests" "$WORK/Tests/CloudLiveTests"
cp "$ROOT/Tools/CloudHarness/Shims/CoreLocation.swift" "$WORK/Sources/CoreLocation/"
for file in "${APP_SOURCES[@]}"; do cp "$ROOT/$file" "$WORK/Sources/MaroonCompass/"; done
for file in "${TEST_SOURCES[@]}"; do cp "$ROOT/$file" "$WORK/Tests/MaroonCompassTests/"; done
cp "$ROOT/MaroonCompassTests/CloudTestSupport.swift" "$WORK/Tests/CloudLiveTests/"
cp "$ROOT"/Tools/CloudHarness/LiveTests/*.swift "$WORK/Tests/CloudLiveTests/"

cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let package = Package(
    name: "MaroonCompassCloudHarness",
    targets: [
        .target(name: "CoreLocation", swiftSettings: strict),
        .target(name: "MaroonCompass", dependencies: ["CoreLocation"], swiftSettings: strict),
        .testTarget(name: "MaroonCompassTests", dependencies: ["MaroonCompass"], swiftSettings: strict),
        .testTarget(name: "CloudLiveTests", dependencies: ["MaroonCompass"], swiftSettings: strict)
    ]
)
SWIFT

docker run --rm --network host \
  -v "$WORK":/work -w /work \
  -e MC_LIVE_SUPABASE_URL -e MC_LIVE_PUBLISHABLE_KEY -e MC_LIVE_SECRET_KEY \
  "$IMAGE" swift test ${MC_HARNESS_FILTER:+--filter "$MC_HARNESS_FILTER"} "$@"
