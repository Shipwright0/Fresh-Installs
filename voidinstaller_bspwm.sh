#!/usr/bin/env bash
#
# voidinstaller_bspwm.v2.sh - provision a bspwm desktop on Void Linux from a
# base install.
#
# Steps:
#   1. Update the system and install packages
#   2. Configure yubikey support
#   3. Install pyenv
#   4. Set executable bits, switch shell, stow dotfiles, run themer
#   5. Optionally delete this repository
#
# Usage:
#   ./voidinstaller_bspwm.v2.sh [options]
#
#   -y, --yes          answer "yes" to every confirmation prompt
#       --no-pyenv     skip the pyenv installer
#       --remove-self  delete ~/Fresh-Installs at the end (destructive)
#   -h, --help         show this help
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
  printf 'voidinstaller_bspwm.v2.sh: error: do not run this as root; run it as\n' >&2
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

readonly SCRIPT_NAME SCRIPT_DIR
readonly ASSUME_YES INSTALL_PYENV REMOVE_SELF

readonly HOME_DIR="${HOME}"
readonly DOTFILES_DIR="${HOME_DIR}/dotfiles"
readonly SCRIPTS_DIR="${HOME_DIR}/scripts/gitscripts"
readonly BASESCRIPTS_DIR="${HOME_DIR}/scripts"
readonly SYSCOMPS_DIR="${HOME_DIR}/syscomps"

# Path to the themer script.
readonly THEMER="${SCRIPTS_DIR}/theming/theme_changer"

# Packages installed from the Void repositories.
readonly -a PACKAGES=(
  xorg
  rxvt-unicode
  dmenu
  hsetroot
  xdotool
  zsh
  xtools
  xclip
  dunst
  libnotify
  stow
  vim
  font-iosevka
  base-devel
  htop
  flatpak
  pywal
  ImageMagick
  youtube-dl
  mpv
  picom
  firefox
  alsa-tools
  alsa-utils
  lemonbar-xft
  ranger
  neovim
  pnpm
  podman
  python3-pip
  ncmpcpp
  mopidy
  u2f-hidraw-policy
  libfido2
  git
  curl
  syncthing
  chatterino2
  zathura
  surf
  bspwm
  sxhkd
  libreoffice
  newsboat
  hugo
  w3m-img
  sxiv
  flameshot
  unclutter
  redshift
  trash-cli
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

Provisions a Void Linux base install into a bspwm desktop.

Options:
  -y, --yes          answer "yes" to every confirmation prompt
      --no-pyenv     skip the pyenv installer
      --remove-self  delete ~/Fresh-Installs at the end (destructive)
  -h, --help         show this help

Environment overrides: ASSUME_YES, INSTALL_PYENV, REMOVE_SELF.
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

# Enable a runit service if it is not already enabled.
enable_sv_service() {
  local svc="$1"
  if [[ -e /var/service/${svc} ]]; then
    info "service already enabled: ${svc}"
  elif [[ -x /etc/sv/${svc}/run ]]; then
    sudo_run ln -s -- "/etc/sv/${svc}" /var/service/
  else
    die "service not found: /etc/sv/${svc}"
  fi
}

# Create directories and any missing parents.
ensure_dir() {
  local dir
  for dir in "$@"; do
    mkdir -p -- "${dir}"
  done
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

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

require_cmd sudo git curl
# Authenticate sudo once up front.
sudo -v || die "sudo authentication failed"

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
ensure_dir  "${BASESCRIPTS_DIR}/usable" \
  "${BASESCRIPTS_DIR}/localscripts" \
  "${BASESCRIPTS_DIR}/syncscripts" \
  "${HOME_DIR}/audio" \
  "${HOME_DIR}/documents" \
  "${HOME_DIR}/visual/pictures" \
  "${HOME_DIR}/visual/video" \

# ---------------------------------------------------------------------------
# 1. Update + packages
# ---------------------------------------------------------------------------

log "Updating the base system"
# Sync the package index and update installed packages.
sudo_run xbps-install -Suv -y

log "Installing packages (${#PACKAGES[@]})"
# Install all packages in one transaction.
sudo_run xbps-install -y -S "${PACKAGES[@]}"

# ---------------------------------------------------------------------------
# 2. Yubikey
# ---------------------------------------------------------------------------

log "Enabling yubikey support"
# Add the user to plugdev if needed.
if groups "${USER}" | grep -qw plugdev; then
  info "already a member of plugdev"
else
  sudo_run gpasswd -a "${USER}" plugdev
fi
# Enable the pcscd smartcard service.
enable_sv_service pcscd

# ---------------------------------------------------------------------------
# 3. pyenv
# ---------------------------------------------------------------------------

# Install pyenv from a downloaded script (skip with --no-pyenv).
if [[ ${INSTALL_PYENV} == true ]]; then
  if [[ -x ${HOME_DIR}/.pyenv/bin/pyenv ]]; then
    info "pyenv already installed, skipping installer"
  elif confirm "Download and run the pyenv installer (https://pyenv.run)?"; then
    log "Installing pyenv"
    # Download the installer, run it, then remove it.
    pyenv_installer="$(mktemp "${HOME_DIR}/pyenv-install.XXXXXX.sh")"
    curl -fsSL https://pyenv.run -o "${pyenv_installer}"
    bash "${pyenv_installer}"
    rm -f -- "${pyenv_installer}"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Executable bits, shell, dotfiles, themer
# ---------------------------------------------------------------------------

log "Marking repository scripts executable"
make_executable \
  "${SCRIPTS_DIR}/theming/theme_changer" \
  "${SCRIPTS_DIR}/theming/wpset" \
  "${SYSCOMPS_DIR}/bar/bspwmbar/panel" \
  "${SYSCOMPS_DIR}/bar/bspwmbar/panel_bar" \
  "${SYSCOMPS_DIR}/dmenu/dmenu.sh"

log "Switching the login shell to zsh"
ensure_shell_registered /bin/zsh
chsh -s /bin/zsh || warn "could not change the login shell; run: chsh -s /bin/zsh"

log "Stowing dotfiles"
require_dir "${DOTFILES_DIR}" "clone your dotfiles repo before re-running this"
# Link the dotfile packages, restowing any already linked.
stow --dir="${DOTFILES_DIR}" --restow dunst zsh Xres neofetch wal neovim

# The dotfiles' .zshrc sources ${ZSH}/oh-my-zsh.sh, so it must exist before the
# new shell starts. Done after stowing so ~/.zshrc is already linked: the
# installer otherwise writes its own template, which would block stow.
# --unattended keeps it from launching zsh or touching the login shell, and
# --keep-zshrc stops it replacing the linked .zshrc.
log "Installing oh-my-zsh"
if [[ ! -d "${HOME_DIR}/.oh-my-zsh" ]]; then
  omz_installer="$(mktemp "${HOME_DIR}/oh-my-zsh-install.XXXXXX.sh")"
  if curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "${omz_installer}"; then
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

# Run the themer if it is executable.
if [[ -x ${THEMER} ]]; then
  log "Running the themer"
  "${THEMER}" || warn "the themer exited non-zero; run it manually after logging in"
else
  warn "themer not executable, skipping: ${THEMER}"
fi

# ---------------------------------------------------------------------------
# 5. Wrap up
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
printf 'Remember which platform you are on, then log out and back in so the\n'
printf 'new shell, fonts and theme are picked up; the themer needs X running.\n'

# Success.
exit 0
