#!/usr/bin/env bash
# The nb-hook relay as the app writes it, run against a stub of the island's socket
# (tests/hook_relay_test.py): the session's name in --statusline mode, the previous status line's
# output unchanged, exit 0 at once when the island does not answer, hook payloads forwarded whole,
# CLAUDE_CODE_ENTRYPOINT forwarded as klayer_entrypoint on every hook event.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/klayer-hook-relay.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
python3 tests/hook_relay_test.py "$PWD" "$TEST_DIR"
