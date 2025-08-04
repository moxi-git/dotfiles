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
# Distribution detection
# -------------------------------
DISTRO=""
PACKAGE_MANAGER=""

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

# -------------------------------
# Distribution detection functions
# -------------------------------
detect_distro() {
  if [ -f /etc/arch-release ]; then
    DISTRO="arch"
    PACKAGE_MANAGER="pacman"
  elif [ -f /etc/gentoo-release ]; then
    DISTRO="gentoo"
    PACKAGE_MANAGER="portage"
  elif command_exists emerge; then
    DISTRO="gentoo"
    PACKAGE_MANAGER="portage"
  else
    error_exit "Unsupported distribution. This script supports Arch Linux and Gentoo only."
  fi

  log_info "Detected distribution: $DISTRO"
  log_debug "Package manager: $PACKAGE_MANAGER"
}

# -------------------------------
# Package management functions
# -------------------------------
pkg_installed() {
  local pkg=$1
  case "$PACKAGE_MANAGER" in
  pacman)
    pacman -Qq "$pkg" &>/dev/null && return 0
    ;;
  portage)
    # Check if package is installed in Gentoo
    if equery list "$pkg" &>/dev/null; then
      return 0
    elif emerge --pretend --quiet "$pkg" 2>/dev/null | grep -q "^\[ebuild.*R.*\]"; then
      return 0
    fi
    ;;
  esac
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

update_package_db() {
  log_info "Updating package database..."
  case "$PACKAGE_MANAGER" in
  pacman)
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: sudo pacman -Sy"
    else
      if ! sudo pacman -Sy; then
        error_exit "Failed to update package database"
      fi
    fi
    ;;
  portage)
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: sudo emerge --sync"
    else
      if ! sudo emerge --sync; then
        error_exit "Failed to sync portage tree"
      fi
    fi
    ;;
  esac
}

install_base_packages() {
  case "$DISTRO" in
  arch)
    if confirm "Install base-devel group packages with pacman?"; then
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
    ;;
  gentoo)
    if confirm "Install essential build tools (equivalent to base-devel)?"; then
      log_info "Installing essential build tools..."
      local build_tools=(
        "sys-devel/gcc"
        "sys-devel/make"
        "sys-devel/binutils"
        "sys-devel/libtool"
        "sys-devel/autoconf"
        "sys-devel/automake"
        "sys-devel/patch"
        "sys-apps/pkgconfig"
      )

      local missing_build_tools=($(filter_missing_pkgs "${build_tools[@]}"))

      if [ "${#missing_build_tools[@]}" -eq 0 ]; then
        log_info "All build tools are already installed."
      else
        if [ "$DRY_RUN" = true ]; then
          echo "[Dry-run] Would run: sudo emerge --ask=n ${missing_build_tools[*]}"
        else
          if ! sudo emerge --ask=n "${missing_build_tools[@]}"; then
            error_exit "Failed to install build tools: ${missing_build_tools[*]}"
          fi
        fi
        log_info "Build tools installed successfully."
      fi
    fi
    ;;
  esac
}

get_package_equivalents() {
  local arch_pkg=$1
  case "$arch_pkg" in
  nemo) echo "gnome-extra/nemo" ;;
  btop) echo "sys-process/btop" ;;
  pavucontrol) echo "media-sound/pavucontrol" ;;
  nvim) echo "app-editors/neovim" ;;
  pyright) echo "dev-python/pyright" ;;
  git) echo "dev-vcs/git" ;;
  hyprland) echo "gui-wm/hyprland" ;;
  xdg-desktop-portal-hyprland) echo "gui-libs/xdg-desktop-portal-hyprland" ;;
  xdg-desktop-portal-gtk) echo "gui-libs/xdg-desktop-portal-gtk" ;;
  hyprpicker) echo "gui-apps/hyprpicker" ;;
  hypridle) echo "gui-apps/hypridle" ;;
  wl-clipboard) echo "gui-apps/wl-clipboard" ;;
  cliphist) echo "gui-apps/cliphist" ;;
  bluez-utils) echo "net-wireless/bluez" ;;
  inotify-tools) echo "sys-fs/inotify-tools" ;;
  wireplumber) echo "media-video/wireplumber" ;;
  trash-cli) echo "app-misc/trash-cli" ;;
  foot) echo "gui-apps/foot" ;;
  fish) echo "app-shells/fish" ;;
  fastfetch) echo "app-misc/fastfetch" ;;
  starship) echo "app-shells/starship" ;;
  jq) echo "app-misc/jq" ;;
  socat) echo "net-misc/socat" ;;
  imagemagick) echo "media-gfx/imagemagick" ;;
  curl) echo "net-misc/curl" ;;
  adw-gtk-theme) echo "x11-themes/adw-gtk3-theme" ;;
  papirus-icon-theme) echo "x11-themes/papirus-icon-theme" ;;
  qt5ct) echo "x11-misc/qt5ct" ;;
  qt6ct) echo "x11-misc/qt6ct" ;;
  ttf-jetbrains-mono-nerd) echo "media-fonts/nerd-fonts" ;;
  noto-fonts-emoji) echo "media-fonts/noto-emoji" ;;
  ttf-joypixels) echo "media-fonts/joypixels" ;;
  ttf-twemoji-color) echo "media-fonts/twemoji-color-font" ;;
  *) echo "$arch_pkg" ;; # fallback to original name
  esac
}

