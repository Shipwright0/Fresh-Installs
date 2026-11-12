#!/usr/bin/env bash
#
# debinstaller_bspwm.v3.sh - provision a bspwm desktop on Debian from a
# minimal (netinst) install.
#
# Debian port of voidinstaller_bspwm.v2.sh. The package-by-package mapping,
# including the packages that have no Debian equivalent, is documented in
# debinstaller_bspwm.v3-report.md.
#
# Steps:
#   1. Optionally migrate to Debian testing/unstable, update, install packages
#   2. Install the Iosevka Nerd Font from the upstream release
#   3. Build and install lemonbar-xft from source
#   4. Configure yubikey support
#   5. Install pyenv
#   6. Set executable bits, switch shell, stow dotfiles, run themer
#   7. Optionally delete this repository
#
# Usage:
#   ./debinstaller_bspwm.sh [options]
#
#   -y, --yes          answer "yes" to every confirmation prompt
#       --no-pyenv     skip the pyenv installer
#       --remove-self  delete ~/Fresh-Installs at the end (destructive)
#   -h, --help         show this help
#
# The Debian suite (stable, testing or unstable) is chosen interactively during
# the install unless TARGET_SUITE is set in the environment.
#
# Exit codes: 0 = success, 1 = error, 2 = bad usage, 130 = interrupted.

# ---------------------------------------------------------------------------
# Safety and hygiene
# ---------------------------------------------------------------------------

# Abort on errors, undefined variables, and failed pipeline stages.
set -Eeuo pipefail

# Use predictable word splitting.
IFS=$'\n\t'

# Use predictable file permissions.
umask 022

# Refuse to run as root; privileged steps use sudo individually.
if [[ ${EUID} -eq 0 ]]; then
  printf 'debinstaller_bspwm.v3.sh: error: do not run this as root; run it as\n' >&2
  printf 'your normal user, the script calls sudo for the privileged steps.\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Configuration - every value can be overridden from the environment
# ---------------------------------------------------------------------------

SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

ASSUME_YES="${ASSUME_YES:-false}"
INSTALL_PYENV="${INSTALL_PYENV:-true}"
REMOVE_SELF="${REMOVE_SELF:-false}"

# Debian suite to provision: stable, testing, or unstable (sid). When empty,
# the script prompts for a choice during step 1. Set TARGET_SUITE to skip the
# prompt, for example in unattended runs.
TARGET_SUITE="${TARGET_SUITE:-}"

# Official mirrors used when replacing the apt sources during a suite
# migration. Override these to use a local or country mirror.
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://deb.debian.org/debian}"
DEBIAN_SECURITY_MIRROR="${DEBIAN_SECURITY_MIRROR:-http://security.debian.org/debian-security}"

# Set to true when the script changed the apt sources to testing or unstable.
REBOOT_REQUIRED="${REBOOT_REQUIRED:-false}"

readonly SCRIPT_NAME SCRIPT_DIR
# ASSUME_YES, INSTALL_PYENV, REMOVE_SELF, TARGET_SUITE and REBOOT_REQUIRED are
# deliberately not readonly: the argument parser, the suite prompt and the
# suite migration update them.

readonly HOME_DIR="${HOME}"
readonly DOTFILES_DIR="${HOME_DIR}/dotfiles"
readonly SCRIPTS_DIR="${HOME_DIR}/scripts/gitscripts"
readonly BASESCRIPTS_DIR="${HOME_DIR}/scripts"
readonly SYSCOMPS_DIR="${HOME_DIR}/syscomps"
readonly CURRENT_USER="$(id -un)"

# Path to the themer script.
readonly THEMER="${SCRIPTS_DIR}/theming/theme_changer"

# Iosevka Nerd Font is installed from the upstream release archive instead of a
# Debian package so the patched Nerd Font variants are available.
readonly IOSEVKA_FONT_URL="${IOSEVKA_FONT_URL:-https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/Iosevka.zip}"
readonly IOSEVKA_FONT_DIR="${HOME_DIR}/.local/share/fonts/iosevka-nerd-font"

