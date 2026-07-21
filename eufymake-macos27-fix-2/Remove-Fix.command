#!/bin/zsh
set -u
setopt NO_BANG_HIST 2>/dev/null || true

FIX_ROOT="$HOME/Library/Application Support/EufyMake-macOS27-Fix"

echo "============================================================"
echo " eufyMake Studio macOS 27 Fix entfernen"
echo "============================================================"
echo ""

killall eufyStudio 2>/dev/null || true

if [[ -d "$FIX_ROOT" ]]; then
    rm -rf "$FIX_ROOT"
    echo "Der gepatchte Fix wurde entfernt."
else
    echo "Es wurde keine installierte Fix-Kopie gefunden."
fi

echo ""
echo "Die originale eufyMake Studio.app wurde nicht verändert."
echo ""
read -r "?Drücke Enter zum Schließen."