install_main_packages() {
  log_info "Installing main packages..."

  case "$DISTRO" in
  arch)
    local packages=(
      nemo btop pavucontrol nvim pyright git
    )
    ;;
  gentoo)
    local packages=(
      "gnome-extra/nemo"
      "sys-process/btop"
      "media-sound/pavucontrol"
      "app-editors/neovim"
      "dev-python/pyright"
      "dev-vcs/git"
    )
    ;;
  esac

  local missing_pkgs=($(filter_missing_pkgs "${packages[@]}"))

  if [ "${#missing_pkgs[@]}" -eq 0 ]; then
    log_info "All main packages are already installed."
  else
    log_info "Installing packages: ${missing_pkgs[*]}"
    case "$PACKAGE_MANAGER" in
    pacman)
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would run: sudo pacman -S --needed --noconfirm ${missing_pkgs[*]}"
      else
        if ! sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"; then
          error_exit "Failed to install packages: ${missing_pkgs[*]}"
        fi
      fi
      ;;
    portage)
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would run: sudo emerge --ask=n ${missing_pkgs[*]}"
      else
        if ! sudo emerge --ask=n "${missing_pkgs[@]}"; then
          error_exit "Failed to install packages: ${missing_pkgs[*]}"
        fi
      fi
      ;;
    esac
    log_info "Main packages installed successfully."
  fi
}

install_aur_packages() {
  case "$DISTRO" in
  arch)
    install_arch_aur_packages
    ;;
  gentoo)
    install_gentoo_overlay_packages
    ;;
  esac
}

