#!/bin/sh
# ./install.sh [--zip | <ssh-host>]   Install/update the plasmoid here, on another machine, or build a .plasmoid.
set -e
cd "$(dirname "$0")"
pkg=org.mrgeebee.sensormonitor
zipfile=dist/$pkg.plasmoid
build() { mkdir -p dist; rm -f "$zipfile"; (cd "$pkg" && zip -qr "../$zipfile" metadata.json contents); }

# VERSION must match the plasmoid metadata (the KDE Store compares the metadata version)
want=$(tr -d '[:space:]' < VERSION)
have=$(sed -n 's/.*"Version": *"\([^"]*\)".*/\1/p' "$pkg/metadata.json")
[ "$want" = "$have" ] || { echo "VERSION ($want) != metadata.json Version ($have)" >&2; exit 1; }

# Syntax check (i18n/cfg "unqualified access" warnings are normal in Plasma code, so only errors count)
lint=/usr/lib/qt6/bin/qmllint
if [ -x "$lint" ] && "$lint" -I /usr/lib/qt6/qml "$pkg"/contents/ui/*.qml 2>&1 | grep -q '^Error'; then
    "$lint" -I /usr/lib/qt6/qml "$pkg"/contents/ui/*.qml 2>&1 | grep -A3 '^Error'; echo "qmllint errors, aborting" >&2; exit 1
fi

case "${1:-}" in
    --zip) build; echo "built $zipfile" ;;
    "") kpackagetool6 -t Plasma/Applet -u "$pkg" 2>/dev/null || kpackagetool6 -t Plasma/Applet -i "$pkg" ;;
    *) build
       scp -q "$zipfile" "$1:/tmp/$pkg.plasmoid"
       ssh "$1" "kpackagetool6 -t Plasma/Applet -u /tmp/$pkg.plasmoid || kpackagetool6 -t Plasma/Applet -i /tmp/$pkg.plasmoid; rm -f /tmp/$pkg.plasmoid" ;;
esac
