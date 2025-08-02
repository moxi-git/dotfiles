#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# Default flags
# -------------------------------
AUTO_YES=false
SKIP_DOTS=false
SKIP_PACKAGES=false
DRY_RUN=false

# -------------------------------
# Color output
# -------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------
# Logging functions
# -------------------------------
log_info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
  echo -e "${BLUE}[DEBUG]${NC} $1"
}

# -------------------------------
# Error handling
# -------------------------------
cleanup() {
  if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
    log_debug "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR"
  fi
}

trap cleanup EXIT

error_exit() {
  log_error "$1"
  exit 1
}

# -------------------------------
# Helpers
# -------------------------------
command_exists() {
  command -v "$1" &>/dev/null
}

realpath_rel() {
  if command_exists realpath; then
    realpath --relative-to="$HOME" "$1"
  elif command_exists python3; then
    python3 -c "import os.path; print(os.path.relpath('$1', '$HOME'))"
  else
    echo "$1"
  fi
}

pkg_installed() {
  local pkg=$1
  if command_exists pacman; then
    pacman -Qq "$pkg" &>/dev/null && return 0
  fi
  return 1
}

filter_missing_pkgs() {
  local pkgs=("$@")
  local missing=()
  for pkg in "${pkgs[@]}"; do
    if ! pkg_installed "$pkg"; then
      missing+=("$pkg")
    fi
  done
  echo "${missing[@]}"
}

# Check if we're on Arch Linux
check_arch_linux() {
  if [ ! -f /etc/arch-release ]; then
    error_exit "This script is designed for Arch Linux only. Current system not supported."
  fi
}

# Check internet connectivity
check_internet() {
  log_info "Checking internet connectivity..."
  if ! ping -c 1 google.com &>/dev/null && ! ping -c 1 8.8.8.8 &>/dev/null; then
    error_exit "No internet connection. Please check your network and try again."
  fi
  log_info "Internet connection verified."
}

# Update package database
update_package_db() {
  log_info "Updating package database..."
  if [ "$DRY_RUN" = true ]; then
    echo "[Dry-run] Would run: sudo pacman -Sy"
  else
    if ! sudo pacman -Sy; then
      error_exit "Failed to update package database"
    fi
  fi
}

# -------------------------------
# Parse command-line arguments
# -------------------------------
for arg in "$@"; do
  case "$arg" in
  -y | --yes) AUTO_YES=true ;;
  --no-dots) SKIP_DOTS=true ;;
  --no-packages) SKIP_PACKAGES=true ;;
  --dry-run) DRY_RUN=true ;;
  -h | --help)
    echo "Usage: ./install.sh [options]"
    echo
    echo "Options:"
    echo "  -y, --yes         Automatically confirm all prompts"
    echo "      --no-dots     Skip dotfile linking"
    echo "      --no-packages Skip package installation"
    echo "      --dry-run     Show actions without performing them"
    echo "  -h, --help        Show this help message"
    exit 0
    ;;
  *)
    echo "Unknown option: $arg"
    exit 1
    ;;
  esac
done

# -------------------------------
# Confirmation Functions
# -------------------------------
confirm() {
  if [ "$AUTO_YES" = true ] || [ "$DRY_RUN" = true ]; then return 0; fi
  while true; do
    read -rp "$1 [Y/n]: " yn
    case "$yn" in
    [Yy] | "") return 0 ;;
    [Nn]) return 1 ;;
    *) echo "Please answer Y or N." ;;
    esac
  done
}

confirm_start() {
  if [ "$AUTO_YES" = true ] || [ "$DRY_RUN" = true ]; then return; fi
  while true; do
    read -rp "Start the installation script? [Y/n]: " yn
    case "$yn" in
    [Yy] | "") break ;;
    [Nn])
      echo "Exiting installer."
      exit 0
      ;;
    *) echo "Please answer Y or N." ;;
    esac
  done
}

confirm_overwrite() {
  local dest="$1"
  if [[ "$dest" != "$HOME"* ]]; then
    log_error "Refusing to overwrite $dest outside of home directory."
    return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ]; then
      local link_target
      link_target=$(readlink "$dest")
      if [[ "$link_target" == "$DOTFILES_DIR/"* ]]; then
        log_info "$dest is already correctly linked. Skipping."
        return 1
      fi
    fi
    echo
    log_warn "$dest already exists and will be removed if you choose to overwrite."
    if confirm "Overwrite $dest?"; then
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would remove $dest"
      else
        if ! rm -rf "$dest"; then
          log_error "Failed to remove $dest"
          return 1
        fi
      fi
      return 0
    else
      log_info "Skipping $dest"
      return 1
    fi
  fi
  return 0
}

