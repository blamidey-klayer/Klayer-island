#!/usr/bin/env bash
# The chat's context comes only from an explicit act (lot 6 spec §3): opening the chat never reads
# the previous app's window. WindowContextCapture.captureActive may be called only by ⌃⌥W
# (« Attacher la fenêtre active », performAttachFrontWindow) and by Klay dropped on a window
# (windowContextAtPoint), both in IslandWindowController.swift. Fails on any other call.
set -euo pipefail
cd "$(dirname "$0")/.."
allowed=" IslandWindowController.swift:performAttachFrontWindow IslandWindowController.swift:windowContextAtPoint "
# Each call (comment lines left out) with its file and the function it sits in.
sites="$(find NotchBuddy/Sources -name '*.swift' -print0 | sort -z | xargs -0 awk '
    FNR == 1 { fn = "" }
    match($0, /func [A-Za-z_][A-Za-z0-9_]*/) { fn = substr($0, RSTART + 5, RLENGTH - 5) }
    /captureActive\(/ && $0 !~ /^[[:space:]]*\/\// && $0 !~ /func captureActive\(/ {
        n = split(FILENAME, parts, "/"); print parts[n] ":" fn ":" FNR
    }')"
bad=0
count=0
while IFS= read -r site; do
    [ -n "$site" ] || continue
    count=$((count + 1))
    key="${site%:*}"
    if [[ "$allowed" == *" $key "* ]]; then
        echo "  ok  $site"
    else
        echo "  NOT ALLOWED  $site: the chat's context comes only from an explicit act" >&2
        bad=1
    fi
done <<< "$sites"
[ "$bad" -eq 0 ] || exit 1
echo "Window capture sites: $count call(s), all explicit"
