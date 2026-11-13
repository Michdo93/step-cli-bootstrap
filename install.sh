#!/bin/sh
#
# step CLI Bootstrap - installs the smallstep "step" CLI on Debian-based systems and can
# bootstrap the host to a step-ca (root certificate, optional system trust).
# Supports: Debian, Ubuntu, Raspberry Pi OS (32/64 bit, incl. ARMv6), DietPi
#
#   wget -qO- https://raw.githubusercontent.com/Michdo93/step-cli-bootstrap/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/Michdo93/step-cli-bootstrap/main/install.sh | sh
#
# Options (after "sh -s --"):
#   --ca-url URL          bootstrap to this step-ca (e.g. https://ca.lab:9000)
#   --fingerprint FP      SHA-256 fingerprint of the CA's root certificate
#   --trust / --no-trust  add the root certificate to the system trust store
#   --yes                 no questions (defaults or the given options)
#
#   wget -qO- .../install.sh | sh -s -- --ca-url https://ca.lab:9000 --fingerprint 4f3c... --trust --yes
#
# Works with "| sh" and "| bash", as root or as a sudo user. Everything is inside main(),
# which is only called on the last line, so a piped script is read completely first.

set -eu

main() {
    if [ -t 1 ]; then
        RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
    else
        RED=''; GREEN=''; YELLOW=''; NC=''
    fi

    CA_URL="${STEP_CA_URL:-}"
    FINGERPRINT="${STEP_FINGERPRINT:-}"
    TRUST="${STEP_TRUST:-}"
    ASSUME_YES="${ASSUME_DEFAULTS:-0}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --ca-url) CA_URL="${2:-}"; shift 2 ;;
            --ca-url=*) CA_URL="${1#*=}"; shift ;;
            --fingerprint) FINGERPRINT="${2:-}"; shift 2 ;;
            --fingerprint=*) FINGERPRINT="${1#*=}"; shift ;;
            --trust) TRUST=yes; shift ;;
            --no-trust) TRUST=no; shift ;;
            --yes|-y) ASSUME_YES=1; shift ;;
            -h|--help) sed -n '2,20p' "$0" 2>/dev/null || true; exit 0 ;;
            *) error "Unknown option: $1" ;;
        esac
    done
    interactive=0
    if have_tty && [ "$ASSUME_YES" != 1 ]; then interactive=1; fi

    # ---------- privileges ----------
    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
        info "Not running as root - administrative commands use sudo."
        if have_tty; then
            sudo -v </dev/tty || error "sudo authentication failed."
        else
            sudo -n true 2>/dev/null || error "sudo needs a password but no terminal is available."
        fi
    else
        error "This script must be run as root or with sudo privileges."
    fi

    # ---------- OS ----------
    [ -r /etc/os-release ] || error "Cannot detect operating system (/etc/os-release missing)."
    # shellcheck disable=SC1091
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in
        *" debian "*|*" ubuntu "*|*" raspbian "*|*" dietpi "*) ;;
        *) command -v apt-get >/dev/null 2>&1 || error "Unsupported OS '${ID:-unknown}' (apt-get not found)."
           warn "OS '${ID:-unknown}' is not officially tested; continuing because apt-get exists." ;;
    esac
    [ -f /boot/dietpi/.version ] && info "DietPi detected."
    info "Detected OS: ${PRETTY_NAME:-$ID} ($(uname -m))"

    # ---------- install ----------
    if command -v step >/dev/null 2>&1; then
        info "step is already installed: $(step version 2>/dev/null | head -n 1)"
        if [ "$interactive" = 1 ] && [ "$(ask_yes_no "Install/upgrade to the latest version? (yes/no) [Default: yes]: " yes)" = no ]; then
            :
        else
            install_step
        fi
    else
        install_step
    fi
    command -v step >/dev/null 2>&1 || error "step was not found after the installation."
    info "Installed: $(step version 2>/dev/null | head -n 1)"

    # ---------- optional: bootstrap to a step-ca ----------
    if [ -z "$CA_URL" ] && [ "$interactive" = 1 ]; then
        CA_URL=$(ask "step-ca URL to bootstrap to (e.g. https://ca.lab:9000), Enter to skip: " "")
    fi
    if [ -n "$CA_URL" ]; then
        case "$CA_URL" in https://*) ;; *) error "The CA URL must start with https:// ($CA_URL)." ;; esac
        if [ -z "$FINGERPRINT" ] && [ "$interactive" = 1 ]; then
            FINGERPRINT=$(ask "Root certificate fingerprint (step certificate fingerprint root_ca.crt): " "")
        fi
        FINGERPRINT=$(printf '%s' "$FINGERPRINT" | tr -d ' :' | tr 'A-F' 'a-f')
        printf '%s' "$FINGERPRINT" | grep -Eq '^[0-9a-f]{64}$' || error "The fingerprint must be 64 hex characters (SHA-256)."
        bootstrap_ca
    fi
    info "step CLI setup completed successfully!"
}

info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1" >&2; exit 1; }

have_tty() { (exec </dev/tty) 2>/dev/null; }

ask() {  # prompt default
    printf '%s' "$1" >/dev/tty
    IFS= read -r reply </dev/tty || reply=""
    printf '%s' "${reply:-$2}"
}