install_arch_aur_packages() {
  # Ensure paru is installed
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

  # Core AUR packages for the Caelestia ecosystem
  aur_packages=(
    caelestia-shell-git caelestia-cli-git
    hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    hyprpicker hypridle wl-clipboard cliphist bluez-utils inotify-tools
    app2unit wireplumber trash-cli foot fish fastfetch starship
    btop jq socat imagemagick curl adw-gtk-theme
    papirus-icon-theme qt5ct qt6ct ttf-jetbrains-mono-nerd
    zen-browser-bin noto-fonts-emoji ttf-joypixels ttf-twemoji-color
    quickshell-git
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

  # Post-installation setup for Caelestia shell
  if pkg_installed "caelestia-shell-git" && command_exists caelestia; then
    log_info "Setting up Caelestia shell..."
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: caelestia install shell"
    else
      if ! caelestia install shell; then
        log_warn "Failed to setup Caelestia shell automatically. You can run 'caelestia install shell' manually."
      else
        log_info "Caelestia shell setup completed."
      fi
    fi
  fi
}

install_gentoo_overlay_packages() {
  log_info "Installing additional packages for Gentoo..."

  # Check if needed overlays are enabled
  local overlays_needed=false

  # Check for guru overlay (needed for some packages)
  if ! eselect repository list | grep -q "guru"; then
    if confirm "Enable guru overlay for additional packages?"; then
      overlays_needed=true
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would run: sudo eselect repository enable guru"
      else
        if ! sudo eselect repository enable guru; then
          log_warn "Failed to enable guru overlay. Some packages may not be available."
        else
          log_info "Guru overlay enabled."
        fi
      fi
    fi
  fi

  # Check for wayland-desktop overlay (needed for Hyprland ecosystem)
  if ! eselect repository list | grep -q "wayland-desktop"; then
    if confirm "Enable wayland-desktop overlay for Hyprland packages?"; then
      overlays_needed=true
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would run: sudo eselect repository enable wayland-desktop"
      else
        if ! sudo eselect repository enable wayland-desktop; then
          log_warn "Failed to enable wayland-desktop overlay."
        else
          log_info "Wayland-desktop overlay enabled."
        fi
      fi
    fi
  fi

  # Sync overlays if any were enabled
  if [ "$overlays_needed" = true ] && [ "$DRY_RUN" = false ]; then
    log_info "Syncing overlays..."
    sudo emerge --sync
  fi

  # Install QuickShell dependencies first (needed for Caelestia shell)
  local quickshell_deps=(
    "dev-qt/qtbase"
    "dev-qt/qtdeclarative"
    "dev-qt/qtwayland"
    "dev-qt/qtsvg"
    "dev-libs/wayland"
    "gui-libs/layer-shell-qt"
    "media-libs/libpulse"
    "sys-apps/dbus"
  )

  log_info "Installing QuickShell dependencies..."
  local missing_qs_deps=($(filter_missing_pkgs "${quickshell_deps[@]}"))

  if [ "${#missing_qs_deps[@]}" -gt 0 ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: sudo emerge --ask=n ${missing_qs_deps[*]}"
    else
      if ! sudo emerge --ask=n "${missing_qs_deps[@]}"; then
        log_error "Failed to install QuickShell dependencies."
      else
        log_info "QuickShell dependencies installed."
      fi
    fi
  fi

  # Main Gentoo packages (equivalents to the AUR packages)
  local gentoo_packages=(
    "gui-wm/hyprland"
    "gui-libs/xdg-desktop-portal-hyprland"
    "gui-libs/xdg-desktop-portal-gtk"
    "gui-apps/wl-clipboard"
    "net-wireless/bluez"
    "sys-fs/inotify-tools"
    "media-video/wireplumber"
    "app-misc/trash-cli"
    "gui-apps/foot"
    "app-shells/fish"
    "app-misc/fastfetch"
    "app-shells/starship"
    "app-misc/jq"
    "net-misc/socat"
    "media-gfx/imagemagick"
    "net-misc/curl"
    "x11-themes/adw-gtk3-theme"
    "x11-themes/papirus-icon-theme"
    "x11-misc/qt5ct"
    "x11-misc/qt6ct"
    "media-fonts/nerd-fonts"
    "media-fonts/noto-emoji"
  )

  local missing_gentoo_pkgs=($(filter_missing_pkgs "${gentoo_packages[@]}"))

  if [ "${#missing_gentoo_pkgs[@]}" -eq 0 ]; then
    log_info "All additional packages are already installed."
  else
    log_info "Additional packages to install: ${missing_gentoo_pkgs[*]}"
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: sudo emerge --ask=n ${missing_gentoo_pkgs[*]}"
    else
      if ! sudo emerge --ask=n "${missing_gentoo_pkgs[@]}"; then
        log_error "Some packages failed to install. Continuing with dotfiles..."
      else
        log_info "Additional packages installed successfully."
      fi
    fi
  fi

  # Install manual packages that need special handling
  install_gentoo_manual_packages
}

install_gentoo_manual_packages() {
  log_info "Installing packages that require manual handling on Gentoo..."

  # Install QuickShell (required for Caelestia shell)
  if ! command_exists quickshell && ! command_exists qs; then
    if confirm "QuickShell not found. Clone and build QuickShell manually?"; then
      log_info "Installing QuickShell from source..."
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would clone and build QuickShell"
      else
        local qs_dir="$TEMP_DIR/quickshell"
        if ! git clone https://github.com/outfoxxed/quickshell.git "$qs_dir"; then
          log_error "Failed to clone QuickShell repository"
          return 1
        fi

        pushd "$qs_dir" >/dev/null || {
          log_error "Failed to enter QuickShell directory"
          return 1
        }

        # Build QuickShell
        if ! cmake -B build -DCMAKE_BUILD_TYPE=Release; then
          popd >/dev/null
          log_error "Failed to configure QuickShell build"
          return 1
        fi

        if ! cmake --build build; then
          popd >/dev/null
          log_error "Failed to build QuickShell"
          return 1
        fi

        if ! sudo cmake --install build; then
          popd >/dev/null
          log_error "Failed to install QuickShell"
          return 1
        fi

        popd >/dev/null
        log_info "QuickShell installed successfully."
      fi
    else
      log_warn "QuickShell is required for Caelestia shell. You may need to install it manually later."
    fi
  fi

  # Install Caelestia CLI manually
  if ! command_exists caelestia; then
    if confirm "Caelestia CLI not found. Clone and install Caelestia CLI manually?"; then
      log_info "Installing Caelestia CLI from source..."
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would clone and build Caelestia CLI"
      else
        # Install Python build dependencies
        local python_deps=("dev-python/build" "dev-python/installer" "dev-python/hatchling")
        local missing_python_deps=($(filter_missing_pkgs "${python_deps[@]}"))

        if [ "${#missing_python_deps[@]}" -gt 0 ]; then
          if ! sudo emerge --ask=n "${missing_python_deps[@]}"; then
            log_error "Failed to install Python build dependencies"
            return 1
          fi
        fi

        local cli_dir="$TEMP_DIR/caelestia-cli"
        if ! git clone https://github.com/caelestia-dots/cli.git "$cli_dir"; then
          log_error "Failed to clone Caelestia CLI repository"
          return 1
        fi

        pushd "$cli_dir" >/dev/null || {
          log_error "Failed to enter Caelestia CLI directory"
          return 1
        }

        # Build and install Caelestia CLI
        if ! python -m build; then
          popd >/dev/null
          log_error "Failed to build Caelestia CLI"
          return 1
        fi

        if ! sudo python -m installer dist/*.whl; then
          popd >/dev/null
          log_error "Failed to install Caelestia CLI"
          return 1
        fi

        popd >/dev/null
        log_info "Caelestia CLI installed successfully."
      fi
    else
      log_warn "Caelestia CLI provides useful utilities. You may want to install it manually later."
    fi
  fi

  # Install Caelestia Shell configuration
  if confirm "Install Caelestia Shell configuration to ~/.config/quickshell/caelestia?"; then
    log_info "Installing Caelestia Shell configuration..."
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would clone Caelestia Shell to ~/.config/quickshell/caelestia"
    else
      local shell_config_dir="$HOME/.config/quickshell/caelestia"

      # Create directory structure
      mkdir -p "$(dirname "$shell_config_dir")"

      # Remove existing directory if it exists
      if [ -d "$shell_config_dir" ]; then
        if confirm "Caelestia shell config already exists. Overwrite?"; then
          rm -rf "$shell_config_dir"
        else
          log_info "Skipping Caelestia shell configuration"
          return 0
        fi
      fi

      if ! git clone https://github.com/caelestia-dots/shell.git "$shell_config_dir"; then
        log_error "Failed to clone Caelestia Shell configuration"
        return 1
      fi

      log_info "Caelestia Shell configuration installed to $shell_config_dir"
      log_info "You can start it with: qs -c caelestia"
    fi
  fi

  # Warn about packages that need alternatives
  echo
  log_warn "Gentoo-specific notes:"
  log_warn "- zen-browser-bin: Not available, consider 'www-client/firefox' or 'www-client/chromium'"
  log_warn "- hyprpicker, hypridle, cliphist: May need manual compilation from source"
  log_warn "- app2unit: Not available, functionality depends on your needs"
  log_warn "- ttf-joypixels, ttf-twemoji-color: May not be in main repo, check overlays"
}

# Check internet connectivity
check_internet() {
  log_info "Checking internet connectivity..."
  if ! ping -c 1 google.com &>/dev/null && ! ping -c 1 8.8.8.8 &>/dev/null; then
    error_exit "No internet connection. Please check your network and try again."
  fi
  log_info "Internet connection verified."
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
    echo
    echo "Supported distributions:"
    echo "  - Arch Linux (with pacman and AUR via paru)"
    echo "  - Gentoo Linux (with portage and overlays)"
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
detect_distro
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
log_info "Detected system: $DISTRO Linux with $PACKAGE_MANAGER"
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
# Install base packages
# -------------------------------
if [ "$SKIP_PACKAGES" = false ]; then
  install_base_packages
fi

# -------------------------------
# Install main packages
# -------------------------------
if [ "$SKIP_PACKAGES" = false ]; then
  install_main_packages
fi

# -------------------------------
# Install AUR/overlay packages
# -------------------------------
if [ "$SKIP_PACKAGES" = false ]; then
  install_aur_packages
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
  fish_path="/usr/bin/fish"

  # Gentoo might install fish in a different location
  if [ "$DISTRO" = "gentoo" ] && [ ! -f "/usr/bin/fish" ]; then
    if [ -f "/bin/fish" ]; then
      fish_path="/bin/fish"
    fi
  fi

  if [ "$current_shell" != "$fish_path" ]; then
    log_info "Changing default shell to fish..."
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: chsh -s $fish_path"
    else
      if ! chsh -s "$fish_path"; then
        log_warn "Failed to change shell to fish. You can change it manually later with: chsh -s $fish_path"
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

log_info "All done! Enjoy your Moxiu T470 dotfiles on $DISTRO Linux."

if [ "$DISTRO" = "gentoo" ]; then
  echo
  log_info "Gentoo-specific post-installation notes:"
  log_info "- If you installed Caelestia shell, start it with: qs -c caelestia"
  log_info "- Consider enabling systemd user service for Caelestia shell"
  log_info "- Some font rendering may require additional configuration"
elif [ "$DISTRO" = "arch" ]; then
  if command_exists caelestia; then
    echo
    log_info "Caelestia shell is installed. You can:"
    log_info "- Start it manually: caelestia shell"
    log_info "- Or with QuickShell directly: qs -c caelestia"
    log_info "- Enable systemd service: systemctl --user enable caelestia-shell.service"
  fi
fi

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
