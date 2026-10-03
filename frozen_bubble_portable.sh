#!/bin/bash
set -e
echo "=== Frozen Bubble → SUPREME 100% STANDALONE (FIXED v72 - CSTUFF & ENCODE FIX) ==="

# ────────────────────── INSTALLING PREREQUISITES ──────────────────────
echo "[1/10] Installing system prerequisites..."

sudo apt install -y build-essential bzip2 libbz2-dev pkg-config wget curl file \
libsdl1.2-dev libsdl-image1.2-dev libsdl-mixer1.2-dev libsdl-ttf2.0-dev libsdl-gfx1.2-dev libsdl-pango-dev \
frozen-bubble frozen-bubble-data libsdl-perl

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
RUNTIME_PM_PATH="$APP_DIR/usr/share/perl5/Games/FrozenBubble/Config.pm"
PERL_VERSION="5.38.2"

# ────────────────────── AUTO-DETECT ──────────────────────
ORIGINAL_SCRIPT="$(which frozen-bubble || echo "")"
[ -z "$ORIGINAL_SCRIPT" ] && { echo "Install frozen-bubble first!"; exit 1; }
ORIGINAL_SCRIPT="$(readlink -f "$ORIGINAL_SCRIPT")"

DATA_DIR=""
for possible in "/usr/share/games/frozen-bubble" "/usr/share/frozen-bubble" "/usr/games/frozen-bubble"; do
    if [ -d "$possible" ]; then
        DATA_DIR="$possible"
        echo "Found data dir: $DATA_DIR"
        break
    fi
done
[ -z "$DATA_DIR" ] && { echo "Data dir missing!"; exit 1; }
BUNDLE_DATA_DIR="$APP_DIR/usr/share/games/frozen-bubble"

# Clean
rm -rf "$APP_DIR" "$OUTPUT_APPIMAGE" "$HOME/perl-install" "$HOME/.cpan" "$HOME/perl-build" "$WRAPPED_SCRIPT" /tmp/scan_wrapper.pl "$CLEAN_BODY"
mkdir -p "$APP_DIR" "$APP_DIR/usr/bin" "$APP_DIR/usr/lib" "$APP_DIR/usr/bin/lib/Games/FrozenBubble" "$APP_DIR/usr/share/perl5/Games/FrozenBubble" "$BUNDLE_DATA_DIR"

# ────────────────────── 1. BUILD SHARED PERL ──────────────────────
echo "[1/10] Building SHARED Perl..."
mkdir -p "$HOME/perl-build"
cd "$HOME/perl-build"
wget -qO- https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz | tar xz
cd perl-${PERL_VERSION}
sh Configure -des -Dprefix="$HOME/perl-install" -Dccflags="-fPIC -O2" -Duseshrplib=true -Dman1dir=none -Dman3dir=none
make -j$(nproc)
make install

PERL_BIN="$HOME/perl-install/bin/perl"
export PATH="$HOME/perl-install/bin:$PATH"
hash -r
ARCHNAME="$("$PERL_BIN" -e 'use Config; print $Config{archname}')"

# ────────────────────── 2. COPY libperl.so (WITH FALLBACK) ──────────────────────
echo "[2/10] Embedding libperl.so..."
CUSTOM_LIBPERL="$HOME/perl-install/lib/${PERL_VERSION}/$ARCHNAME/CORE/libperl.so"
if [ -f "$CUSTOM_LIBPERL" ]; then
    cp -L "$CUSTOM_LIBPERL" "$LIBPERL_SO"
else
    SYSTEM_FALLBACK_FILE=$(find /usr/lib/x86_64-linux-gnu/ -name "libperl.so*" 2>/dev/null | head -n 1)
    [ -n "$SYSTEM_FALLBACK_FILE" ] && cp -L "$SYSTEM_FALLBACK_FILE" "$LIBPERL_SO" || touch "$LIBPERL_SO"
fi