# lemonbar-xft is built from source because the Debian lemonbar package lacks
# Xft support, which the panel needs for fontconfig and Nerd Font rendering.
readonly LEMONBAR_REPO="${LEMONBAR_REPO:-https://github.com/abatalev/lemonbar-xft.git}"
readonly LEMONBAR_BRANCH="${LEMONBAR_BRANCH:-xft-port}"
readonly LEMONBAR_SRC_DIR="${LEMONBAR_SRC_DIR:-${HOME_DIR}/.local/src/lemonbar-xft}"
# Install under /usr/local so the locally built bar does not overwrite the
# dpkg-owned /usr/bin/lemonbar if the distro package is still present.
readonly LEMONBAR_PREFIX="${LEMONBAR_PREFIX:-/usr/local}"

# Packages installed from the Debian repositories.
#
readonly -a PACKAGES=(
  # X11, window manager and desktop utilities.
  xorg
  x11-utils
  x11-xserver-utils
  rxvt-unicode
  dmenu
  hsetroot
  xdotool
  xclip
  dunst
  libnotify-bin
  picom
  firefox-esr
  bspwm
  sxhkd
  unclutter
  redshift
  flameshot
  trash-cli
  rsync
  nfs-common
  cifs-utils

  # shell, build and general-purpose tools.
  zsh
  stow
  vim
  htop
  build-essential
  git
  curl
  ca-certificates
  unzip
  imagemagick
  yt-dlp
  mpv
  ranger
  neovim
  ncmpcpp
  mopidy
  tmux
  remina
  fzf
  tree-sitter-cli

  # Fonts, browsers, document and media applications.
  fonts-jetbrains-mono
  fontconfig
  flatpak
  podman
  python3-pip
  syncthing
  zathura
  surf
  libreoffice
  newsboat
  hugo
  w3m-img
  sxiv

  # Dependencies used by the bspwm panel and themer scripts.
  xdo
  bc
  pamixer

  # Yubikey/FIDO2 support. pcscd is needed for the smartcard service.
  libfido2-1
  fido2-tools
  libu2f-udev
  pcscd

)

# Populated after `apt-get update`, once apt has a current package index.
# These two packages swap places depending on the Debian release: neofetch was
# removed for Debian 13 (trixie), where fastfetch is the replacement. Whichever
# one is known to apt is installed, so the same script works on 12 and 13.
OPTIONAL_PACKAGES=()

# Extra packages installed only when the chosen suite is testing or unstable.
# apt-listbugs warns about release-critical bugs before package upgrades.
SUITE_PACKAGES=()

# Build dependencies for pyenv on Debian (the Void base-devel package does not
# pull in all of these). Installed only when the pyenv step actually runs.
readonly -a PYENV_BUILD_DEPS=(
  make
  build-essential
  libssl-dev
  zlib1g-dev
  libbz2-dev
  libreadline-dev
  libsqlite3-dev
  libncurses-dev
  xz-utils
  tk-dev
  libxml2-dev
  libxmlsec1-dev
  libffi-dev
  liblzma-dev
)

# Build dependencies for lemonbar-xft. These provide the XCB, Xlib, Xft,
# FreeType and fontconfig headers and libraries used by its Makefile.
readonly -a LEMONBAR_BUILD_DEPS=(
  libxcb1-dev
  libxcb-xinerama0-dev
  libxcb-randr0-dev
  libx11-dev
  libx11-xcb-dev
  libxft-dev
  libfreetype-dev
  libfontconfig1-dev
  zlib1g-dev
)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s: warning: %s\n' "${SCRIPT_NAME}" "$*" >&2; }
die()  { printf '%s: error: %s\n' "${SCRIPT_NAME}" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Provisions a Debian base install into a bspwm desktop.

Options:
  -y, --yes          answer "yes" to every confirmation prompt
      --no-pyenv     skip the pyenv installer
      --remove-self  delete ~/Fresh-Installs at the end (destructive)
  -h, --help         show this help

The Debian suite (stable, testing or unstable) is chosen interactively during
the install unless TARGET_SUITE is set in the environment.

Environment overrides: ASSUME_YES, INSTALL_PYENV, REMOVE_SELF, TARGET_SUITE,
DEBIAN_MIRROR, DEBIAN_SECURITY_MIRROR, LEMONBAR_*.
EOF
}

