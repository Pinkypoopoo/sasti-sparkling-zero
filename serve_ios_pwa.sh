#!/usr/bin/env bash
set -e
mkdir -p build/web
echo "Exporting Web iOS Safari PWA..."
godot --headless --path . --export-release "Web iOS Safari PWA" build/web/index.html || true
IP_ADDR=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -n1)
if [ -z "$IP_ADDR" ]; then IP_ADDR="localhost"; fi
echo "=========================================================="
echo " iOS SAFARI PWA READY!"
echo " Open Safari on your iPhone (same Wi-Fi / Hotspot) and go to:"
echo "   http://${IP_ADDR}:8080"
echo " Tap Share -> 'Add to Home Screen' for fullscreen 120Hz touch!"
echo "=========================================================="
python3 -m http.server 8080 --directory build/web