# ────────────────────── 3. SETUP CPAN & INSTALL SDL + CSTUFF ──────────────────────
echo "[3/10] Installing tools, SDL, and CStuff on Perl 5.38...."
unset PERL5LIB
export PERL_MM_USE_DEFAULT=1
export PERL_EXTUTILS_AUTOINSTALL="--defaultdeps"

curl -L https://cpanmin.us | "$PERL_BIN" - --notest App::cpanminus
CPANM="$HOME/perl-install/bin/cpanm"

"$CPANM" --notest Module::ScanDeps Compress::Bzip2 PAR::Packer Encode::Locale

echo " → Installing hidden dependencies of Alien::SDL..."
"$CPANM" --notest File::Which File::ShareDir File::Fetch Archive::Extract Archive::Tar Archive::Zip Text::Patch Capture::Tiny Module::Build Digest::SHA ExtUtils::CBuilder File::Path File::Temp File::Spec File::Find

echo " → Downloading and compiling Alien::SDL (interactive bypass with --travis)..."
cd /tmp
rm -rf Alien-SDL-1.446 Alien-SDL-1.446.tar.gz
wget -q http://www.cpan.org/authors/id/F/FR/FROGGS/Alien-SDL-1.446.tar.gz
tar xzf Alien-SDL-1.446.tar.gz
cd Alien-SDL-1.446
"$PERL_BIN" Build.PL --travis
"$PERL_BIN" ./Build
"$PERL_BIN" ./Build install
cd /tmp && rm -rf Alien-SDL-1.446 Alien-SDL-1.446.tar.gz

echo " → Installing main SDL module..."
"$CPANM" --notest SDL || "$CPANM" --notest --force SDL

echo " → Installing Games::FrozenBubble from CPAN (this compiles CStuff.so for Perl 5.38)..."
"$CPANM" --notest Games::FrozenBubble || echo "WARNING: Games::FrozenBubble failed. CStuff.so might be missing."

echo " → Checking SDL..."
"$PERL_BIN" -MSDL -e 'print "SDL OK: $SDL::VERSION\n"'

