#!/bin/bash
set -e
echo "=== Frozen Bubble → SUPREME 100% STANDALONE (FIXED v63 - PATCH INSIDE PP ONLY) ==="
# ────────────────────── CONFIG ──────────────────────
APP_NAME="FrozenBubble"
APP_DIR="$HOME/$APP_NAME.AppDir"
OUTPUT_APPIMAGE="$HOME/${APP_NAME}-SUPREME-x86_64.AppImage"
ICON_SRC="/usr/share/icons/hicolor/64x64/apps/frozen-bubble.png"
LAUNCHER_SCRIPT="$APP_DIR/AppRun"
EXECUTABLE="$APP_DIR/usr/bin/frozen-bubble"
WRAPPED_SCRIPT="/tmp/frozen-bubble-supreme-wrapped.pl"
LIBPERL_SO="$APP_DIR/usr/lib/libperl.so"
CLEAN_BODY="/tmp/clean_body.pl"
SOURCE_PM_PATH="/usr/share/perl5/Games/FrozenBubble/Config.pm"
BUNDLE_PM_PATH="$APP_DIR/usr/bin/lib/Games/FrozenBubble/Config.pm"
# ────────────────────── AUTO-DETECT ──────────────────────
ORIGINAL_SCRIPT="$(which frozen-bubble || echo "")"
[ -z "$ORIGINAL_SCRIPT" ] && { echo "Install frozen-bubble first!"; exit 1; }
# Detect data dir (try standard paths)
DATA_DIR=""
for possible in "/usr/share/games/frozen-bubble" "/usr/share/frozen-bubble" "/usr/games/frozen-bubble"; do
  if [ -d "$possible" ]; then
    DATA_DIR="$possible"
    echo "Found data dir: $DATA_DIR"
    break
  fi
done
[ -z "$DATA_DIR" ] && { echo "Data dir missing! Tried: /usr/share/games/frozen-bubble, /usr/share/frozen-bubble, /usr/games/frozen-bubble"; exit 1; }
BUNDLE_DATA_DIR="$APP_DIR/usr/share/games/frozen-bubble"
# Clean
rm -rf "$APP_DIR" "$OUTPUT_APPIMAGE" "$HOME/perl-install" "$HOME/.cpan" "$HOME/perl-build" "$WRAPPED_SCRIPT" /tmp/scan_wrapper.pl "$CLEAN_BODY"
# FIXED: Create root AppDir before subdirs
mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/usr/bin" "$APP_DIR/usr/lib" "$APP_DIR/usr/bin/lib/Games/FrozenBubble" "$BUNDLE_DATA_DIR"
# ────────────────────── 1. BUILD SHARED PERL ──────────────────────
echo "[1/10] Building SHARED Perl..."
mkdir -p "$HOME/perl-build"
cd "$HOME/perl-build"
wget -qO- https://www.cpan.org/src/5.0/perl-5.38.2.tar.gz | tar xz
cd perl-5.38.2
sh Configure -des -Dprefix="$HOME/perl-install" -Dccflags="-fPIC -O2" -Duseshrplib=true -Dman1dir=none -Dman3dir=none
make -j$(nproc)
make install
# ────────────────────── 2. COPY libperl.so (WITH FALLBACK) ──────────────────────
echo "[2/10] Embedding libperl.so..."
ARCHNAME="$($HOME/perl-install/bin/perl -e 'use Config; print $Config{archname}')"
CUSTOM_LIBPERL="$HOME/perl-install/lib/5.38.2/$ARCHNAME/CORE/libperl.so"
if [ -f "$CUSTOM_LIBPERL" ]; then
  echo " → Using custom Perl libperl.so"
  cp "$CUSTOM_LIBPERL" "$LIBPERL_SO"
else
  echo " → Custom libperl.so not found, falling back to system libperl.so..."
  SYSTEM_LIBPERL="$($HOME/perl-install/bin/perl -e 'use Config; print $Config{libperl}')"
  if [ -f "$SYSTEM_LIBPERL" ]; then
    cp "$SYSTEM_LIBPERL" "$LIBPERL_SO"
  else
    echo " → System libperl.so not found, trying common system path..."
    SYSTEM_FALLBACK="/usr/lib/x86_64-linux-gnu/libperl.so*"
    if ls $SYSTEM_FALLBACK 1> /dev/null 2>&1; then
      cp $(ls $SYSTEM_FALLBACK | head -1) "$LIBPERL_SO"
    else
      echo " → No libperl.so found, AppImage may fail to bundle Perl modules."
      touch "$LIBPERL_SO" # Placeholder
    fi
  fi