# Print the failing line and command, then exit.
on_err() {
  local code=$?
  trap - ERR
  printf '%s: error: aborted at line %s (exit %s): %s\n' \
    "${SCRIPT_NAME}" "${BASH_LINENO[0]}" "${code}" "${BASH_COMMAND}" >&2
  exit "${code}"
}
trap on_err ERR
# Exit 130 when interrupted.
trap 'printf "\n%s: interrupted, nothing further will run.\n" "${SCRIPT_NAME}" >&2; exit 130' INT TERM

# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "required command not found: ${cmd}"
  done
}

require_dir() {
  local dir="$1" hint="$2"
  [[ -d ${dir} ]] || die "missing directory: ${dir} (${hint})"
}

# Run a command with sudo.
sudo_run() {
  sudo "$@"
}

# Run apt-get non-interactively. Setting the variables through `env` makes sure
# they survive sudo, which strips most of the caller's environment by default.
apt_get() {
  sudo_run env \
    DEBIAN_FRONTEND=noninteractive \
    NEEDRESTART_MODE=a \
    APT_LISTCHANGES_FRONTEND=none \
    APT_LISTBUGS_FRONTEND=none \
    UCF_FORCE_CONFFOLD=1 \
    apt-get \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    "$@"
}

# True when stdin and stdout are terminals.
is_interactive() { [[ -t 0 && -t 1 ]]; }

confirm() {
  local prompt="$1" reply=''
  if [[ ${ASSUME_YES} == true ]]; then
    return 0
  fi
  if ! is_interactive; then
    warn "no terminal attached, assuming \"no\" for: ${prompt}"
    return 1
  fi
  read -r -p "${prompt} [y/N] " reply
  [[ ${reply} =~ ^[Yy]([Ee][Ss])?$ ]]
}

usage_error() {
  printf '%s: %s\n' "${SCRIPT_NAME}" "$*" >&2
  printf 'Try `%s --help` for the available options.\n' "${SCRIPT_NAME}" >&2
  exit 2
}

# Make files executable, warning about any that are missing.
make_executable() {
  local path
  for path in "$@"; do
    if [[ -f ${path} ]]; then
      chmod +x -- "${path}"
    else
      warn "not found, skipping: ${path}"
    fi
  done
}

# Add a shell to /etc/shells if it is not already listed.
ensure_shell_registered() {
  local shell="$1"
  if grep -qxF "${shell}" /etc/shells 2>/dev/null; then
    return 0
  fi
  info "registering ${shell} in /etc/shells (chsh refuses unregistered shells)"
  printf '%s\n' "${shell}" | sudo_run tee -a /etc/shells >/dev/null
}

# Create directories and any missing parents.
ensure_dir() {
  local dir
  for dir in "$@"; do
    mkdir -p -- "${dir}"
  done
}

# Download a zip archive and install the TrueType fonts it contains into a
# per-user font directory. Only the .ttf files are extracted, and the font cache
# is refreshed so the new fonts are available without logging out.
install_font_zip() {
  local url="$1" dest="$2"
  local tmpdir zip count

  # The archive is large (several hundred MB), so stage it under the home
  # directory rather than a possibly small tmpfs.
  tmpdir="$(mktemp -d "${HOME_DIR}/nerd-font.XXXXXX")"
  # Remove the temporary directory even if the download or extraction fails.
  # shellcheck disable=SC2064
  trap "rm -rf -- $(printf '%q' "${tmpdir}")" EXIT
  zip="${tmpdir}/font.zip"

  info "downloading ${url}"
  curl -fsSL --retry 3 --retry-delay 2 "${url}" -o "${zip}"

  info "extracting fonts into ${dest}"
  ensure_dir "${dest}"
  if ! unzip -o -q "${zip}" '*.ttf' -d "${dest}"; then
    die "failed to extract .ttf files from ${url}"
  fi

  count="$(find "${dest}" -type f -iname '*.ttf' | wc -l)"
  if ((count == 0)); then
    die "no .ttf files found in ${url}"
  fi

  info "refreshing the font cache"
  fc-cache -f "${dest}" >/dev/null

  rm -rf -- "${tmpdir}"
  trap - EXIT
}