# -------------------------------
# Root check and warn
# -------------------------------
if [ "$EUID" -eq 0 ]; then
  log_warn "Running the installer as root is not recommended."
  if ! confirm "Continue as root?"; then exit 1; fi
fi

# -------------------------------
# System checks
# -------------------------------
check_arch_linux
check_internet

# -------------------------------
# Welcome & Start
# -------------------------------
cat <<'EOF'
   __  ___          _     
  /  |/  /__ __ __ (_)_ __
 / /|_/ / _ \ \ // / // /
/_/  /_/\___/_\_\/_/\_,_/  
EOF

echo
log_info "Welcome to the Moxiu T470 dotfiles installer!"
echo

confirm_start

# -------------------------------
# Paths & Preparation
# -------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)

log_info "Dotfiles directory: $DOTFILES_DIR"
log_debug "Temporary directory: $TEMP_DIR"

# Verify configs directory exists
if [ ! -d "$DOTFILES_DIR/configs" ]; then
  error_exit "configs/ directory not found in $DOTFILES_DIR"
fi

# -------------------------------
# Update package database
# -------------------------------
if [ "$SKIP_PACKAGES" = false ]; then
  update_package_db
fi

# -------------------------------
# Install base-devel
# -------------------------------
if [ "$SKIP_PACKAGES" = false ] && confirm "Install base-devel group packages with pacman?"; then
  log_info "Installing base-devel group..."
  if [ "$DRY_RUN" = true ]; then
    echo "[Dry-run] Would run: sudo pacman -S --needed --noconfirm base-devel"
  else
    if ! sudo pacman -S --needed --noconfirm base-devel; then
      error_exit "Failed to install base-devel group"
    fi
  fi
  log_info "base-devel group installed successfully."
fi

# -------------------------------
# Install additional pacman packages
# -------------------------------
if [ "$SKIP_PACKAGES" = false ]; then
  log_info "Installing additional pacman packages..."

  pacman_packages=(
    nemo btop pavucontrol nvim pyright git
  )

  missing_pacman_pkgs=($(filter_missing_pkgs "${pacman_packages[@]}"))

  if [ "${#missing_pacman_pkgs[@]}" -eq 0 ]; then
    log_info "All pacman packages are already installed."
  else
    log_info "Installing pacman packages: ${missing_pacman_pkgs[*]}"
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: sudo pacman -S --needed --noconfirm ${missing_pacman_pkgs[*]}"
    else
      if ! sudo pacman -S --needed --noconfirm "${missing_pacman_pkgs[@]}"; then
        error_exit "Failed to install pacman packages: ${missing_pacman_pkgs[*]}"
      fi
    fi
    log_info "Pacman packages installed successfully."
  fi
fi

# -------------------------------
# Ensure paru is installed
# -------------------------------
if [ "$SKIP_PACKAGES" = false ]; then
  if ! command_exists paru; then
    log_info "paru is required for AUR installs."
    if confirm "paru not found. Clone and install paru?"; then
      log_info "Installing paru..."
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would clone paru repo and build it"
      else
        # Ensure git is available
        if ! command_exists git; then
          error_exit "git is required to install paru but not found"
        fi

        paru_dir="$TEMP_DIR/paru"
        if ! git clone https://aur.archlinux.org/paru.git "$paru_dir"; then
          error_exit "Failed to clone paru repository"
        fi

        pushd "$paru_dir" >/dev/null || error_exit "Failed to enter paru directory"

        if ! makepkg -si --noconfirm; then
          popd >/dev/null
          error_exit "Failed to build and install paru"
        fi

        popd >/dev/null
        log_info "paru installed successfully."
      fi
    else
      error_exit "paru is required to proceed. Exiting."
    fi
  else
    log_info "paru is already installed."
  fi

  log_info "Installing AUR packages and dependencies via paru..."

  aur_packages=(
    caelestia-shell-git caelestia-cli-git
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    hyprpicker hypridle wl-clipboard cliphist bluez-utils inotify-tools
    app2unit wireplumber trash-cli foot fish fastfetch starship
    btop jq socat imagemagick curl adw-gtk-theme
    papirus-icon-theme qt5ct qt6ct ttf-jetbrains-mono-nerd
    zen-browser-bin noto-fonts-emoji ttf-joypixels ttf-twemoji-color
  )

  missing_aur_pkgs=($(filter_missing_pkgs "${aur_packages[@]}"))

  if [ "${#missing_aur_pkgs[@]}" -eq 0 ]; then
    log_info "All AUR packages are already installed."
  else
    log_info "AUR packages to install: ${missing_aur_pkgs[*]}"
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: paru -S --needed --noconfirm ${missing_aur_pkgs[*]}"
    else
      if ! paru -S --needed --noconfirm "${missing_aur_pkgs[@]}"; then
        log_error "Some AUR packages failed to install. Continuing with dotfiles..."
      else
        log_info "AUR packages installed successfully."
      fi
    fi
  fi

  echo