fi
# ────────────────────── 3. SETUP CPAN AUTO-YES ──────────────────────
echo "[3/10] CPAN auto-yes..."
export PATH="$HOME/perl-install/bin:$PATH"
mkdir -p "$HOME/.cpan/CPAN"
cat > "$HOME/.cpan/CPAN/MyConfig.pm" << 'EOF'
$CPAN::Config = {
  'auto_commit' => 1,
  'make_install_arg' => q[--notest],
  'prerequisites_policy' => q[follow],
  'yes' => 1,
};
1;
EOF
perl -MCPAN -e 'CPAN::Shell->notest("install", "PAR::Packer", "Module::ScanDeps", "SDL");'
# ────────────────────── 4. COPY DATA ──────────────────────
echo "[4/10] Copying game data to bundled /usr/share/games/frozen-bubble..."
cp -r "$DATA_DIR"/* "$BUNDLE_DATA_DIR/"
# ────────────────────── 4.5. COPY & PATCH APPDIR CONFIG.PM AT /usr/bin/lib/ ──────────────────────
echo "[4.5/10] Copying & patching Config.pm in AppDir at /usr/bin/lib/Games/FrozenBubble/Config.pm..."
if [ -f "$SOURCE_PM_PATH" ]; then
  ls -la "$SOURCE_PM_PATH"
  echo " → Found source Config.pm at: $SOURCE_PM_PATH"
  # Copy to AppDir /usr/bin/lib/
  cp "$SOURCE_PM_PATH" "$BUNDLE_PM_PATH"
  echo " → Copied to AppDir /usr/bin/lib/ target: $BUNDLE_PM_PATH"
  ls -la "$BUNDLE_PM_PATH"
  # Add File::Basename if missing
  grep -q "use File::Basename" "$BUNDLE_PM_PATH" || sed -i '1i use File::Basename;' "$BUNDLE_PM_PATH"
  # Determine dirname count (5 for AppDir/usr/bin/lib/Games/FrozenBubble)
  DIRNAME_COUNT=5
  echo " → Using 5x dirname for AppDir/usr/bin/lib/Games path"
  DIRNAME_STR=""
  for i in $(seq 1 $DIRNAME_COUNT); do DIRNAME_STR="$DIRNAME_STR dirname("; done
  DIRNAME_STR="$DIRNAME_STR __FILE__"
  for i in $(seq 1 $DIRNAME_COUNT); do DIRNAME_STR="$DIRNAME_STR )"; done
  # Patch $FPATH/$FLPATH
  sed -i "s/\$FPATH\s*=\s*'[^']*'\s*;\s*/\$FPATH = \$ENV{DATA_DIR} || $DIRNAME_STR . '\/usr\/share\/games\/frozen-bubble'; /" "$BUNDLE_PM_PATH"
  sed -i "s/\$FLPATH\s*=\s*'[^']*'\s*;\s*/\$FLPATH = \$ENV{DATA_DIR} || \$FPATH; /" "$BUNDLE_PM_PATH"
  echo " → AppDir /usr/bin/lib/ Config.pm patched (DATA_DIR hack applied)"
  echo " → Post-patch \$FPATH: $(grep "\$FPATH" "$BUNDLE_PM_PATH")"
  echo " → Post-patch \$FLPATH: $(grep "\$FLPATH" "$BUNDLE_PM_PATH")"
else
  echo " → Source Config.pm not found at $SOURCE_PM_PATH (run: sudo apt install frozen-bubble) - skipping copy/patch"