# Clone, build and install lemonbar-xft. The source tree is kept between runs so
# a failed build can be retried without downloading everything again.
install_lemonbar_xft() {
  local src="${LEMONBAR_SRC_DIR}"

  if [[ -d ${src}/.git ]]; then
    info "using existing source tree at ${src}"
  else
    ensure_dir "$(dirname -- "${src}")"
    info "cloning ${LEMONBAR_REPO} (branch ${LEMONBAR_BRANCH})"
    git clone --depth 1 --branch "${LEMONBAR_BRANCH}" "${LEMONBAR_REPO}" "${src}" ||
      die "failed to clone lemonbar-xft"
  fi

  info "building lemonbar-xft"
  make -C "${src}" clean >/dev/null 2>&1 || true
  make -C "${src}" || die "failed to build lemonbar-xft"

  info "installing lemonbar into ${LEMONBAR_PREFIX}/bin"
  sudo_run install -D -m 755 "${src}/lemonbar" "${LEMONBAR_PREFIX}/bin/lemonbar"

  # The man page needs pod2man, which ships with perl. Install it when it can
  # be generated, but do not fail the whole step if it is unavailable.
  if make -C "${src}" doc >/dev/null 2>&1; then
    sudo_run install -D -m 644 "${src}/lemonbar.1" \
      "${LEMONBAR_PREFIX}/share/man/man1/lemonbar.1"
  else
    warn "could not build the lemonbar man page; installing the binary only"
  fi
}

# Upgrade the base system, using a full upgrade when the apt sources were
# switched to a rolling suite.
apt_full_upgrade() {
  if [[ ${TARGET_SUITE} == stable ]]; then
    apt_get -y upgrade
    return 0
  fi

  # A suite migration changes package versions and dependencies, so a plain
  # upgrade is not enough. Run full-upgrade twice: the first pass can hold
  # packages back while their dependencies move.
  apt_get -y full-upgrade
  apt_get -y full-upgrade
}

# Install the subset of the given packages that exists in the configured apt
# sources. Packages missing from the target suite are reported and skipped so
# one unavailable package cannot fail the whole install.
install_available_packages() {
  local -a available=() missing=()
  local pkg

  for pkg in "$@"; do
    if apt-cache show "${pkg}" >/dev/null 2>&1; then
      available+=("${pkg}")
    else
      missing+=("${pkg}")
    fi
  done

  if ((${#missing[@]} > 0)); then
    printf '%s: warning: not available on Debian %s, skipping:' \
      "${SCRIPT_NAME}" "${TARGET_SUITE}" >&2
    printf ' %s' "${missing[@]}" >&2
    printf '\n' >&2
  fi

  if ((${#available[@]} == 0)); then
    warn "no installable packages left in this group"
    return 0
  fi

  apt_get install -y "${available[@]}"
}

# ---------------------------------------------------------------------------
# Debian suite migration
# ---------------------------------------------------------------------------

# Print the codename from /etc/os-release, if present.
debian_codename() {
  local codename=''
  if [[ -r /etc/os-release ]]; then
    codename="$(
      # shellcheck disable=SC1091
      . /etc/os-release
      printf '%s' "${VERSION_CODENAME:-}"
    )"
  fi
  printf '%s\n' "${codename}"
}

# Print the codename the mirror currently publishes for a suite. Prints nothing
# when the mirror cannot be reached, so callers can fall back.
release_codename() {
  local suite="$1" release
  release="$(curl -fsSL --retry 2 --retry-delay 1 --max-time 30 \
    "${DEBIAN_MIRROR}/dists/${suite}/Release" 2>/dev/null)" || return 0
  awk -F': *' '$1 == "Codename" { print $2; exit }' <<< "${release}"
}

# Classify the running system as stable, testing, unstable or unknown.
current_debian_suite() {
  local codename stable_codename testing_codename
  codename="$(debian_codename)"

  case "${codename}" in
    sid | unstable)
      printf 'unstable\n'
      return 0
      ;;
  esac

  stable_codename="$(release_codename stable)"
  testing_codename="$(release_codename testing)"

  if [[ -n ${stable_codename} && ${codename} == "${stable_codename}" ]]; then
    printf 'stable\n'
  elif [[ -n ${testing_codename} && ${codename} == "${testing_codename}" ]]; then
    printf 'testing\n'
  else
    # Fall back to the codenames known when this script was written.
    case "${codename}" in
      trixie | bookworm | bullseye | buster) printf 'stable\n' ;;
      forky) printf 'testing\n' ;;
      *) printf 'unknown\n' ;;
    esac
  fi
}

# Ask which Debian suite to provision. An explicit TARGET_SUITE from the
# environment skips the prompt; a non-interactive run defaults to stable.
choose_target_suite() {
  local reply=''

  if [[ -n ${TARGET_SUITE} ]]; then
    info "using Debian ${TARGET_SUITE} from TARGET_SUITE"
    return 0
  fi

  if ! is_interactive; then
    warn "no terminal attached; provisioning Debian stable"
    TARGET_SUITE=stable
    return 0
  fi

  log "Select the Debian suite to provision"
  info "1) stable (default)"
  info "2) testing"
  info "3) unstable (sid)"

  while true; do
    if ! read -r -p 'Choice [1-3, default 1]: ' reply; then
      warn "no input; provisioning Debian stable"
      TARGET_SUITE=stable
      return 0
    fi
    case "${reply}" in
      '' | 1) TARGET_SUITE=stable; return 0 ;;
      2) TARGET_SUITE=testing; return 0 ;;
      3) TARGET_SUITE=unstable; return 0 ;;
      *) warn "please enter 1, 2, or 3" ;;
    esac
  done
}

