#!/usr/bin/env bash
OUT=$(godot --path . --headless --quit-after 10 2>&1)
echo "$OUT"
if echo "$OUT" | grep -qE "SCRIPT ERROR|Parse Error|Failed to load script"; then
    echo "VERIFY_FAILED"
    exit 1
else
    echo "VERIFY_PASSED"
    exit 0
fi
