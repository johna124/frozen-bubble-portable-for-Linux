#!/usr/bin/env bash
set -e

sanitize_appdir() {
    local target="$1"

    echo " → Sanitizing metadata in: $target"

    chmod -R u+rwX "$target" 2>/dev/null || true

    find "$target" \
        \( \
            -name '.packlist' \
            -o -name '.meta' \
            -o -name 'META.yml' \
            -o -name 'META.json' \
            -o -name 'MYMETA.yml' \
            -o -name 'MYMETA.json' \
            -o -name 'perllocal.pod' \
            -o -name 'Config_heavy.pl' \
            -o -name '*.bs' \
            -o -name 'install.json' \
            -o -name 'fb-server' \
            -o -name 'frozen-bubble-editor' \
        \) \
        -exec rm -rf {} + 2>/dev/null || true

    rm -f \
        "$target/META.yml" \
        "$target/META.json" \
        "$target/usr/bin/META.yml" \
        "$target/usr/bin/META.json" \
        2>/dev/null || true

    find "$target" -type f \
        \( \
            -name '*.yml' \
            -o -name '*.yaml' \
            -o -name '*.json' \
            -o -name '*.pod' \
            -o -name '*.pm' \
            -o -name '*.pl' \
            -o -name 'AppRun' \
            -o -name '*.desktop' \
        \) \
        -exec sed -i -E \
            -e "s|$HOME|/build|g" \
            -e "s|/home/mint|/build|g" \
            {} + 2>/dev/null || true

    find "$target" -type d -empty -delete 2>/dev/null || true

    echo " → Verifying remaining metadata..."
    if find "$target" \
        \( \
            -name '.packlist' \
            -o -name '.meta' \
            -o -name 'META.yml' \
            -o -name 'META.json' \
            -o -name 'MYMETA.yml' \
            -o -name 'MYMETA.json' \
            -o -name 'perllocal.pod' \
            -o -name 'Config_heavy.pl' \
        \) -print 2>/dev/null | grep -q .; then
        echo "   → WARNING: metadata still remains."
    else
        echo "   → Metadata cleaned."
    fi
}

echo "=== Frozen Bubble → SUPREME 100% STANDALONE (v73) ==="

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────

safe_rm() {
    local target="$1"
    [ -e "$target" ] || return 0

    if ! rm -rf "$target" 2>/dev/null; then
        echo " → Fixing permissions on: $target"
        sudo chown -R "$(id -un):$(id -gn)" "$target" 2>/dev/null || true
        chmod -R u+rwX "$target" 2>/dev/null || true
        rm -rf "$target"
    fi
}

can_load_module() {
    local mod="$1"
    "$PERL_BIN" -MModule::Load -e "load '$mod'; 1" >/dev/null 2>&1
}

module_file_exists() {
    local mod="$1"
    local rel="${mod//:://}.pm"

    [ -f "$SITE_BASE/$rel" ] && return 0
    [ -f "$SITE_BASE/$ARCHNAME/$rel" ] && return 0

    return 1
}