fi
# ────────────────────── 5. CREATE WRAPPED SCRIPT (PATH HACK) ──────────────────────
echo "[5/10] Creating wrapped script (absolute path → $data_dir hack)..."
sed '1d' "$ORIGINAL_SCRIPT" > "$CLEAN_BODY"
# Remove original decls/chdir to avoid conflicts
sed -i "/^\s*my \$data_dir\s*=\s*['\"](\/usr\/share\/games\/frozen-bubble|\/usr\/share\/frozen-bubble|\/usr\/games\/frozen-bubble)['\"]\s*;/d" "$CLEAN_BODY"
sed -i "/^\s*chdir \$data_dir;\s*$/d" "$CLEAN_BODY"
# Replace absolutes with placeholder (quoted/unquoted)
sed -i 's|"/usr/share/games/frozen-bubble"|"__DATA_DIR__"|g' "$CLEAN_BODY"
sed -i 's|"/usr/share/frozen-bubble"|"__DATA_DIR__"|g' "$CLEAN_BODY"
sed -i 's|/usr/share/games/frozen-bubble|__DATA_DIR__|g' "$CLEAN_BODY"
sed -i 's|/usr/share/frozen-bubble|__DATA_DIR__|g' "$CLEAN_BODY"
sed -i 's|/usr/games/frozen-bubble|__DATA_DIR__|g' "$CLEAN_BODY"
# Hack $prefix
sed -i 's|^\s*my \$prefix =.*|my \$prefix = \$appdir;|' "$CLEAN_BODY"
sed -i 's|^\s*\$prefix =.*|\$prefix = \$appdir;|' "$CLEAN_BODY"
# Header with early safe decl (avoids strict errors)
cat > "$WRAPPED_SCRIPT" << 'EOF'
#!/usr/bin/perl
use strict;
use warnings;
no warnings 'uninitialized';
use FindBin '$RealBin';
use File::Basename;
BEGIN {
    if (exists $ENV{BUILD_LIB} && $ENV{BUILD_LIB} ne '') {
        require lib;
        lib->import($ENV{BUILD_LIB});
    }
}
my $appdir = $ENV{APPDIR} || dirname($RealBin);
my $fallback_dir = $appdir . "/usr/share/games/frozen-bubble";
my $data_dir = $ENV{DATA_DIR} || $fallback_dir;
if (!$ENV{BUILD_MODE}) {
    if (-d $data_dir) {
        chdir $data_dir or die "chdir failed: $!";
    } else {
        die "Data directory $data_dir does not exist!";
    }
}
EOF
cat "$CLEAN_BODY" >> "$WRAPPED_SCRIPT"
sed -i 's|__DATA_DIR__|\$data_dir|g' "$WRAPPED_SCRIPT" # Safe post-decl replace
perl -c "$WRAPPED_SCRIPT" && echo " → Wrapped script syntax OK"
# ────────────────────── 6. FULL SCAN WITH COMPILE ──────────────────────
echo "[6/10] Full dependency scan (using AppDir /usr/bin/lib/ patched module)..."
export BUILD_LIB="$APP_DIR/usr/bin/lib"
cat > /tmp/scan_wrapper.pl <<EOF
@ARGV = ('--help');
do '$WRAPPED_SCRIPT';
EOF
export BUILD_MODE=1
DEPS=$(perl -MModule::ScanDeps -e "print for keys %{scan_deps(files => ['/tmp/scan_wrapper.pl'], recurse => 1, compile => 1)}" | grep -v '^/' | sort -u | grep -v 'perlmain')
unset BUILD_MODE
unset BUILD_LIB
MODULES=()
for dep in $DEPS; do dep=${dep%.pm}; dep=${dep//:://}; MODULES+=("$dep"); done
echo " → Found ${#MODULES[@]} modules"
# ────────────────────── 7. FINAL PP WITH ALL -M + ATTACH ──────────────────────
echo "[7/10] Bundling executable (PAR bundles AppDir /usr/bin/lib/ patched module)..."
FINAL_CMD=(pp -o "$EXECUTABLE" --gui --clean --cachedeps --verbose --link "$LIBPERL_SO")
for m in "${MODULES[@]}"; do FINAL_CMD+=("-M" "$m"); done
FINAL_CMD+=("$WRAPPED_SCRIPT")
cd "$HOME"
export BUILD_MODE=1
"${FINAL_CMD[@]}"
unset BUILD_MODE
chmod +x "$EXECUTABLE"
# FIXED v63: Remove temporary /usr/bin/lib after bundling (patched Config.pm now ONLY inside pp)
rm -rf "$APP_DIR/usr/bin/lib"
echo "[7/10] Bundling complete! (Temp /usr/bin/lib removed; Config.pm inside pp only)"
# ────────────────────── 8. COPY SDL LIBS & ICON ──────────────────────
echo "[8/10] Copying SDL libs and icon..."
mkdir -p "$APP_DIR/usr/lib"
for lib in libSDL-1.2.so.0 libSDL_mixer-1.2.so.0 libSDL_image-1.2.so.0 libSDL_ttf-2.0.so.0 libSDL_gfx.so.15 libmikmod.so.3 libflac.so.12 libfluidsynth.so.3 libmad.so.0 libvorbisfile.so.3 libvorbis.so.0 libogg.so.0 libSDL_Pango.so.1 libpango-1.0.so.0 libpangocairo-1.0.so.0 libpangoft2-1.0.so.0 libcairo.so.2 libgobject-2.0.so.0 libglib-2.0.so.0 libgio-2.0.so.0 libgmodule-2.0.so.0 libffi.so.8 libfreetype.so.6 libfontconfig.so.1 libharfbuzz.so.0 libpng16.so.16 libjpeg.so.8 libtiff.so.6 libsmpeg.so.0 libthai.so.0 libdatrie.so.1 libpixman-1.so.0 libxcb-shm.so.0 libxcb-render.so.0 libxcb.so.1 libXrender.so.1 libX11.so.6 libXext.so.6 libLerc.so.4 libdeflate.so.0 libselinux.so.1 libpcre2-8.so.0 libz.so.1 libbz2.so.1 liblzma.so.5 libbrotlienc.so.1 libbrotlidec.so.1 libxml2.so.2; do
  cp -L /usr/lib/x86_64-linux-gnu/$lib* "$APP_DIR/usr/lib/" 2>/dev/null || true
done
[ -f "$ICON_SRC" ] && { mkdir -p "$APP_DIR/usr/share/icons/hicolor/64x64/apps"; cp "$ICON_SRC" "$APP_DIR/usr/share/icons/hicolor/64x64/apps/frozen-bubble.png"; cp "$ICON_SRC" "$APP_DIR/frozen-bubble.png"; cp "$ICON_SRC" "$APP_DIR/.DirIcon"; }
echo " → Patched Config.pm bundled inside pp (no AppDir copy left)"
# ────────────────────── 9. APPRUN & BUILD ──────────────────────
echo "[9/10] Creating AppRun (DATA_DIR env hack; no PERL5LIB needed post-bundle)..."
cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export APPDIR="${HERE}"
export DATA_DIR="${HERE}/usr/share/games/frozen-bubble" # HACK: Force bundled data path
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export SDL_AUDIODRIVER=alsa
CONFIG_DIR="$HOME/.local/share/frozen-bubble"
mkdir -p "$CONFIG_DIR"
cp -n "${HERE}/usr/share/games/frozen-bubble/scores" "$CONFIG_DIR/" 2>/dev/null || true
exec "${HERE}/usr/bin/frozen-bubble" "$@"
EOF
chmod +x "$LAUNCHER_SCRIPT"
mkdir -p "$APP_DIR/usr/share/applications"
cat > "$APP_DIR/usr/share/applications/$APP_NAME.desktop" << EOF
[Desktop Entry]
Name=Frozen Bubble
Exec=frozen-bubble
Icon=frozen-bubble
Type=Application
Categories=Game;ArcadeGame;
EOF
ln -s "usr/share/applications/$APP_NAME.desktop" "$APP_DIR/$APP_NAME.desktop"
TOOL="$HOME/appimagetool-x86_64.AppImage"
[ -f "$TOOL" ] || wget -qO "$TOOL" "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" && chmod +x "$TOOL"
"$TOOL" --no-appstream "$APP_DIR" "$OUTPUT_APPIMAGE"
# ────────────────────── 10. FINALIZE ──────────────────────
echo "=================================================="
echo "SUCCESS! HACKED AppImage created: $OUTPUT_APPIMAGE"
echo "Fixed v63: Patched Config.pm bundled INSIDE pp only (no AppDir/usr/bin/lib/ left)"
echo "Fixed: rm -rf AppDir/usr/bin/lib after pp (not in root/folder)"
echo "Fixed: Removed PERL5LIB export from AppRun (bundled via PAR)"
echo "Fixed: ls -la source and AppDir target before/after copy"
echo "Fixed: DIRNAME_COUNT=5 for AppDir/usr/bin/lib/Games path"
echo "Fixed: BUILD_LIB=AppDir/usr/bin/lib for scan/pp (bundles patched)"
echo "Hack Summary:"
echo "- Data copied to AppDir/usr/share/games/frozen-bubble (bundled)"
echo "- Config.pm copied + patched → scanned/bundled INSIDE pp (temp dir removed)"
echo "- Bundled patched module via AppDir /usr/bin/lib scan + PAR -M"
echo "- Main script: Absolute paths → \$data_dir (strict-safe)"
echo "- AppRun: export DATA_DIR=AppDirRoot/usr/share/games/frozen-bubble"
echo "- chdir \$data_dir early (cwd = bundled data)"
echo "- Run: ~/$OUTPUT_APPIMAGE"
echo "- Compress: upx --best --lzma $OUTPUT_APPIMAGE (~40-50 MB)"
echo "=================================================="
