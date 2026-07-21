#!/bin/zsh
# eufyMake Studio macOS 27 Fix
# One-click workaround for the libpag CFRelease(NULL) crash on Apple Silicon.
#
# This script does NOT modify the original eufyMake Studio installation.
# It creates a private patched copy, ad-hoc signs the patched executable in
# isolation, and launches that executable natively as arm64.

set -u
setopt NO_BANG_HIST 2>/dev/null || true

SCRIPT_VERSION="1.0.0"
FIX_ROOT="$HOME/Library/Application Support/EufyMake-macOS27-Fix"
PATCHED_APP="$FIX_ROOT/eufyMake Studio macOS27 Fixed.app"
METADATA_FILE="$FIX_ROOT/source.env"
LOG_FILE="$FIX_ROOT/eufymake-fixed.log"
WORK_DIR=""

print_header() {
    clear 2>/dev/null || true
    echo "============================================================"
    echo " eufyMake Studio macOS 27 Fix v$SCRIPT_VERSION"
    echo "============================================================"
    echo ""
}

pause_on_error() {
    echo ""
    echo "Drücke Enter, um das Fenster zu schließen."
    read -r _
}

fail() {
    echo ""
    echo "FEHLER: $1" >&2
    pause_on_error
    exit 1
}

cleanup() {
    if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT INT TERM

find_eufymake_app() {
    local candidates=()
    local p

    for p in \
        "/Applications/eufyMake Studio.app" \
        "$HOME/Applications/eufyMake Studio.app"; do
        [[ -d "$p" ]] && candidates+=("$p")
    done

    if (( ${#candidates[@]} == 0 )); then
        while IFS= read -r p; do
            [[ -d "$p" ]] && candidates+=("$p")
        done < <(find /Applications "$HOME/Applications" -maxdepth 1 -type d -iname '*eufy*studio*.app' 2>/dev/null | sort -u)
    fi

    if (( ${#candidates[@]} == 0 )); then
        return 1
    fi

    printf '%s\n' "${candidates[1]}"
}

hash_file() {
    /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

is_patch_present_perl() {
    /usr/bin/perl - "$1" <<'PERL'
use strict;
use warnings;

my ($path) = @ARGV;
open my $fh, '<:raw', $path or die "cannot open $path: $!\n";
local $/;
my $data = <$fh>;
close $fh;

my @w = unpack('V*', $data);
my $NOP = 0xD503201F;
my @movs = (0xAA1B03E0, 0xAA1A03E0, 0xAA1703E0, 0xAA1803E0, 0xAA1903E0);

sub is_bl {
    my ($x) = @_;
    return (($x & 0xFC000000) == 0x94000000);
}

sub bl_target {
    my ($idx, $x) = @_;
    my $imm = $x & 0x03FFFFFF;
    $imm -= 0x04000000 if ($imm & 0x02000000);
    return ($idx * 4) + ($imm * 4);
}

my @matches;
for (my $i = 0; $i + 12 < @w; $i++) {
    next unless $w[$i]     == 0xAA0003F6; # mov x22, x0
    next unless $w[$i + 1] == 0xF94013E0; # ldr x0, [sp,#0x20]
    next unless ($w[$i + 2] == $NOP || is_bl($w[$i + 2]));

    my $ok = 1;
    my @call_indices = (4, 6, 8, 10, 12);
    for my $n (0..4) {
        my $move_idx = $i + 3 + ($n * 2);
        my $call_idx = $i + 4 + ($n * 2);
        if ($w[$move_idx] != $movs[$n] || !is_bl($w[$call_idx])) {
            $ok = 0;
            last;
        }
    }
    next unless $ok;

    my $target = bl_target($i + 4, $w[$i + 4]);
    for my $call_offset (@call_indices) {
        if (bl_target($i + $call_offset, $w[$i + $call_offset]) != $target) {
            $ok = 0;
            last;
        }
    }
    next unless $ok;

    if (is_bl($w[$i + 2]) && bl_target($i + 2, $w[$i + 2]) != $target) {
        next;
    }

    push @matches, [$i + 2, $w[$i + 2] == $NOP ? 'patched' : 'unpatched'];
}

if (@matches == 1 && $matches[0]->[1] eq 'patched') {
    exit 0;
}
exit 1;
PERL
}

patch_arm64_perl() {
    /usr/bin/perl - "$1" <<'PERL'
use strict;
use warnings;

my ($path) = @ARGV;
open my $fh, '+<:raw', $path or die "cannot open $path: $!\n";
local $/;
my $data = <$fh>;
my @w = unpack('V*', $data);

my $NOP = 0xD503201F;
my @movs = (0xAA1B03E0, 0xAA1A03E0, 0xAA1703E0, 0xAA1803E0, 0xAA1903E0);

sub is_bl {
    my ($x) = @_;
    return (($x & 0xFC000000) == 0x94000000);
}

sub bl_target {
    my ($idx, $x) = @_;
    my $imm = $x & 0x03FFFFFF;
    $imm -= 0x04000000 if ($imm & 0x02000000);
    return ($idx * 4) + ($imm * 4);
}

my @matches;
for (my $i = 0; $i + 12 < @w; $i++) {
    next unless $w[$i]     == 0xAA0003F6;
    next unless $w[$i + 1] == 0xF94013E0;
    next unless ($w[$i + 2] == $NOP || is_bl($w[$i + 2]));

    my $ok = 1;
    my @call_indices = (4, 6, 8, 10, 12);
    for my $n (0..4) {
        my $move_idx = $i + 3 + ($n * 2);
        my $call_idx = $i + 4 + ($n * 2);
        if ($w[$move_idx] != $movs[$n] || !is_bl($w[$call_idx])) {
            $ok = 0;
            last;
        }
    }
    next unless $ok;

    my $target = bl_target($i + 4, $w[$i + 4]);
    for my $call_offset (@call_indices) {
        if (bl_target($i + $call_offset, $w[$i + $call_offset]) != $target) {
            $ok = 0;
            last;
        }
    }
    next unless $ok;

    if (is_bl($w[$i + 2]) && bl_target($i + 2, $w[$i + 2]) != $target) {
        next;
    }

    push @matches, [$i + 2, $w[$i + 2] == $NOP ? 'patched' : 'unpatched'];
}

if (@matches != 1) {
    print STDERR "Safety check failed: expected exactly one libpag release sequence, found " . scalar(@matches) . ".\n";
    exit 20;
}

my ($word_index, $state) = @{$matches[0]};
my $byte_offset = $word_index * 4;
printf "Gefundene Patchposition im ARM64-Slice: 0x%X\n", $byte_offset;

if ($state eq 'patched') {
    print "Patch ist bereits vorhanden.\n";
    exit 0;
}

substr($data, $byte_offset, 4, pack('V', $NOP));
seek($fh, 0, 0) or die "seek failed: $!\n";
print {$fh} $data or die "write failed: $!\n";
truncate($fh, length($data)) or die "truncate failed: $!\n";
close $fh;
print "Patch gesetzt: unsicherer CFRelease-Aufruf -> ARM64 NOP.\n";
PERL
}

patch_arm64_python() {
    /usr/bin/env python3 - "$1" <<'PY'
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = bytearray(path.read_bytes())
words = list(struct.unpack(f'<{len(data)//4}I', data[:len(data)//4*4]))
NOP = 0xD503201F
MOVS = [0xAA1B03E0, 0xAA1A03E0, 0xAA1703E0, 0xAA1803E0, 0xAA1903E0]

def is_bl(x: int) -> bool:
    return (x & 0xFC000000) == 0x94000000

def bl_target(index: int, word: int) -> int:
    imm = word & 0x03FFFFFF
    if imm & 0x02000000:
        imm -= 0x04000000
    return index * 4 + imm * 4

matches = []
for i in range(len(words) - 12):
    if words[i] != 0xAA0003F6 or words[i + 1] != 0xF94013E0:
        continue
    if words[i + 2] != NOP and not is_bl(words[i + 2]):
        continue
    ok = True
    call_offsets = [4, 6, 8, 10, 12]
    for n, mov in enumerate(MOVS):
        move_idx = i + 3 + n * 2
        call_idx = i + 4 + n * 2
        if words[move_idx] != mov or not is_bl(words[call_idx]):
            ok = False
            break
    if not ok:
        continue
    target = bl_target(i + 4, words[i + 4])
    if any(bl_target(i + off, words[i + off]) != target for off in call_offsets):
        continue
    if is_bl(words[i + 2]) and bl_target(i + 2, words[i + 2]) != target:
        continue
    matches.append((i + 2, words[i + 2] == NOP))

if len(matches) != 1:
    print(f'Safety check failed: expected exactly one libpag release sequence, found {len(matches)}.', file=sys.stderr)
    sys.exit(20)

word_index, already_patched = matches[0]
offset = word_index * 4
print(f'Gefundene Patchposition im ARM64-Slice: 0x{offset:X}')
if already_patched:
    print('Patch ist bereits vorhanden.')
    sys.exit(0)

data[offset:offset+4] = struct.pack('<I', NOP)
path.write_bytes(data)
print('Patch gesetzt: unsicherer CFRelease-Aufruf -> ARM64 NOP.')
PY
}

print_header

CURRENT_ARCH="$(/usr/bin/uname -m)"
[[ "$CURRENT_ARCH" == "arm64" ]] || fail "Dieser Fix unterstützt aktuell nur Apple-Silicon-Macs (arm64). Gefunden: $CURRENT_ARCH"

MACOS_VERSION="$(/usr/bin/sw_vers -productVersion)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if [[ "$MACOS_MAJOR" != "27" ]]; then
    fail "Dieser Workaround ist ausschließlich für macOS 27 vorgesehen. Installiert: macOS $MACOS_VERSION"
fi

ORIGINAL_APP="$(find_eufymake_app)" || fail "eufyMake Studio wurde weder in /Applications noch in ~/Applications gefunden."
INFO_PLIST="$ORIGINAL_APP/Contents/Info.plist"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo unknown)"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST" 2>/dev/null || echo unknown)"
ORIGINAL_BIN="$ORIGINAL_APP/Contents/MacOS/$EXECUTABLE"
PATCHED_BIN="$PATCHED_APP/Contents/MacOS/$EXECUTABLE"

[[ -f "$ORIGINAL_BIN" ]] || fail "Das Hauptprogramm wurde nicht gefunden: $ORIGINAL_BIN"

ARCHS="$(/usr/bin/lipo -archs "$ORIGINAL_BIN" 2>/dev/null)" || fail "Die Architektur des eufyMake-Binaries konnte nicht gelesen werden."
[[ " $ARCHS " == *" arm64 "* ]] || fail "Die installierte eufyMake-Version enthält keine ARM64-Version. Architekturen: $ARCHS"

mkdir -p "$FIX_ROOT"
chmod 700 "$FIX_ROOT" 2>/dev/null || true

# Remove quarantine from the downloaded launcher after the user has opened it once.
/usr/bin/xattr -dr com.apple.quarantine "${0:A:h}" 2>/dev/null || true

SOURCE_HASH="$(hash_file "$ORIGINAL_BIN")"
CACHED_HASH=""
if [[ -f "$METADATA_FILE" ]]; then
    CACHED_HASH="$(/usr/bin/awk -F= '$1=="SOURCE_SHA256" {print $2}' "$METADATA_FILE" 2>/dev/null | head -1)"
    CACHED_PATCHED_HASH="$(/usr/bin/awk -F= '$1=="PATCHED_SHA256" {print $2}' "$METADATA_FILE" 2>/dev/null | head -1)"
else
    CACHED_PATCHED_HASH=""
fi

CURRENT_PATCHED_HASH=""
if [[ -f "$PATCHED_BIN" ]]; then
    CURRENT_PATCHED_HASH="$(hash_file "$PATCHED_BIN" 2>/dev/null || true)"
fi

if [[ -d "$PATCHED_APP" && -f "$PATCHED_BIN" && "$CACHED_HASH" == "$SOURCE_HASH" && -n "$CACHED_PATCHED_HASH" && "$CURRENT_PATCHED_HASH" == "$CACHED_PATCHED_HASH" ]]; then
    echo "Installierte eufyMake-Version: $APP_VERSION ($APP_BUILD)"
    echo "Bereits gepatchte Kopie gefunden."
    echo ""
    echo "Starte eufyMake Studio nativ als ARM64 ..."
    killall "$EXECUTABLE" 2>/dev/null || true
    (
        cd "$PATCHED_APP/Contents/MacOS" || exit 1
        /usr/bin/nohup /usr/bin/arch -arm64 "./$EXECUTABLE" >>"$LOG_FILE" 2>&1 &
    )
    echo "Fertig."
    exit 0
fi

echo "macOS:                 $MACOS_VERSION"
echo "Original-App:          $ORIGINAL_APP"
echo "eufyMake-Version:      $APP_VERSION ($APP_BUILD)"
echo "Architekturen:         $ARCHS"
echo ""
echo "Erstelle eine neue gepatchte Kopie ..."

WORK_DIR="$(/usr/bin/mktemp -d /tmp/eufymake-macos27-fix.XXXXXX)" || fail "Temporäres Arbeitsverzeichnis konnte nicht erstellt werden."
WORK_APP="$WORK_DIR/eufyMake Studio Working.app"
ARM64_SLICE="$WORK_DIR/eufyStudio.arm64"
X86_SLICE="$WORK_DIR/eufyStudio.x86_64"
UNIVERSAL_BIN="$WORK_DIR/eufyStudio.universal"
SIGNED_BIN="$WORK_DIR/eufyStudio.signed"
ENTITLEMENTS="$WORK_DIR/entitlements.plist"

killall "$EXECUTABLE" 2>/dev/null || true

rm -rf "$WORK_APP" "$PATCHED_APP"
/usr/bin/ditto "$ORIGINAL_APP" "$WORK_APP" || fail "Die eufyMake-App konnte nicht kopiert werden."
/usr/bin/xattr -cr "$WORK_APP" 2>/dev/null || true

WORK_BIN="$WORK_APP/Contents/MacOS/$EXECUTABLE"
/usr/bin/lipo "$WORK_BIN" -thin arm64 -output "$ARM64_SLICE" || fail "ARM64-Slice konnte nicht extrahiert werden."

if [[ " $ARCHS " == *" x86_64 "* ]]; then
    /usr/bin/lipo "$WORK_BIN" -thin x86_64 -output "$X86_SLICE" || fail "x86_64-Slice konnte nicht extrahiert werden."
fi

echo "Suche die bekannte libpag-Crashsequenz ..."
if [[ -x /usr/bin/perl ]]; then
    patch_arm64_perl "$ARM64_SLICE" || fail "Die bekannte Crashsequenz wurde nicht eindeutig gefunden. Diese eufyMake-Version wird aus Sicherheitsgründen nicht verändert."
elif command -v python3 >/dev/null 2>&1; then
    patch_arm64_python "$ARM64_SLICE" || fail "Die bekannte Crashsequenz wurde nicht eindeutig gefunden. Diese eufyMake-Version wird aus Sicherheitsgründen nicht verändert."
else
    fail "Weder /usr/bin/perl noch python3 ist verfügbar. Mindestens eine der beiden Laufzeiten wird für den sicheren Pattern-Scan benötigt."
fi

if [[ -f "$X86_SLICE" ]]; then
    /usr/bin/lipo -create "$X86_SLICE" "$ARM64_SLICE" -output "$UNIVERSAL_BIN" || fail "Universal Binary konnte nicht neu erstellt werden."
else
    cp "$ARM64_SLICE" "$UNIVERSAL_BIN" || fail "ARM64-Binary konnte nicht vorbereitet werden."
fi
chmod +x "$UNIVERSAL_BIN"

/usr/bin/codesign -d --entitlements :- "$ORIGINAL_APP" > "$ENTITLEMENTS" 2>/dev/null || fail "Die ursprünglichen App-Entitlements konnten nicht gelesen werden."

cp "$UNIVERSAL_BIN" "$SIGNED_BIN" || fail "Das gepatchte Binary konnte nicht für die Signierung vorbereitet werden."
/usr/bin/xattr -c "$SIGNED_BIN" 2>/dev/null || true
/usr/bin/codesign --remove-signature "$SIGNED_BIN" 2>/dev/null || true

/usr/bin/codesign \
    --force \
    --sign - \
    --identifier "$BUNDLE_ID" \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$SIGNED_BIN" >/dev/null || fail "Das gepatchte Binary konnte nicht ad-hoc signiert werden."

/usr/bin/codesign --verify --strict --verbose=2 "$SIGNED_BIN" >/dev/null 2>&1 || fail "Die Signatur des gepatchten Binaries ist ungültig."

cp "$SIGNED_BIN" "$WORK_BIN" || fail "Das signierte Binary konnte nicht in die gepatchte App kopiert werden."
chmod +x "$WORK_BIN"

mkdir -p "${PATCHED_APP:h}"
/usr/bin/ditto "$WORK_APP" "$PATCHED_APP" || fail "Die fertige gepatchte App konnte nicht installiert werden."
/usr/bin/xattr -dr com.apple.quarantine "$PATCHED_APP" 2>/dev/null || true
chmod -R u+rwX "$PATCHED_APP" 2>/dev/null || true

PATCHED_HASH="$(hash_file "$PATCHED_BIN")"
cat > "$METADATA_FILE" <<META
SOURCE_SHA256=$SOURCE_HASH
PATCHED_SHA256=$PATCHED_HASH
APP_VERSION=$APP_VERSION
APP_BUILD=$APP_BUILD
SCRIPT_VERSION=$SCRIPT_VERSION
META
chmod 600 "$METADATA_FILE" 2>/dev/null || true

# Final safety verification: extract ARM64 from the installed copy and make sure
# the exact sequence now contains NOP instead of the unsafe CFRelease call.
VERIFY_SLICE="$WORK_DIR/verify.arm64"
/usr/bin/lipo "$PATCHED_BIN" -thin arm64 -output "$VERIFY_SLICE" || fail "Abschlussprüfung konnte den ARM64-Slice nicht lesen."
if [[ -x /usr/bin/perl ]]; then
    is_patch_present_perl "$VERIFY_SLICE" || fail "Die Abschlussprüfung konnte den Patch nicht bestätigen."
fi

echo ""
echo "============================================================"
echo " FIX ERFOLGREICH INSTALLIERT"
echo "============================================================"
echo ""
echo "Original bleibt unverändert:"
echo "  $ORIGINAL_APP"
echo ""
echo "Gepatchte Kopie:"
echo "  $PATCHED_APP"
echo ""
echo "Starte eufyMake Studio jetzt nativ als ARM64 ..."

killall "$EXECUTABLE" 2>/dev/null || true
(
    cd "$PATCHED_APP/Contents/MacOS" || exit 1
    /usr/bin/nohup /usr/bin/arch -arm64 "./$EXECUTABLE" >>"$LOG_FILE" 2>&1 &
)

echo ""
echo "eufyMake Studio wurde gestartet."
echo "Log: $LOG_FILE"
echo ""
echo "Dieses .command-Skript kann künftig einfach erneut doppelt angeklickt werden."
echo "Bei unveränderter eufyMake-Version wird der vorhandene Fix direkt gestartet."