# Back up the existing apt sources and replace them with a single deb822 file
# pointing at the requested suite. Returns without changing anything when the
# system is already on that suite.
switch_apt_suite() {
  local target="$1"
  local current codename backup_dir tmp_source suite_line f

  codename="$(debian_codename)"
  current="$(current_debian_suite)"

  if [[ ${current} == "${target}" ]]; then
    info "already on Debian ${target} (${codename}); leaving apt sources unchanged"
    return 0
  fi

  if [[ ${current} == unstable && ${target} == testing ]]; then
    die "refusing to downgrade from Debian unstable (sid) to testing"
  fi

  if [[ ${current} == unknown ]]; then
    warn "could not determine the current Debian suite (codename: ${codename:-unknown})"
  else
    info "current Debian suite: ${current} (${codename})"
  fi

  log "Migrating apt sources to Debian ${target}"
  info "existing sources will be backed up under /var/backups"
  if ! confirm "Replace the apt sources with Debian ${target} sources?"; then
    die "suite migration to Debian ${target} was declined"
  fi

  sudo_run mkdir -p /var/backups /etc/apt/sources.list.d
  backup_dir="$(sudo_run mktemp -d /var/backups/apt-sources.XXXXXX)"
  info "backing up apt sources to ${backup_dir}"

  for f in /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list \
    /etc/apt/sources.list.d/*.sources; do
    [[ -e ${f} ]] || continue
    sudo_run cp -a --parents -- "${f}" "${backup_dir}/"
  done

  # Remove the old definitions so apt does not mix stable and target suites.
  sudo_run rm -f -- /etc/apt/sources.list
  for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -e ${f} ]] || continue
    sudo_run rm -f -- "${f}"
  done

  # Unstable has no security suite of its own, so only the main archive is
  # used there. Testing has both testing-updates and testing-security.
  if [[ ${target} == testing ]]; then
    suite_line='testing testing-updates'
  else
    suite_line='unstable'
  fi

  tmp_source="$(mktemp)"
  {
    printf 'Types: deb\n'
    printf 'URIs: %s\n' "${DEBIAN_MIRROR}"
    printf 'Suites: %s\n' "${suite_line}"
    printf 'Components: main contrib non-free non-free-firmware\n'
    printf 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg\n'

    if [[ ${target} == testing ]]; then
      printf '\n'
      printf 'Types: deb\n'
      printf 'URIs: %s\n' "${DEBIAN_SECURITY_MIRROR}"
      printf 'Suites: testing-security\n'
      printf 'Components: main contrib non-free non-free-firmware\n'
      printf 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg\n'
    fi
  } > "${tmp_source}"

  sudo_run install -D -m 644 "${tmp_source}" \
    "/etc/apt/sources.list.d/debian-${target}.sources"
  rm -f -- "${tmp_source}"

  REBOOT_REQUIRED=true
  info "apt sources now point at Debian ${target}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y | --yes)     ASSUME_YES=true ;;
    --no-pyenv)     INSTALL_PYENV=false ;;
    --remove-self)  REMOVE_SELF=true ;;
    -h | --help)    usage; exit 0 ;;
    *)              usage_error "unknown option: $1" ;;
  esac
  shift
done

# Normalize and validate a suite selected through the environment. When it is
# empty, choose_target_suite prompts during step 1.
if [[ -n ${TARGET_SUITE} ]]; then
  case "${TARGET_SUITE}" in
    stable | testing) ;;
    sid | unstable) TARGET_SUITE=unstable ;;
    *)
      usage_error "invalid TARGET_SUITE: ${TARGET_SUITE} (expected stable, testing or unstable)"
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

# sudo cannot install itself, so a truly minimal Debian install has to take
# this one step manually before the script can run.
if ! command -v sudo >/dev/null 2>&1; then
  die "sudo is not installed. As root run: apt-get update && apt-get install -y sudo, add your user to the sudo group, then log in again"
fi

require_cmd apt-get apt-cache
# Authenticate sudo once up front.
sudo -v || die "sudo authentication failed"

# git/curl are needed before the main package transaction (to clone the repos),
# and ca-certificates is needed for the HTTPS clones and the pyenv installer.
if ! command -v git >/dev/null 2>&1 ||
  ! command -v curl >/dev/null 2>&1 ||
  [[ ! -r /etc/ssl/certs/ca-certificates.crt ]]; then
  log "Installing bootstrap prerequisites (git, curl, CA certificates)"
  apt_get update
  apt_get install -y git curl ca-certificates
fi
require_cmd git curl

# Clone required repositories if they are missing.
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/Shipwright0/dotfiles.git}"
SCRIPTS_REPO="${SCRIPTS_REPO:-https://github.com/Shipwright0/scripts.git}"
SYSCOMPS_REPO="${SYSCOMPS_REPO:-https://github.com/Shipwright0/syscomps.git}"

log "Ensuring required repositories are present"

# dotfiles
if [[ ! -d "${DOTFILES_DIR}/.git" ]]; then
  if [[ -z "${DOTFILES_REPO}" ]]; then
    die "dotfiles missing at ${DOTFILES_DIR} and DOTFILES_REPO not set. Set DOTFILES_REPO or clone manually."
  fi
  log "Cloning dotfiles from ${DOTFILES_REPO}"
  git clone --depth 1 "${DOTFILES_REPO}" "${DOTFILES_DIR}" || die "failed to clone dotfiles"
fi

# scripts
if [[ ! -d "${SCRIPTS_DIR}/.git" ]]; then
  if [[ -z "${SCRIPTS_REPO}" ]]; then
    die "scripts missing at ${SCRIPTS_DIR} and SCRIPTS_REPO not set. Set SCRIPTS_REPO or clone manually."
  fi
  log "Cloning scripts from ${SCRIPTS_REPO}"
  git clone --depth 1 "${SCRIPTS_REPO}" "${SCRIPTS_DIR}" || die "failed to clone scripts"
fi

# syscomps
if [[ ! -d "${SYSCOMPS_DIR}/.git" ]]; then
  if [[ -z "${SYSCOMPS_REPO}" ]]; then
    die "syscomps missing at ${SYSCOMPS_DIR} and SYSCOMPS_REPO not set. Set SYSCOMPS_REPO or clone manually."
  fi
  log "Cloning syscomps from ${SYSCOMPS_REPO}"
  git clone --depth 1 "${SYSCOMPS_REPO}" "${SYSCOMPS_DIR}" || die "failed to clone syscomps"
fi

log "Creating base directories"
ensure_dir "${BASESCRIPTS_DIR}/usable" \
  "${BASESCRIPTS_DIR}/localscripts" \
  "${BASESCRIPTS_DIR}/syncscripts" \
  "${HOME_DIR}/audio" \
  "${HOME_DIR}/documents" \
  "${HOME_DIR}/visual/pictures" \
  "${HOME_DIR}/visual/video"

# ---------------------------------------------------------------------------
# 1. Update + packages
# ---------------------------------------------------------------------------

# Let the user pick the suite, then migrate before the main package install so
# the packages below come from the requested suite.
choose_target_suite
if [[ ${TARGET_SUITE} != stable ]]; then
  switch_apt_suite "${TARGET_SUITE}"
fi

log "Updating the base system"
# Sync the package index and update installed packages. A suite migration
# needs a full upgrade, which apt_full_upgrade handles.
apt_get update
apt_full_upgrade

# apt-listbugs is useful on the rolling suites, where release-critical bugs are
# more common. Install it after the upgrade so it does not interrupt it.
if [[ ${TARGET_SUITE} != stable ]]; then
  SUITE_PACKAGES+=(apt-listbugs)
fi

# Choose the fetch tool that this Debian release actually ships.
if apt-cache show fastfetch >/dev/null 2>&1; then
  OPTIONAL_PACKAGES+=(fastfetch)
elif apt-cache show neofetch >/dev/null 2>&1; then
  OPTIONAL_PACKAGES+=(neofetch)
fi

log "Installing packages (${#PACKAGES[@]})"
# Install all packages in one transaction, skipping any that the target suite
# does not provide.
install_available_packages "${PACKAGES[@]}"

if ((${#SUITE_PACKAGES[@]} > 0)); then
  log "Installing suite-specific packages: ${SUITE_PACKAGES[*]}"
  install_available_packages "${SUITE_PACKAGES[@]}"
fi

if ((${#OPTIONAL_PACKAGES[@]} > 0)); then
  log "Installing release-specific packages: ${OPTIONAL_PACKAGES[*]}"
  install_available_packages "${OPTIONAL_PACKAGES[@]}"
fi

# ---------------------------------------------------------------------------
# 2. Fonts
# ---------------------------------------------------------------------------

log "Installing the Iosevka Nerd Font"
# Installed from the upstream release archive rather than a Debian package so
# the patched Nerd Font variants are available. The fonts go into the current
# user's font directory, so no root privileges are needed.
if [[ -n "$(find "${IOSEVKA_FONT_DIR}" -type f -iname '*.ttf' -print -quit 2>/dev/null)" ]]; then
  info "already installed in ${IOSEVKA_FONT_DIR}, skipping"
else
  require_cmd unzip fc-cache
  install_font_zip "${IOSEVKA_FONT_URL}" "${IOSEVKA_FONT_DIR}"
fi

# ---------------------------------------------------------------------------
# 3. lemonbar-xft
# ---------------------------------------------------------------------------

log "Installing lemonbar-xft"
# The panel passes Xft font specifiers, which the Debian lemonbar package does
# not understand. Build the Xft fork from upstream instead.
if [[ -x "${LEMONBAR_PREFIX}/bin/lemonbar" ]]; then
  info "already installed at ${LEMONBAR_PREFIX}/bin/lemonbar, skipping"
else
  log "Installing lemonbar-xft build dependencies"
  apt_get install -y "${LEMONBAR_BUILD_DEPS[@]}"
  require_cmd make gcc
  install_lemonbar_xft
fi

# ---------------------------------------------------------------------------
# 4. Yubikey
# ---------------------------------------------------------------------------

log "Enabling yubikey support"
# The plugdev group is normally present on Debian, but create it defensively.
if ! getent group plugdev >/dev/null 2>&1; then
  info "creating the plugdev group"
  sudo_run groupadd plugdev || warn "could not create the plugdev group"
fi

# Add the user to plugdev if needed.
if id -nG "${CURRENT_USER}" | grep -qw plugdev; then
  info "already a member of plugdev"
else
  sudo_run gpasswd -a "${CURRENT_USER}" plugdev
fi

# Enable the pcscd smartcard service. Debian uses systemd and prefers socket
# activation; fall back to the service unit on systems that do not ship the
# socket, and only warn if systemd is unavailable (for example in a container).
if ! sudo_run systemctl enable --now pcscd.socket; then
  sudo_run systemctl enable --now pcscd.service ||
    warn "could not enable pcscd; enable it manually with: sudo systemctl enable --now pcscd.socket"
fi

# ---------------------------------------------------------------------------
# 5. pyenv
# ---------------------------------------------------------------------------

# Install pyenv from a downloaded script (skip with --no-pyenv).
if [[ ${INSTALL_PYENV} == true ]]; then
  if [[ -x ${HOME_DIR}/.pyenv/bin/pyenv ]]; then
    info "pyenv already installed, skipping installer"
  elif confirm "Download and run the pyenv installer (https://pyenv.run)?"; then
    log "Installing pyenv build dependencies"
    apt_get install -y "${PYENV_BUILD_DEPS[@]}"

    log "Installing pyenv"
    # Download the installer, run it, then remove it.
    pyenv_installer="$(mktemp "${HOME_DIR}/pyenv-install.XXXXXX.sh")"
    curl -fsSL https://pyenv.run -o "${pyenv_installer}"
    if ! bash "${pyenv_installer}"; then
      rm -f -- "${pyenv_installer}"
      die "pyenv installer failed"
    fi
    rm -f -- "${pyenv_installer}"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Executable bits, shell, dotfiles, themer
# ---------------------------------------------------------------------------

log "Marking repository scripts executable"
make_executable \
  "${SCRIPTS_DIR}/theming/theme_changer" \
  "${SCRIPTS_DIR}/theming/wpset" \
  "${SYSCOMPS_DIR}/bar/bspwmbar/panel" \
  "${SYSCOMPS_DIR}/bar/bspwmbar/panel_bar" \
  "${SYSCOMPS_DIR}/dmenu/dmenu.sh"

log "Switching the login shell to zsh"
# Debian installs zsh at /usr/bin/zsh (with /bin a symlink to /usr/bin), so
# resolve the path instead of hardcoding /bin/zsh.
require_cmd zsh
ZSH_PATH="$(command -v zsh)"
ensure_shell_registered "${ZSH_PATH}"
chsh -s "${ZSH_PATH}" || warn "could not change the login shell; run: chsh -s ${ZSH_PATH}"

log "Stowing dotfiles"
require_dir "${DOTFILES_DIR}" "clone your dotfiles repo before re-running this"
# Link the dotfile packages, restowing any already linked.
stow --dir="${DOTFILES_DIR}" --restow colors bspwm mpd ncmpcpp newsboat ranger dunst zsh sxhkd xres neovim

# The dotfiles' .zshrc sources ${ZSH}/oh-my-zsh.sh, so it must exist before the
# new shell starts. Done after stowing so ~/.zshrc is already linked: the
# installer otherwise writes its own template, which would block stow.
# --unattended keeps it from launching zsh or touching the login shell, and
# --keep-zshrc stops it replacing the linked .zshrc.
log "Installing oh-my-zsh"
if [[ ! -d "${HOME_DIR}/.oh-my-zsh" ]]; then
  omz_installer="$(mktemp "${HOME_DIR}/oh-my-zsh-install.XXXXXX.sh")"
  if curl -fsSL --retry 3 --retry-delay 2 \
    https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "${omz_installer}"; then
    if RUNZSH=no CHSH=no sh "${omz_installer}" --unattended --keep-zshrc; then
      rm -f -- "${omz_installer}"
    else
      rm -f -- "${omz_installer}"
      die "oh-my-zsh installer failed"
    fi
  else
    rm -f -- "${omz_installer}"
    die "could not download the oh-my-zsh installer"
  fi
else
  log "oh-my-zsh already installed"
fi

# ---------------------------------------------------------------------------
# 7. Wrap up
# ---------------------------------------------------------------------------

# Delete this repository only when explicitly requested and safe to do so.
if [[ ${REMOVE_SELF} == true ]]; then
  case "${SCRIPT_DIR}" in
    "${HOME_DIR}"|/|"${HOME_DIR}"/)
      warn "refusing to delete ${SCRIPT_DIR}" ;;
    *)
      if [[ ${SCRIPT_DIR} != "${HOME_DIR}"/* ]]; then
        warn "refusing to delete ${SCRIPT_DIR}: not inside ${HOME_DIR}"
      elif [[ ${PWD} == "${SCRIPT_DIR}" ]]; then
        warn "not deleting ${SCRIPT_DIR}: change out of it first (cd ~)"
      elif confirm "Delete ${SCRIPT_DIR}?"; then
        sudo_run rm -rf -- "${SCRIPT_DIR}"
      fi ;;
  esac
fi

printf '\n%s: done - maybe.\n' "${SCRIPT_NAME}"
if [[ ${REBOOT_REQUIRED} == true ]]; then
  printf '\n*** Reboot required: this system was migrated to Debian %s. ***\n' \
    "${TARGET_SUITE}"
  printf 'Reboot before using the desktop so the new kernel and libraries load.\n'
fi
printf 'Remember which platform you are on, then log out and back in so the\n'
printf 'new shell, fonts and theme are picked up; the themer needs X running.\n'

# Success.
exit 0