add_module() {
    local mod="$1"
    [ -z "$mod" ] && return 0

    if [ -z "${MODSEEN[$mod]:-}" ]; then
        MODSEEN["$mod"]=1
        MODULES+=("$mod")
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# PREREQUISITES
# ──────────────────────────────────────────────────────────────────────────────

echo "[1/10] Installing system prerequisites..."

sudo apt install -y \
    build-essential \
    bzip2 \
    libbz2-dev \
    pkg-config \
    wget \
    curl \
    file \
    libsdl1.2-dev \
    libsdl-image1.2-dev \
    libsdl-mixer1.2-dev \
    libsdl-ttf2.0-dev \
    libsdl-gfx1.2-dev \
    libsdl-pango-dev \
    frozen-bubble \
    frozen-bubble-data \
    libsdl-perl

# ──────────────────────────────────────────────────────────────────────────────
# CONFIG
# ──────────────────────────────────────────────────────────────────────────────

APP_NAME="FrozenBubble"

BUILD_ROOT="/tmp/frozenbubble-appimage-build"

APP_DIR="$BUILD_ROOT/$APP_NAME.AppDir"
OUTPUT_APPIMAGE="$HOME/${APP_NAME}-SUPREME-x86_64.AppImage"

PERL_VERSION="5.38.2"
PERL_PREFIX="$BUILD_ROOT/perl-install"
PERL_BUILD_DIR="$BUILD_ROOT/perl-build"
CPAN_BUILD_DIR="$BUILD_ROOT/cpan-build"

ICON_SRC="/usr/share/icons/hicolor/64x64/apps/frozen-bubble.png"
LAUNCHER_SCRIPT="$APP_DIR/AppRun"
EXECUTABLE="$APP_DIR/usr/bin/frozen-bubble"
LIBPERL_SO="$APP_DIR/usr/lib/libperl.so"

WRAPPED_SCRIPT="$BUILD_ROOT/frozen-bubble-supreme-wrapped.pl"
CLEAN_BODY="$BUILD_ROOT/clean_body.pl"
SCAN_WRAPPER="$BUILD_ROOT/scan_wrapper.pl"
SOURCE_PATCHER="$BUILD_ROOT/patch_frozen_source.pl"
ARGS_FILE="$BUILD_ROOT/pp_arguments.args"

BUNDLE_DATA_DIR="$APP_DIR/usr/share/games/frozen-bubble"

BUILD_USER="appimage-builder"
BUILD_HOST="localhost"

# ──────────────────────────────────────────────────────────────────────────────
# AUTO-DETECT ORIGINAL SCRIPT AND DATA
# ──────────────────────────────────────────────────────────────────────────────

ORIGINAL_SCRIPT="$(command -v frozen-bubble || echo "")"
if [ -z "$ORIGINAL_SCRIPT" ]; then
    echo "ERROR: frozen-bubble executable not found."
    echo "Install it first: sudo apt install frozen-bubble"
    exit 1
fi

ORIGINAL_SCRIPT="$(readlink -f "$ORIGINAL_SCRIPT")"
echo "Original frozen-bubble script: $ORIGINAL_SCRIPT"

DATA_DIR=""
for possible in \
    "/usr/share/games/frozen-bubble" \
    "/usr/share/frozen-bubble" \
    "/usr/games/frozen-bubble"
do
    if [ -d "$possible" ]; then
        DATA_DIR="$possible"
        echo "Found data dir: $DATA_DIR"
        break
    fi
done

if [ -z "$DATA_DIR" ]; then
    echo "ERROR: Frozen Bubble data dir missing."
    echo "Tried:"
    echo "  /usr/share/games/frozen-bubble"
    echo "  /usr/share/frozen-bubble"
    echo "  /usr/games/frozen-bubble"
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# CLEAN
# ──────────────────────────────────────────────────────────────────────────────

echo "[2/10] Cleaning previous build artifacts..."

safe_rm "$BUILD_ROOT"
safe_rm "$OUTPUT_APPIMAGE"

safe_rm "$HOME/FrozenBubble.AppDir"
safe_rm "$HOME/perl-install"
safe_rm "$HOME/perl-build"
safe_rm "$HOME/.cpan"
safe_rm "/tmp/frozen-bubble-supreme-wrapped.pl"
safe_rm "/tmp/clean_body.pl"
safe_rm "/tmp/scan_wrapper.pl"
safe_rm "/tmp/pp_arguments.args"

mkdir -p \
    "$BUILD_ROOT" \
    "$APP_DIR" \
    "$APP_DIR/usr/bin" \
    "$APP_DIR/usr/lib" \
    "$BUNDLE_DATA_DIR" \
    "$CPAN_BUILD_DIR"

# ──────────────────────────────────────────────────────────────────────────────
# BUILD PRIVATE PERL
# ──────────────────────────────────────────────────────────────────────────────

echo "[3/10] Building private shared Perl ${PERL_VERSION}..."

mkdir -p "$PERL_BUILD_DIR"
cd "$PERL_BUILD_DIR"

wget -qO- "https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz" | tar xz
cd "perl-${PERL_VERSION}"

sh Configure \
    -des \
    -Dprefix="$PERL_PREFIX" \
    -Dccflags="-fPIC -O2" \
    -Duseshrplib=true \
    -Dman1dir=none \
    -Dman3dir=none \
    -Dcf_by="$BUILD_USER" \
    -Dcf_email="builder@localhost" \
    -Dperladmin="builder@localhost" \
    -Dmyhostname="$BUILD_HOST" \
    -Dmyuname="linux generic" \
    -Dosname=linux

make -j"$(nproc)"
make install

PERL_BIN="$PERL_PREFIX/bin/perl"
export PATH="$PERL_PREFIX/bin:$PATH"
hash -r

ARCHNAME="$("$PERL_BIN" -e 'use Config; print $Config{archname}')"
SITE_BASE="$PERL_PREFIX/lib/site_perl/$PERL_VERSION"

echo "Private Perl: $PERL_BIN"
echo "Architecture: $ARCHNAME"

# ──────────────────────────────────────────────────────────────────────────────
# SANITIZE PERL CONFIG FILES
# ──────────────────────────────────────────────────────────────────────────────

echo " → Sanitizing Perl Config files..."

HOST_NODE="$(uname -n 2>/dev/null || echo localhost)"

find "$PERL_PREFIX" \
    \( -name Config_heavy.pl -o -name Config.pm \) \
    -type f \
    -exec sed -i -E \
        -e "s|$HOME|/build|g" \
        -e "s|mint|builder|g" \
        -e "s|$HOST_NODE|localhost|g" \
        -e "s/^## Configured by.*/## Configured by     : builder/" \
        -e "s/^## Target system.*/## Target system     : linux generic/" \
        {} + 2>/dev/null || true

# ──────────────────────────────────────────────────────────────────────────────
# COPY libperl.so
# ──────────────────────────────────────────────────────────────────────────────

echo "[4/10] Embedding libperl.so..."

CUSTOM_LIBPERL="$PERL_PREFIX/lib/${PERL_VERSION}/${ARCHNAME}/CORE/libperl.so"

if [ -f "$CUSTOM_LIBPERL" ]; then
    echo " → Using custom Perl libperl.so"
    cp -L "$CUSTOM_LIBPERL" "$LIBPERL_SO"
else
    echo " → Custom libperl.so not found, trying fallback..."

    SYSTEM_FALLBACK_FILE="$(find /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu -name 'libperl.so*' 2>/dev/null | head -n 1 || true)"

    if [ -n "$SYSTEM_FALLBACK_FILE" ] && [ -e "$SYSTEM_FALLBACK_FILE" ]; then
        echo " → Using system libperl fallback: $SYSTEM_FALLBACK_FILE"
        cp -L "$SYSTEM_FALLBACK_FILE" "$LIBPERL_SO"
    else
        echo " → WARNING: No libperl.so found. Creating placeholder."
        touch "$LIBPERL_SO"
    fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL CPAN TOOLING
# ──────────────────────────────────────────────────────────────────────────────

echo "[5/10] Installing cpanm and packaging tools..."

export PERL_MM_USE_DEFAULT=1
export PERL_EXTUTILS_AUTOINSTALL="--defaultdeps"

curl -L https://cpanmin.us | "$PERL_BIN" - --notest App::cpanminus

CPANM="$PERL_PREFIX/bin/cpanm"

"$CPANM" --notest Module::ScanDeps
"$CPANM" --notest Compress::Bzip2
"$CPANM" --notest PAR::Packer
"$CPANM" --notest Encode::Locale

echo " → Installing Alien::SDL hidden build dependencies..."

"$CPANM" --notest \
    File::Which \
    File::ShareDir \
    File::Fetch \
    Archive::Extract \
    Archive::Tar \
    Archive::Zip \
    Text::Patch \
    Capture::Tiny \
    Module::Build \
    Digest::SHA \
    ExtUtils::CBuilder \
    File::Path \
    File::Temp \
    File::Spec \
    File::Find

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL Alien::SDL WITH --travis BYPASS
# ──────────────────────────────────────────────────────────────────────────────

echo " → Installing Alien::SDL with --travis bypass..."

cd "$CPAN_BUILD_DIR"
safe_rm "$CPAN_BUILD_DIR/Alien-SDL-1.446"
safe_rm "$CPAN_BUILD_DIR/Alien-SDL-1.446.tar.gz"

wget -q http://www.cpan.org/authors/id/F/FR/FROGGS/Alien-SDL-1.446.tar.gz
tar xzf Alien-SDL-1.446.tar.gz
cd Alien-SDL-1.446

"$PERL_BIN" Build.PL --travis
"$PERL_BIN" ./Build
"$PERL_BIN" ./Build install

cd "$CPAN_BUILD_DIR"
rm -rf Alien-SDL-1.446 Alien-SDL-1.446.tar.gz

if ! "$PERL_BIN" -MAlien::SDL -e 1 >/dev/null 2>&1; then
    echo "FATAL: Alien::SDL could not be installed."
    exit 1
fi

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL SDL + Games::FrozenBubble
# ──────────────────────────────────────────────────────────────────────────────

echo " → Installing SDL..."
"$CPANM" --notest SDL || "$CPANM" --notest --force SDL

if ! "$PERL_BIN" -MSDL -e 1 >/dev/null 2>&1; then
    echo "FATAL: SDL could not be installed/loaded from private Perl."
    exit 1
fi

echo " → Installing Games::FrozenBubble from CPAN (builds CStuff.so for 5.38)..."
"$CPANM" --notest Games::FrozenBubble || true


# Remove unnecessary CPAN game launchers from private Perl bin.
# We use our own pp executable inside the AppImage.
echo " → Removing unnecessary CPAN game launchers..."
rm -f \
    "$PERL_PREFIX/bin/fb-server" \
    "$PERL_PREFIX/bin/frozen-bubble" \
    "$PERL_PREFIX/bin/frozen-bubble-editor"

echo " → Making private Perl installation writable..."
chmod -R u+rwX "$PERL_PREFIX" 2>/dev/null || true

# If there is a duplicate arch-specific FrozenBubble.pm while a normal one exists,
# remove the duplicate.
if [ -f "$SITE_BASE/Games/FrozenBubble.pm" ] && \
   [ -f "$SITE_BASE/$ARCHNAME/Games/FrozenBubble.pm" ]; then
    echo " → Removing duplicate arch-specific Games/FrozenBubble.pm"
    rm -f "$SITE_BASE/$ARCHNAME/Games/FrozenBubble.pm"
fi

# Remove CPAN share data to avoid duplicating ~29 MB inside pp.
echo " → Removing CPAN Games-FrozenBubble share data to avoid duplication..."
find "$SITE_BASE" \
    -type d \
    -path '*/auto/share/dist/Games-FrozenBubble' \
    -exec rm -rf {} + 2>/dev/null || true

# Remove metadata noise before pp.
echo " → Removing CPAN metadata noise..."
find "$PERL_PREFIX" -type f -name .packlist -delete 2>/dev/null || true
find "$PERL_PREFIX" -type d -name .meta -exec rm -rf {} + 2>/dev/null || true
find "$PERL_PREFIX" -type f -name perllocal.pod -delete 2>/dev/null || true
find "$PERL_PREFIX" -type f -name '*.bs' -delete 2>/dev/null || true

# ──────────────────────────────────────────────────────────────────────────────
# PATCH Config.pm INSIDE PRIVATE PERL
# ──────────────────────────────────────────────────────────────────────────────

echo " → Ensuring private Perl site_perl is writable..."
chmod -R u+rwX "$SITE_BASE" 2>/dev/null || true

echo " → Patching private Games::FrozenBubble::Config..."

FB_CONFIG="$(find "$SITE_BASE" -path '*/Games/FrozenBubble/Config.pm' 2>/dev/null | head -n1)"

if [ -n "$FB_CONFIG" ]; then
    if ! grep -q "AppImage portable override" "$FB_CONFIG"; then

        # Si CPAN dejó el archivo read-only, lo hacemos writable.
        if [ ! -w "$FB_CONFIG" ]; then
            echo "   → Config.pm is read-only, fixing permissions..."
            chmod u+w "$FB_CONFIG" 2>/dev/null || true
        fi

        # Si todavía no se puede escribir, probablemente haya restos root.
        if [ ! -w "$FB_CONFIG" ]; then
            echo ""
            echo "FATAL: Cannot write to:"
            echo "  $FB_CONFIG"
            echo ""
            echo "This is probably caused by old root-owned files."
            echo "Run this once and restart the script:"
            echo ""
            echo "  sudo rm -rf $BUILD_ROOT"
            echo ""
            exit 1
        fi

        cat >> "$FB_CONFIG" <<'CONFIGEOF'

# AppImage portable override
{
    no strict;
    no warnings;

    if ($ENV{DATA_DIR}) {
        $FPATH  = $ENV{DATA_DIR};
        $FLPATH = $ENV{DATA_DIR};

        $Games::FrozenBubble::Config::FPATH  = $ENV{DATA_DIR};
        $Games::FrozenBubble::Config::FLPATH = $ENV{DATA_DIR};

        $fb_config::FPATH  = $ENV{DATA_DIR};
        $fb_config::FLPATH = $ENV{DATA_DIR};
    }
}
1;
CONFIGEOF

        echo "   → Patched: $FB_CONFIG"
    else
        echo "   → Config.pm already patched"
    fi
else
    echo "   → WARNING: Games/FrozenBubble/Config.pm not found in private Perl."
fi




if [ -n "$FB_CONFIG" ]; then
    if ! grep -q "AppImage portable override" "$FB_CONFIG"; then
        cat >> "$FB_CONFIG" <<'CONFIGEOF'

# AppImage portable override
{
    no strict;
    no warnings;

    if ($ENV{DATA_DIR}) {
        $FPATH  = $ENV{DATA_DIR};
        $FLPATH = $ENV{DATA_DIR};

        $Games::FrozenBubble::Config::FPATH  = $ENV{DATA_DIR};
        $Games::FrozenBubble::Config::FLPATH = $ENV{DATA_DIR};

        $fb_config::FPATH  = $ENV{DATA_DIR};
        $fb_config::FLPATH = $ENV{DATA_DIR};
    }
}
1;
CONFIGEOF
        echo "   → Patched: $FB_CONFIG"
    fi
else
    echo "   → WARNING: Games/FrozenBubble/Config.pm not found in private Perl."
fi

# ──────────────────────────────────────────────────────────────────────────────
# COPY GAME DATA
# ──────────────────────────────────────────────────────────────────────────────

echo "[6/10] Copying game data..."
cp -r "$DATA_DIR"/* "$BUNDLE_DATA_DIR/"

# ──────────────────────────────────────────────────────────────────────────────
# CREATE SOURCE PATCHER
# ──────────────────────────────────────────────────────────────────────────────

echo "[7/10] Creating robust source patcher..."

cat > "$SOURCE_PATCHER" <<'EOF'
use strict;
use warnings;

local $/;
my $t = <STDIN>;

# Remove original shebang
$t =~ s/^#!.*\n//;

# Replace prefix/data_dir assignments
$t =~ s{^\s*(?:my|our|local)?\s*\$prefix\s*=.*$}
       {\$prefix = \$appdir . "/usr";}gm;

$t =~ s{^\s*(?:my|our|local)?\s*\$data_dir\s*=.*$}
       {\$data_dir = \$ENV{DATA_DIR} || \$appdir . "/usr/share/games/frozen-bubble";}gm;

# Remove simple chdir duplicate if present
$t =~ s{^\s*chdir\s+\$data_dir\s*;\s*$}
       {# chdir removed (wrapper does it)}gm;

# Replace literal paths, with or without subpaths
$t =~ s{['"]/usr/share/games/frozen-bubble((?:/[^'"]*)?)['"]}
       {"\$data_dir$1"}g;

$t =~ s{['"]/usr/share/frozen-bubble((?:/[^'"]*)?)['"]}
       {"\$data_dir$1"}g;

$t =~ s{['"]/usr/games/frozen-bubble((?:/[^'"]*)?)['"]}
       {"\$data_dir$1"}g;

# Replace $prefix-based paths
$t =~ s{['"]\$prefix/share/games/frozen-bubble((?:/[^'"]*)?)['"]}
       {"\$data_dir$1"}g;

$t =~ s{\$prefix\s*\.\s*['"]/share/games/frozen-bubble((?:/[^'"]*)?)['"]}
       {"\$data_dir$1"}g;

print $t;
EOF

perl "$SOURCE_PATCHER" < "$ORIGINAL_SCRIPT" > "$CLEAN_BODY"

# ──────────────────────────────────────────────────────────────────────────────
# CREATE WRAPPED SCRIPT
# ──────────────────────────────────────────────────────────────────────────────

cat > "$WRAPPED_SCRIPT" <<EOF
#!/usr/bin/perl
use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'redefine';

use FindBin qw(\$RealBin);
use File::Basename;

BEGIN {
    if (my \$ad = \$ENV{APPDIR}) {
        unshift @INC, "\$ad/usr/share/perl5"
            if -d "\$ad/usr/share/perl5";

        unshift @INC, "\$ad/usr/lib/perl5/site_perl/$PERL_VERSION"
            if -d "\$ad/usr/lib/perl5/site_perl/$PERL_VERSION";

        unshift @INC, "\$ad/usr/lib/perl5/site_perl/$PERL_VERSION/$ARCHNAME"
            if -d "\$ad/usr/lib/perl5/site_perl/$PERL_VERSION/$ARCHNAME";
    }

    unshift @INC, split(/:/, \$ENV{BUILD_LIB}) if \$ENV{BUILD_LIB};
}

my \$appdir = \$ENV{APPDIR} || dirname(\$RealBin);
my \$prefix = "\$appdir/usr";
my \$data_dir = \$ENV{DATA_DIR} || "\$appdir/usr/share/games/frozen-bubble";

if (!\$ENV{BUILD_MODE}) {
    if (-d \$data_dir) {
        chdir \$data_dir or die "chdir failed: \$!";
    } else {
        die "Data directory \$data_dir does not exist!";
    }
}
EOF

cat "$CLEAN_BODY" >> "$WRAPPED_SCRIPT"

echo " → Checking wrapped script syntax..."
BUILD_MODE=1 DATA_DIR="$BUNDLE_DATA_DIR" "$PERL_BIN" -c "$WRAPPED_SCRIPT"
echo " → Wrapped script syntax OK"

# ──────────────────────────────────────────────────────────────────────────────
# SCAN DEPENDENCIES
# ──────────────────────────────────────────────────────────────────────────────

echo "[8/10] Scanning dependencies..."

cat > "$SCAN_WRAPPER" <<EOF
@ARGV = ('--help');
do '$WRAPPED_SCRIPT';
EOF

DEPS=$(
    BUILD_MODE=1 \
    SCAN_FILE="$SCAN_WRAPPER" \
    "$PERL_BIN" -MModule::ScanDeps -e \
    'print "$_\n" for keys %{scan_deps(files => [$ENV{SCAN_FILE}], recurse => 1, compile => 1)}' \
    | grep -v '^/' \
    | sort -u \
    | grep -v 'perlmain' \
    || true
)

declare -A MODSEEN=()
MODULES=()

# Convert ScanDeps paths to module names.
for dep in $DEPS; do
    dep="${dep#$ARCHNAME/}"

    case "$dep" in
        *.pm)
            mod="${dep%.pm}"
            mod="${mod//\//::}"
            add_module "$mod"
            ;;
    esac
done

# Add installed SDL modules.
while IFS= read -r pm; do
    pm="${pm#$ARCHNAME/}"

    if [[ "$pm" == "SDL.pm" || "$pm" == SDL/* ]]; then
        mod="${pm%.pm}"
        mod="${mod//\//::}"
        add_module "$mod"
    fi
done < <(find "$SITE_BASE" -type f -name '*.pm' -printf '%P\n' 2>/dev/null | sort -u)

# Add installed Games::FrozenBubble modules.
while IFS= read -r pm; do
    pm="${pm#$ARCHNAME/}"

    if [[ "$pm" == "Games.pm" || "$pm" == Games/* ]]; then
        mod="${pm%.pm}"
        mod="${mod//\//::}"
        add_module "$mod"
    fi
done < <(find "$SITE_BASE" -type f -name '*.pm' -printf '%P\n' 2>/dev/null | sort -u)

# Force critical modules.
FORCE_MODULES=(
    SDL
    SDL::App
    SDL::Surface
    SDL::Video
    SDL::Mixer
    SDL::Rect
    SDL::Event
    SDL::Image
    SDL::TTF
    SDL::GFX
    Compress::Bzip2
    Encode::Locale
    Games::FrozenBubble
    Games::FrozenBubble::Config
    Games::FrozenBubble::Stuff
    Games::FrozenBubble::CStuff
)

for mod in "${FORCE_MODULES[@]}"; do
    add_module "$mod"
done

echo " → Found ${#MODULES[@]} candidate modules"

# ──────────────────────────────────────────────────────────────────────────────
# BUILD pp ARGUMENTS
# ──────────────────────────────────────────────────────────────────────────────

echo "[9/10] Bundling executable with pp..."

PP_BIN="$PERL_PREFIX/bin/pp"

rm -f "$ARGS_FILE"

{
    echo "--gui"
    echo "--clean"
    echo "--cachedeps"
    echo "--verbose"
} >> "$ARGS_FILE"

# Include private Perl paths first.
for inc in \
    "$APP_DIR/usr/lib/perl5/site_perl/$PERL_VERSION/$ARCHNAME" \
    "$APP_DIR/usr/lib/perl5/site_perl/$PERL_VERSION" \
    "$APP_DIR/usr/share/perl5" \
    "$SITE_BASE/$ARCHNAME" \
    "$SITE_BASE"
do
    if [ -d "$inc" ]; then
        echo "-I" >> "$ARGS_FILE"
        echo "$inc" >> "$ARGS_FILE"
    fi
done

echo "--link" >> "$ARGS_FILE"
echo "$LIBPERL_SO" >> "$ARGS_FILE"

for mod in "${MODULES[@]}"; do
    if can_load_module "$mod"; then
        echo "-M" >> "$ARGS_FILE"
        echo "$mod" >> "$ARGS_FILE"
    elif [[ "$mod" == Games::FrozenBubble* || "$mod" == SDL* ]] && module_file_exists "$mod"; then
        echo " → WARNING: forcing module file into pp: $mod"
        echo "-M" >> "$ARGS_FILE"
        echo "$mod" >> "$ARGS_FILE"
    else
        echo " → WARNING: Módulo '$mod' no cargable en Perl 5.38, omitido para evitar crash de pp."
    fi
done

BUILD_MODE=1 "$PP_BIN" -o "$EXECUTABLE" @"$ARGS_FILE" "$WRAPPED_SCRIPT"

chmod +x "$EXECUTABLE"
rm -f "$ARGS_FILE"

# ──────────────────────────────────────────────────────────────────────────────
# COPY SDL LIBS AND ICON
# ──────────────────────────────────────────────────────────────────────────────

echo "[10/10] Copying SDL libraries, icon and sanitizing..."

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

# ──────────────────────────────────────────────────────────────────────────────
# APPDIR SANITIZATION BEFORE APPIMAGE
# ──────────────────────────────────────────────────────────────────────────────

echo " → Sanitizing AppDir..."

# Specifically requested cleanup.
rm -rf "$APP_DIR/usr/lib/perl5/site_perl/$PERL_VERSION/$ARCHNAME/auto/Games/FrozenBubble/.packlist" 2>/dev/null || true

# General cleanup.
find "$APP_DIR" -type f -name .packlist -delete 2>/dev/null || true
find "$APP_DIR" -type d -name .meta -exec rm -rf {} + 2>/dev/null || true
find "$APP_DIR" -type f -name perllocal.pod -delete 2>/dev/null || true
find "$APP_DIR" -type f -name '*.bs' -delete 2>/dev/null || true
find "$APP_DIR" -type f -name Config_heavy.pl -delete 2>/dev/null || true

# Remove unnecessary CPAN game utilities if they somehow ended up in AppDir.
find "$APP_DIR" -type f \( -name fb-server -o -name frozen-bubble-editor \) -delete 2>/dev/null || true

# Remove empty directories.
find "$APP_DIR" -type d -empty -delete 2>/dev/null || true

# ──────────────────────────────────────────────────────────────────────────────
# APPRUN
# ──────────────────────────────────────────────────────────────────────────────

cat > "$LAUNCHER_SCRIPT" <<'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"

export APPDIR="${HERE}"
export DATA_DIR="${HERE}/usr/share/games/frozen-bubble"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"

CONFIG_DIR="$HOME/.local/share/frozen-bubble"
mkdir -p "$CONFIG_DIR"

cp -n "${HERE}/usr/share/games/frozen-bubble/scores" "$CONFIG_DIR/" 2>/dev/null || true

exec "${HERE}/usr/bin/frozen-bubble" "$@"
EOF

chmod +x "$LAUNCHER_SCRIPT"

# ──────────────────────────────────────────────────────────────────────────────
# DESKTOP FILE
# ──────────────────────────────────────────────────────────────────────────────

mkdir -p "$APP_DIR/usr/share/applications"

cat > "$APP_DIR/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=Frozen Bubble
Exec=frozen-bubble
Icon=frozen-bubble
Type=Application
Categories=Game;ArcadeGame;
EOF

ln -sf "usr/share/applications/$APP_NAME.desktop" "$APP_DIR/$APP_NAME.desktop"

# ──────────────────────────────────────────────────────────────────────────────
# BUILD APPIMAGE
# ──────────────────────────────────────────────────────────────────────────────

TOOL="$BUILD_ROOT/appimagetool-x86_64.AppImage"

if [ ! -f "$TOOL" ]; then
    echo " → Downloading appimagetool..."
    wget -qO "$TOOL" "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
fi

chmod +x "$TOOL"

export ARCH=x86_64

# ──────────────────────────────────────────────────────────────────────────────
# SANITIZAR APPDIR ANTES DE APPIMAGE
# ──────────────────────────────────────────────────────────────────────────────
sanitize_appdir "$APP_DIR"

echo " → Compiling AppImage..."
"$TOOL" --no-appstream "$APP_DIR" "$OUTPUT_APPIMAGE"

echo "=================================================="
echo "SUCCESS! AppImage created:"
echo "  $OUTPUT_APPIMAGE"
echo ""
echo "Sanitized build root:"
echo "  $BUILD_ROOT"
echo ""
echo "Optional compression:"
echo "  upx --best --lzma $OUTPUT_APPIMAGE"
echo "=================================================="
