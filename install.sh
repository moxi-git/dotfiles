#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# Default flags
# -------------------------------
AUTO_YES=false
SKIP_DOTS=false
SKIP_PACKAGES=false
DRY_RUN=false
VERBOSE=false

# -------------------------------
# Helpers
# -------------------------------
command_exists() {
  command -v "$1" &>/dev/null
}

log() {
  if [ "$VERBOSE" = true ]; then
    echo "$@"
  fi
}

# realpath fallback
realpath_rel() {
  if command_exists realpath; then
    realpath --relative-to="$HOME" "$1"
  else
    # fallback: try python3
    if command_exists python3; then
      python3 -c "import os.path; print(os.path.relpath('$1', '$HOME'))"
    else
      # fallback: absolute path (not ideal)
      echo "$1"
    fi
  fi
}

# Check if package is installed (supports pacman & paru)
pkg_installed() {
  local pkg=$1
  if command_exists pacman; then
    pacman -Qq "$pkg" &>/dev/null && return 0 || return 1
  else
    return 1
  fi
}

# Filter missing packages from list
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

# -------------------------------
# Parse command-line arguments
# -------------------------------
for arg in "$@"; do
  case "$arg" in
  -y | --yes) AUTO_YES=true ;;
  --no-dots) SKIP_DOTS=true ;;
  --no-packages) SKIP_PACKAGES=true ;;
  --dry-run) DRY_RUN=true ;;
  -v | --verbose) VERBOSE=true ;;
  -h | --help)
    echo "Usage: ./install.sh [options]"
    echo
    echo "Options:"
    echo "  -y, --yes         Automatically confirm all prompts"
    echo "      --no-dots     Skip dotfile linking"
    echo "      --no-packages Skip package installation"
    echo "      --dry-run     Show actions without performing them"
    echo "  -v, --verbose     Enable verbose output"
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
  if [ "$AUTO_YES" = true ] || [ "$DRY_RUN" = true ]; then
    return 0
  fi
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
  if [ "$AUTO_YES" = true ] || [ "$DRY_RUN" = true ]; then
    return
  fi
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
    echo "Refusing to overwrite $dest outside of home directory."
    return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ]; then
      local link_target
      link_target=$(readlink "$dest")
      if [[ "$link_target" == "$DOTFILES_DIR/"* ]]; then
        echo "$dest is already correctly linked. Skipping."
        return 1
      fi
    fi
    echo
    echo "Warning: $dest already exists and will be removed if you choose to overwrite."
    if confirm "Overwrite $dest?"; then
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would remove $dest"
      else
        rm -rf "$dest"
      fi
      return 0
    else
      echo "Skipping $dest"
      return 1
    fi
  fi
  return 0
}

# -------------------------------
# Root check and warn
# -------------------------------
if [ "$EUID" -eq 0 ]; then
  echo "Warning: Running the installer as root is not recommended."
  echo "Some commands require sudo, but the script should be run as a normal user."
  if ! confirm "Continue as root?"; then
    exit 1
  fi
fi

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
echo "Welcome to the Moxiu T470 dotfiles installer!"
echo

confirm_start

# -------------------------------
# Paths & Preparation
# -------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------
# Install base-devel
# -------------------------------
if [ "$SKIP_PACKAGES" = false ] && confirm "Install base-devel group packages with pacman?"; then
  if [ "$DRY_RUN" = true ]; then
    echo "[Dry-run] Would run: sudo pacman -S --needed base-devel"
  else
    log "Running: sudo pacman -S --needed base-devel"
    sudo pacman -S --needed base-devel
  fi
fi

# -------------------------------
# Ensure paru is installed
# -------------------------------
if [ "$SKIP_PACKAGES" = false ]; then
  if ! command_exists paru; then
    echo "paru is required for AUR installs."
    if confirm "paru not found. Clone and install paru?"; then
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would clone paru repo and build it"
      else
        tmpdir=$(mktemp -d)
        log "Cloning paru into $tmpdir/paru"
        git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
        pushd "$tmpdir/paru" >/dev/null
        log "Building paru package"
        makepkg -si --noconfirm
        popd >/dev/null
        rm -rf "$tmpdir"
      fi
    else
      echo "paru is required to proceed. Exiting."
      exit 1
    fi
  else
    echo "paru is already installed."
  fi

  echo
  echo "Installing packages and dependencies via paru..."

  # List of desired packages
  packages=(
    caelestia-shell-git
    caelestia-cli-git
    hyprland
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    hyprpicker
    hypridle
    wl-clipboard
    cliphist
    bluez-utils
    inotify-tools
    app2unit
    wireplumber
    trash-cli
    foot
    fish
    fastfetch
    starship
    btop
    jq
    socat
    imagemagick
    curl
    adw-gtk-theme
    papirus-icon-theme
    qt5ct
    qt6ct
    ttf-jetbrains-mono-nerd
  )

  # Filter only missing packages to speed up install
  missing_pkgs=($(filter_missing_pkgs "${packages[@]}"))

  if [ "${#missing_pkgs[@]}" -eq 0 ]; then
    echo "All packages are already installed."
  else
    echo "Packages to install: ${missing_pkgs[*]}"
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would run: paru -S --needed --noconfirm ${missing_pkgs[*]}"
    else
      log "Running: paru -S --needed --noconfirm ${missing_pkgs[*]}"
      paru -S --needed --noconfirm "${missing_pkgs[@]}"
    fi
  fi

  echo
  echo "Packages installed."
  echo
fi

# -------------------------------
# Link dotfiles
# -------------------------------
if [ "$SKIP_DOTS" = false ]; then
  echo "Installing dotfiles from $DOTFILES_DIR to $HOME..."
  echo

  shopt -s dotglob nullglob

  for item in "$DOTFILES_DIR"/* "$DOTFILES_DIR"/.[!.]* "$DOTFILES_DIR"/..?*; do
    [ -e "$item" ] || continue

    base=$(basename "$item")
    if [[ "$base" == "README.md" || "$base" == "install.sh" || "$base" == ".git" ]]; then
      continue
    fi

    target="$HOME/$base"

    if confirm_overwrite "$target"; then
      rel_target=$(realpath_rel "$item")
      if [ "$DRY_RUN" = true ]; then
        echo "[Dry-run] Would link $item → $target (relative: $rel_target)"
      else
        ln -sfn "$rel_target" "$target"
        echo "Linked $item → $target"
      fi
    fi
  done

  shopt -u dotglob nullglob
fi

echo
echo "All done! Enjoy your Moxiu T470 dotfiles."
if [ "$DRY_RUN" = true ]; then
  echo "[Dry-run] No changes were actually made."
fi

# -------------------------------
# Change shell to fish (if installed)
# -------------------------------
if command_exists /usr/bin/fish; then
  echo "Changing default shell to /usr/bin/fish..."
  if [ "$DRY_RUN" = true ]; then
    echo "[Dry-run] Would run: chsh -s /usr/bin/fish"
  else
    chsh -s /usr/bin/fish && echo "Default shell changed to fish."
  fi
else
  echo "Fish shell (/usr/bin/fish) not found. Skipping shell change."
fi

# -------------------------------
# Reboot prompt
# -------------------------------
while true; do
  read -rp "Reboot (Highly Recommended!) [Y/n]: " yn
  case "$yn" in
  [Yy] | "")
    echo "Rebooting..."
    if [ "$DRY_RUN" = true ]; then
      echo "[Dry-run] Would reboot now"
    else
      sudo reboot
    fi
    break
    ;;
  [Nn])
    echo "Please reboot later to apply all changes."
    break
    ;;
  *) echo "Please answer Y or N." ;;
  esac
done