normalize_yes_no() {
    case "$1" in
        y|Y|yes|Yes|YES) printf yes ;;
        n|N|no|No|NO) printf no ;;
        *) return 1 ;;
    esac
}

ask_yes_no() {  # prompt default
    while :; do
        if normalize_yes_no "$(ask "$1" "$2")"; then return 0; fi
        printf "${YELLOW}[WARN]${NC} Please answer yes, Yes, y or no, No, n.\n" >/dev/tty
    done
}

# Never stop at a "configuration file modified" question (no terminal for dpkg).
apt_get() {
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold "$@" </dev/null
}

download() {  # url file
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
    else wget -qO "$2" "$1"; fi
}

install_step() {
    info "Installing prerequisites (curl, ca-certificates)..."
    apt_get update -qq || error "apt-get update failed."
    apt_get install -y -qq --no-install-recommends curl ca-certificates >/dev/null ||
        error "Installing curl/ca-certificates failed (see the apt output above)."

    # The smallstep repository has amd64, arm64 and armhf (ARMv7) packages. ARMv6
    # (Raspberry Pi 1/Zero) needs the ARMv6 binary, the armhf package would crash there.
    case "$(uname -m)" in
        armv6*) info "ARMv6 detected - installing the ARMv6 binary."; install_tarball armv6; return ;;
    esac

    info "Adding the smallstep apt repository..."
    $SUDO install -d -m 0755 /etc/apt/keyrings
    tmp=$(mktemp)
    if download "${STEP_KEY_URL:-https://packages.smallstep.com/keys/apt/repo-signing-key.gpg}" "$tmp" && [ -s "$tmp" ]; then
        $SUDO install -m 0644 "$tmp" /etc/apt/keyrings/smallstep.asc
        rm -f "$tmp"
        printf 'Types: deb\nURIs: %s\nSuites: debs\nComponents: main\nSigned-By: /etc/apt/keyrings/smallstep.asc\n' \
            "${STEP_REPO_URL:-https://packages.smallstep.com/stable/debian}" | $SUDO tee /etc/apt/sources.list.d/smallstep.sources >/dev/null
        if apt_get update -qq && apt_get install -y -qq step-cli >/dev/null; then
            info "step-cli installed from the smallstep repository (updates come with apt upgrade)."
            return
        fi
        warn "Installation from the smallstep repository failed - falling back to the release binary."
        # a broken repository entry would make every later "apt-get update" fail
        $SUDO rm -f /etc/apt/sources.list.d/smallstep.sources /etc/apt/keyrings/smallstep.asc
        apt_get update -qq || true
    else
        rm -f "$tmp"
        warn "Could not download the repository key - falling back to the release binary."
    fi
    case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
        amd64|x86_64) install_tarball amd64 ;;
        arm64|aarch64) install_tarball arm64 ;;
        armhf|armv7*) install_tarball armv7 ;;
        i386|i686) install_tarball 386 ;;
        *) error "No step binary for architecture $(uname -m)." ;;
    esac
}

install_tarball() {  # arch
    url="${STEP_TARBALL_BASE:-https://dl.smallstep.com/cli/docs-cli-install/latest}/step_linux_$1.tar.gz"
    dir=$(mktemp -d)
    info "Downloading $url..."
    download "$url" "$dir/step.tar.gz" || { rm -rf "$dir"; error "Download of $url failed."; }
    tar -xzf "$dir/step.tar.gz" -C "$dir" || { rm -rf "$dir"; error "Cannot unpack $url."; }
    bin=$(find "$dir" -type f -name step -perm -u+x | head -n 1)
    [ -n "$bin" ] || { rm -rf "$dir"; error "The archive does not contain the step binary."; }
    $SUDO install -m 0755 "$bin" /usr/local/bin/step
    rm -rf "$dir"
    info "step installed to /usr/local/bin/step (re-run this script to update it)."
}

bootstrap_ca() {
    # Runs as the calling user: step keeps its configuration in ~/.step of that user.
    info "Bootstrapping to $CA_URL ..."
    step ca bootstrap --ca-url "$CA_URL" --fingerprint "$FINGERPRINT" --force </dev/null >/dev/null ||
        error "step ca bootstrap failed (check URL, fingerprint, that the CA is reachable and NO_PROXY if a proxy is set)."
    root="$(step path)/certs/root_ca.crt"
    info "Root certificate stored in $root (fingerprint verified)."

    if [ -z "$TRUST" ]; then
        if [ "$interactive" = 1 ]; then
            TRUST=$(ask_yes_no "Add the root certificate to the system trust store? (yes/no) [Default: no]: " no)
        else
            TRUST=no
        fi
    fi
    if [ "$TRUST" = yes ]; then
        name=$(printf '%s' "$CA_URL" | sed -e 's#https://##' -e 's#[^A-Za-z0-9.-]#_#g')
        $SUDO install -m 0644 "$root" "/usr/local/share/ca-certificates/step-ca-$name.crt"
        $SUDO update-ca-certificates >/dev/null 2>&1 || warn "update-ca-certificates failed."
        info "Root certificate added to the system trust store."
    fi
}

main "$@"
