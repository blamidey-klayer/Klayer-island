#!/usr/bin/env bash
# End-to-end test of Klayer Island on the macOS CI: the island shows the sessions and the requests of
# the Claude app, and they are answered from the island (tests/e2e/island_e2e.py).
#   1. the shipped build (KLAYER_E2E_RELEASE_APP, set by the CI) answers no test command;
#   2. the test build (KLAYER_E2E) launched without KLAYER_ISLAND_TEST=1 answers none either;
#   3. the test build launched with KLAYER_ISLAND_TEST=1 passes the 11 scenarios.
# Build the test app first, as .github/workflows/build.yml does. Made for the CI runner: it uses this
# account's ~/Library/Application Support/NotchBuddy and the island's preferences (terminal cards must
# be off), and never writes ~/.claude/settings.json. Logs go to build-e2e/e2e-logs/. Outside the CI
# (CI=true, set by GitHub Actions) it refuses to run unless KLAYER_E2E_LOCAL=1 says you know that.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${CI:-}" != "true" ] && [ "${KLAYER_E2E_LOCAL:-}" != "1" ]; then
    echo "test-e2e-island: made for the macOS CI; it takes this account's Klayer Island socket and preferences." >&2
    echo "test-e2e-island: to run it here anyway, quit Klayer Island and set KLAYER_E2E_LOCAL=1." >&2
    exit 1
fi
APP="${KLAYER_E2E_APP:-build-e2e/Build/Products/Debug/KlayerIsland.app/Contents/MacOS/KlayerIsland}"
OUT="${KLAYER_E2E_OUT:-build-e2e/e2e-logs}"
mkdir -p "$OUT"
: > "$OUT/harness.txt"

# The test takes the island's socket: never under a Klayer Island in use.
if pgrep -x KlayerIsland >/dev/null 2>&1; then
    echo "test-e2e-island: quit Klayer Island first (the test would replace its socket)" | tee -a "$OUT/harness.txt"
    exit 1
fi

# The island's own log (nb.log…) next to the harness output, whatever happens.
trap 'cp "$HOME"/Library/Logs/NotchBuddy/*.log "$OUT/" 2>/dev/null || true' EXIT

harness() {
    python3 tests/e2e/island_e2e.py "$@" 2>&1 | tee -a "$OUT/harness.txt"
}

if [ -n "${KLAYER_E2E_RELEASE_APP:-}" ]; then
    harness --app "$KLAYER_E2E_RELEASE_APP" --log "$OUT/release-app.log" --expect-no-test-commands
fi
harness --app "$APP" --log "$OUT/app-without-test-env.log" --expect-no-test-commands --without-test-env
harness --app "$APP" --log "$OUT/app.log"