fi

# -------------------------------
# Link dotfiles from configs/
# -------------------------------
if [ "$SKIP_DOTS" = false ]; then
  log_info "Installing dotfiles from $DOTFILES_DIR/configs to $HOME and ~/.config..."
  echo

  CONFIGS_DIR="$DOTFILES_DIR/configs"

  # Handle files in configs/ (e.g. .bashrc, .viminfo)
  if find "$CONFIGS_DIR" -mindepth 1 -maxdepth 1 ! -name ".config" | head -1 | read -r; then
    find "$CONFIGS_DIR" -mindepth 1 -maxdepth 1 ! -name ".config" | while read -r item; do
      base=$(basename "$item")
      target="$HOME/$base"

      if confirm_overwrite "$target"; then
        if [ "$DRY_RUN" = true ]; then
          echo "[Dry-run] Would link $item → $target"
        else
          if ln -sfn "$item" "$target"; then
            log_info "Linked $(realpath_rel "$item") → $(realpath_rel "$target")"
          else
            log_error "Failed to link $item → $target"
          fi
        fi
      fi
    done
  fi

  # Handle files inside configs/.config/
  if [ -d "$CONFIGS_DIR/.config" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would create ~/.config directory"
    else
      mkdir -p "$HOME/.config"
    fi

    if find "$CONFIGS_DIR/.config" -mindepth 1 -maxdepth 1 | head -1 | read -r; then
      find "$CONFIGS_DIR/.config" -mindepth 1 -maxdepth 1 | while read -r config_item; do
        config_name=$(basename "$config_item")
        config_target="$HOME/.config/$config_name"

        if confirm_overwrite "$config_target"; then
          if [ "$DRY_RUN" = true ]; then
            echo "[Dry-run] Would link $config_item → $config_target"
          else
            if ln -sfn "$config_item" "$config_target"; then
              log_info "Linked $(realpath_rel "$config_item") → $(realpath_rel "$config_target")"
            else
              log_error "Failed to link $config_item → $config_target"
            fi
          fi
        fi
      done
    fi
  fi

  echo
fi

# -------------------------------
# Change shell to fish (only if fish is installed)
# -------------------------------
if command_exists fish; then
  current_shell=$(getent passwd "$USER" | cut -d: -f7)
  if [ "$current_shell" != "/usr/bin/fish" ]; then
    log_info "Changing default shell to fish..."
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: chsh -s /usr/bin/fish"
    else
      if ! chsh -s /usr/bin/fish; then
        log_warn "Failed to change shell to fish. You can change it manually later with: chsh -s /usr/bin/fish"
      else
        log_info "Default shell changed to fish."
      fi
    fi
  else
    log_info "Shell is already set to fish."
  fi
else
  log_warn "fish shell not found. Skipping shell change."
fi

log_info "All done! Enjoy your Moxiu T470 dotfiles."
[ "$DRY_RUN" = true ] && echo "[Dry-run] No changes were actually made."

# -------------------------------
# Reboot prompt
# -------------------------------
if [ "$DRY_RUN" = false ]; then
  while true; do
    read -rp "Reboot (Highly Recommended!) [Y/n]: " yn
    case "$yn" in
    [Yy] | "")
      log_info "Rebooting..."
      sudo reboot
      break
      ;;
    [Nn])
      log_info "Please reboot later to apply all changes."
      break
      ;;
    *) echo "Please answer Y or N." ;;
    esac
  done
else
  echo "[Dry-run] Would prompt for reboot"
fi
