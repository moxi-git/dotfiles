#!/usr/bin/env bash
set -euo pipefail

# -------------------------------
# Confirmation Functions
# -------------------------------

confirm() {
  while true; do
    read -rp "$1 [Y/n]: " yn
    case "$yn" in
    [Yy] | "") return 0 ;; # Yes or default
    [Nn]) return 1 ;;      # No
    *) echo "Please answer Y or N." ;;
    esac
  done
}

confirm_start() {
  while true; do
    read -rp "Start the installation script? [Y/n]: " yn
    case "$yn" in
    [Yy] | "") break ;; # Proceed
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
  # Safety check: only allow paths inside $HOME
  if [[ "$dest" != "$HOME"* ]]; then
    echo "Refusing to overwrite $dest outside of home directory."
    return 1
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    # Check if it's already a symlink to the intended source
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
      rm -rf "$dest"
      return 0
    else
      echo "Skipping $dest"
      return 1
    fi
  fi
  return 0
}

# -------------------------------
# Welcome & Start Prompt
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
# Variables
# -------------------------------

# Get the directory where this script is located
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------
# Install base-devel
# -------------------------------

if confirm "Install base-devel group packages with pacman?"; then
  sudo pacman -S --needed base-devel
fi

# -------------------------------
# Ensure paru is installed
# -------------------------------

if ! command -v paru &>/dev/null; then
  echo "paru is required for AUR installs."
  if confirm "paru not found. Clone and install paru?"; then
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
    pushd "$tmpdir/paru" >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    rm -rf "$tmpdir"
  else
    echo "paru is required to proceed. Exiting."
    exit 1
  fi
else
  echo "paru is already installed."
fi

# -------------------------------
# Install packages
# -------------------------------

echo
echo "Installing packages and dependencies via paru..."

paru -S --needed --noconfirm \
  caelestia-shell-git \
  caelestia-cli-git \
  hyprland \
  xdg-desktop-portal-hyprland \
  xdg-desktop-portal-gtk \
  hyprpicker \
  hypridle \
  wl-clipboard \
  cliphist \
  bluez-utils \
  inotify-tools \
  app2unit \
  wireplumber \
  trash-cli \
  foot \
  fish \
  fastfetch \
  starship \
  btop \
  jq \
  socat \
  imagemagick \
  curl \
  adw-gtk-theme \
  papirus-icon-theme \
  qt5ct \
  qt6ct \
  ttf-jetbrains-mono-nerd

echo
echo "Packages installed."
echo

# -------------------------------
# Link dotfiles
# -------------------------------

echo "Installing dotfiles from $DOTFILES_DIR to $HOME..."
echo

# Enable dotglob and nullglob to handle hidden files and no-match patterns gracefully
shopt -s dotglob nullglob

for item in "$DOTFILES_DIR"/* "$DOTFILES_DIR"/.[!.]* "$DOTFILES_DIR"/..?*; do
  # Skip if the glob didn't match anything
  [ -e "$item" ] || continue

  base=$(basename "$item")
  # Skip README.md, install.sh, and .git directory
  if [[ "$base" == "README.md" || "$base" == "install.sh" || "$base" == ".git" ]]; then
    continue
  fi

  target="$HOME/$base"

  if confirm_overwrite "$target"; then
    # Use relative symlink from $HOME to $DOTFILES_DIR to improve portability
    rel_target=$(realpath --relative-to="$HOME" "$item")
    ln -s "$rel_target" "$target"
    echo "Linked $item → $target"
  fi
done

shopt -u dotglob nullglob

# -------------------------------
# Done
# -------------------------------

echo
echo "All done! Enjoy your Moxiu T470 dotfiles."
