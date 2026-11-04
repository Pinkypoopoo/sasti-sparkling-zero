#!/usr/bin/env bash
godot --path . --headless --quit-after 10
if [ $? -eq 0 ]; then
    echo "VERIFY_PASSED"
    exit 0
else
    echo "VERIFY_FAILED"
    exit 1
fi