# ────────────────────── 4. COPY DATA & PATCH CONFIG ──────────────────────
echo "[4/10] Copying game data & patching Config.pm..."
cp -r "$DATA_DIR"/* "$BUNDLE_DATA_DIR/"

if [ -f "$SOURCE_PM_PATH" ]; then
    cp "$SOURCE_PM_PATH" "$BUNDLE_PM_PATH"
    cp "$SOURCE_PM_PATH" "$RUNTIME_PM_PATH"
    grep -q "use File::Basename" "$BUNDLE_PM_PATH" || sed -i '1i use File::Basename;' "$BUNDLE_PM_PATH"
    grep -q "use File::Basename" "$RUNTIME_PM_PATH" || sed -i '1i use File::Basename;' "$RUNTIME_PM_PATH"
    
    DIRNAME_STR="dirname(dirname(dirname(dirname(dirname(__FILE__)))))"
    
    sed -i "s#\$FPATH\s*=\s*['\"][^'\"]*['\"]\s*;#\$FPATH = \$ENV{DATA_DIR} || $DIRNAME_STR . '/usr/share/games/frozen-bubble';#" "$BUNDLE_PM_PATH"
    sed -i "s#\$FLPATH\s*=\s*['\"][^'\"]*['\"]\s*;#\$FLPATH = \$ENV{DATA_DIR} || \$FPATH;#" "$BUNDLE_PM_PATH"
    
    sed -i "s#\$FPATH\s*=\s*['\"][^'\"]*['\"]\s*;#\$FPATH = \$ENV{DATA_DIR} || $DIRNAME_STR . '/usr/share/games/frozen-bubble';#" "$RUNTIME_PM_PATH"
    sed -i "s#\$FLPATH\s*=\s*['\"][^'\"]*['\"]\s*;#\$FLPATH = \$ENV{DATA_DIR} || \$FPATH;#" "$RUNTIME_PM_PATH"
fi

# ────────────────────── 5. CREATING WRAPPED SCRIPT ──────────────────────
echo "[5/10] Creating wrapped script..."
sed '1d' "$ORIGINAL_SCRIPT" > "$CLEAN_BODY"
sed -i "/^\s*my \$data_dir\s*=\s*['\"][^'\"]*['\"]\s*;/d" "$CLEAN_BODY"
sed -i "/^\s*chdir \$data_dir;\s*$/d" "$CLEAN_BODY"
sed -i 's|/usr/share/games/frozen-bubble|__DATA_DIR__|g' "$CLEAN_BODY"
sed -i 's|/usr/share/frozen-bubble|__DATA_DIR__|g' "$CLEAN_BODY"
sed -i 's|/usr/games/frozen-bubble|__DATA_DIR__|g' "$CLEAN_BODY"
sed -i 's|^\s*my \$prefix =.*|my \$prefix = \$appdir;|' "$CLEAN_BODY"
sed -i 's|^\s*\$prefix =.*|\$prefix = \$appdir;|' "$CLEAN_BODY"

SAFE_SHARE_DIR="/usr/share/perl5"
cat > "$WRAPPED_SCRIPT" << EOF
#!/usr/bin/perl
use strict; use warnings;
no warnings 'uninitialized'; no warnings 'redefine';
use FindBin '\$RealBin'; use File::Basename;
BEGIN {
    push @INC, '$SAFE_SHARE_DIR' if -d '$SAFE_SHARE_DIR';
    push @INC, split(/:/, \$ENV{BUILD_LIB}) if \$ENV{BUILD_LIB};
    if (my \$ad = \$ENV{APPDIR}) {
        push @INC, "\$ad/usr/share/perl5" if -d "\$ad/usr/share/perl5";
    }
}
my \$appdir = \$ENV{APPDIR} || dirname(\$RealBin);
my \$fallback_dir = \$appdir . "/usr/share/games/frozen-bubble";
my \$data_dir = \$ENV{DATA_DIR} || \$fallback_dir;
if (!\$ENV{BUILD_MODE}) {
    chdir \$data_dir or die "chdir failed: \$!";
}
EOF
cat "$CLEAN_BODY" >> "$WRAPPED_SCRIPT"
sed -i 's|__DATA_DIR__|\$data_dir|g' "$WRAPPED_SCRIPT"

unset PERL5LIB
"$PERL_BIN" -I"$SAFE_SHARE_DIR" -c "$WRAPPED_SCRIPT" && echo " → Wrapped script syntax OK"

# ────────────────────── 6. FULL SCAN WITH COMPILE ──────────────────────
echo "[6/10] Full dependency scan..."
unset PERL5LIB
export BUILD_LIB="$APP_DIR/usr/bin/lib"
cat > /tmp/scan_wrapper.pl <<EOF
@ARGV = ('--help');
do '$WRAPPED_SCRIPT';
EOF
export BUILD_MODE=1

DEPS=$(BUILD_LIB="$APP_DIR/usr/bin/lib" BUILD_MODE=1 "$PERL_BIN" -I"$SAFE_SHARE_DIR" -I"$APP_DIR/usr/bin/lib" -I"$APP_DIR/usr/share/perl5" -MModule::ScanDeps -e "print \"\$_\\n\" for keys %{scan_deps(files => ['/tmp/scan_wrapper.pl'], recurse => 1, compile => 1)}" | grep -v '^/' | sort -u | grep -v 'perlmain' || true)
unset BUILD_MODE BUILD_LIB

MODULES=()
for dep in $DEPS; do
    case "$dep" in
        *.pm)
            mod="${dep%.pm}"
            mod="${mod//\//::}"
            MODULES+=("$mod")
            ;;
    esac
done

for sdl_mod in SDL SDL::App SDL::Surface SDL::Video SDL::Mixer SDL::Rect SDL::Event SDL::Image SDL::TTF SDL::GFX SDL::Pango; do
    if "$PERL_BIN" -M"$sdl_mod" -e 1 >/dev/null 2>&1; then
        MODULES+=("$sdl_mod")
    fi
done

MODULES=($(echo "${MODULES[@]}" | tr ' ' '\n' | sort -u))
echo " → Found ${#MODULES[@]} modules"

# ────────────────────── 7. FINAL PP WITH ALL -M ──────────────────────
echo "[7/10] Bundling executable..."
cd "$HOME"
export BUILD_MODE=1
ARGS_FILE="/tmp/pp_arguments.args"
rm -f "$ARGS_FILE"
echo "--gui" >> "$ARGS_FILE"
echo "--clean" >> "$ARGS_FILE"
echo "--cachedeps" >> "$ARGS_FILE"
echo "--verbose" >> "$ARGS_FILE"
echo "-I" >> "$ARGS_FILE"; echo "$APP_DIR/usr/bin/lib" >> "$ARGS_FILE"
echo "-I" >> "$ARGS_FILE"; echo "$APP_DIR/usr/share/perl5" >> "$ARGS_FILE"
echo "-I" >> "$ARGS_FILE"; echo "$HOME/perl-install/lib/site_perl/${PERL_VERSION}" >> "$ARGS_FILE"
echo "--link" >> "$ARGS_FILE"; echo "$LIBPERL_SO" >> "$ARGS_FILE"

for m in "${MODULES[@]}"; do
    if "$PERL_BIN" -M"$m" -e 1 >/dev/null 2>&1; then
        echo "-M" >> "$ARGS_FILE"
        echo "$m" >> "$ARGS_FILE"
    else
        echo " → WARNING: Module '$m' cannot be loaded in Perl 5.38; skipped to avoid pp crash.."
    fi
done

PP_BIN="$HOME/perl-install/bin/pp"
BUILD_MODE=1 "$PP_BIN" -o "$EXECUTABLE" @"$ARGS_FILE" "$WRAPPED_SCRIPT"
unset BUILD_MODE
chmod +x "$EXECUTABLE"
rm -f "$ARGS_FILE"
rm -rf "$APP_DIR/usr/bin/lib"

# ────────────────────── 8. COPYING LIBS AND PERL MODULES ──────────────────────
echo "[8/10] Copying SDL libs, icon and Perl 5.38 modules..."
mkdir -p "$APP_DIR/usr/lib"
LIBS_BASE=(
libSDL-1.2 libSDL_mixer-1.2 libSDL_image-1.2 libSDL_ttf-2.0 libSDL_gfx libSDL_Pango
libmikmod libflac libfluidsynth libmad libvorbisfile libvorbis libogg libFLAC
libpango-1.0 libpangocairo-1.0 libpangoft2-1.0 libcairo libglib-2.0 libgio-2.0
libgmodule-2.0 libgobject-2.0 libffi libfreetype libfontconfig libharfbuzz
libpng16 libjpeg libtiff libsmpeg libthai libdatrie libpixman-1
libxcb-shm libxcb-render libxcb libXrender libX11 libXext libLerc
libdeflate libselinux libpcre2-8 libz libbz2 liblzma libbrotlienc libbrotlidec libxml2
libapparmor libasyncns libbrotlicommon libbsd libdb-5.3 libgcrypt libgomp libgpg-error
libinstpatch-1.0 libjack libjbig libmd libmp3lame libmpg123 libopenal libopus
libpipewire-0.3 libpulse-simple libpulse libpulsecommon* libsharpyuv libsndfile libsndio libsystemd libwebp
)
for lib in "${LIBS_BASE[@]}"; do
    cp -L /usr/lib/x86_64-linux-gnu/"${lib}".so* "$APP_DIR/usr/lib/" 2>/dev/null || true
    cp -L /lib/x86_64-linux-gnu/"${lib}".so* "$APP_DIR/usr/lib/" 2>/dev/null || true
done

if [ -f "$ICON_SRC" ]; then
    mkdir -p "$APP_DIR/usr/share/icons/hicolor/64x64/apps"
    cp "$ICON_SRC" "$APP_DIR/usr/share/icons/hicolor/64x64/apps/frozen-bubble.png"
    cp "$ICON_SRC" "$APP_DIR/frozen-bubble.png"
    cp "$ICON_SRC" "$APP_DIR/.DirIcon"
fi

SITE_BASE="$HOME/perl-install/lib/site_perl/${PERL_VERSION}"
PERL_FALLBACK_BASE="$APP_DIR/usr/lib/perl5/site_perl/${PERL_VERSION}"
mkdir -p "$PERL_FALLBACK_BASE/$ARCHNAME/auto"

[ -f "$SITE_BASE/SDL.pm" ] && cp "$SITE_BASE/SDL.pm" "$PERL_FALLBACK_BASE/"
[ -d "$SITE_BASE/SDL" ] && cp -r "$SITE_BASE/SDL" "$PERL_FALLBACK_BASE/"
[ -d "$SITE_BASE/Games" ] && cp -r "$SITE_BASE/Games" "$PERL_FALLBACK_BASE/"
[ -d "$SITE_BASE/$ARCHNAME/auto/SDL" ] && cp -r "$SITE_BASE/$ARCHNAME/auto/SDL" "$PERL_FALLBACK_BASE/$ARCHNAME/auto/"
[ -d "$SITE_BASE/$ARCHNAME/auto/Games" ] && cp -r "$SITE_BASE/$ARCHNAME/auto/Games" "$PERL_FALLBACK_BASE/$ARCHNAME/auto/"

CSTUFF_538=$(find "$HOME/perl-install/lib/site_perl/5.38.2/x86_64-linux/" -name "CStuff.so" 2>/dev/null | head -n 1)
if [ -n "$CSTUFF_538" ] && [ -f "$CSTUFF_538" ]; then
    DEST_DIR="$APP_DIR/usr/lib/perl5/site_perl/5.38.2/x86_64-linux/auto/Games/FrozenBubble/CStuff"
    
    if [ -d "$APP_DIR" ] && [ ! -w "$APP_DIR/usr/lib" ]; then
        echo " → Permission blockage detected. Attempting to repair..."
        sudo chown -R "$USER:$USER" "$APP_DIR" 2>/dev/null || true
    fi

    mkdir -p "$DEST_DIR"

    install -m 755 "$CSTUFF_538" "$DEST_DIR/CStuff.so"
    echo " → Native CStuff.so 5.38 successfully injected!"
else
    echo " → WARNING: CStuff.so not found."
fi

# ────────────────────── 9. APPRUN & BUILD ──────────────────────
echo "[9/10] Creating AppRun..."
cat > "$LAUNCHER_SCRIPT" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export APPDIR="${HERE}"
export DATA_DIR="${HERE}/usr/share/games/frozen-bubble"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"

PERL_BASE="${HERE}/usr/lib/perl5/site_perl"
if [ -d "${PERL_BASE}" ]; then
    for ver_dir in "${PERL_BASE}"/*; do
        [ -d "${ver_dir}" ] || continue
        export PERL5LIB="${ver_dir}:${PERL5LIB:-}"
        for arch_dir in "${ver_dir}"/*; do
            [ -d "${arch_dir}" ] && export PERL5LIB="${arch_dir}:${PERL5LIB:-}"
        done
    done
fi
[ -d "${HERE}/usr/share/perl5" ] && export PERL5LIB="${HERE}/usr/share/perl5:${PERL5LIB:-}"

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
ln -sf "usr/share/applications/$APP_NAME.desktop" "$APP_DIR/$APP_NAME.desktop"

TOOL="$HOME/appimagetool-x86_64.AppImage"
if [ ! -f "$TOOL" ]; then
    wget -qO "$TOOL" "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
fi
chmod +x "$TOOL"
export ARCH=x86_64
"$TOOL" --no-appstream "$APP_DIR" "$OUTPUT_APPIMAGE"

echo "=================================================="
echo "SUCCESS! AppImage created: $OUTPUT_APPIMAGE"
echo "=================================================="
