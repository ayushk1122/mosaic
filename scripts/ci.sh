#!/usr/bin/env bash
# Local engineering gate: unit tests + optional Supabase reset/SQL tests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:${HOME}/.local/bin:${PATH}"
export SUPABASE_INTERNAL_DISABLE_TELEMETRY=1

cd "$ROOT"

echo "==> Mosaic unit tests"
if [[ -d "/Applications/Xcode.app" ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DEST="${MOSAIC_TEST_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"
xcodebuild test \
  -project Mosaic/Mosaic.xcodeproj \
  -scheme Mosaic \
  -destination "$DEST" \
  -only-testing:MosaicTests \
  -derivedDataPath /tmp/mosaic-ci-dd \
  | tee /tmp/mosaic-ci-unit.log \
  | grep -E 'error:|TEST SUCCEEDED|TEST FAILED|failed \(' || true
grep -q 'TEST SUCCEEDED' /tmp/mosaic-ci-unit.log

if docker info >/dev/null 2>&1 && command -v supabase >/dev/null 2>&1; then
  echo "==> Local Supabase reset + SQL tests"
  (
    cd "$ROOT"
    supabase start
    supabase db reset --yes
    if [[ -d supabase/tests ]]; then
      supabase test db || {
        echo "supabase test db failed or pgTAP is unavailable; baseline reset still required to pass."
        exit 1
      }
    fi
  )
else
  echo "==> Skipping Supabase SQL tests (Docker or supabase CLI unavailable)"
fi

echo "==> CI checks passed"
