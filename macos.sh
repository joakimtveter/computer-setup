#!/usr/bin/env bash
set -e  # Exit immediately if a command fails

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Check if running on macOS 26 or newer
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script is designed for macOS only."
    exit 1
fi

MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_VERSION" -lt 26 ]]; then
    log_error "This script requires macOS 26 or newer. You are running macOS $MACOS_VERSION."
    exit 1
fi
log_info "Starting macOS setup..."

# Prompt for setup type
echo ""
echo -e "${BLUE}ℹ️  Is this a work or personal laptop?${NC}"
echo "  1) Personal"
echo "  2) Work"
read -rp "Choose [1/2]: " SETUP_TYPE
echo ""

IS_WORK=false

echo -e "${BLUE}ℹ️  Please enter your email address (default: joakim@tveter.net):${NC}"
read -r USER_EMAIL
if [[ -z "$USER_EMAIL" ]]; then
    USER_EMAIL="joakim@tveter.net"
fi
log_success "Email set to: $USER_EMAIL"

if [[ "$SETUP_TYPE" == "2" ]]; then
    IS_WORK=true
    log_info "Setting up as a WORK laptop"
else
    log_info "Setting up as a PERSONAL laptop"
fi
echo ""

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

safe_source() {
    if [[ -f "$1" ]]; then
        set +e
        source "$1"
        set -e
    fi
}

# Install Homebrew
if command_exists brew; then
    log_success "Homebrew is already installed at: $(which brew)"
else
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    log_success "Homebrew installation complete."
fi

# Determine Homebrew path based on architecture
if [[ -d "/opt/homebrew/bin" ]]; then
    BREW_PATH="/opt/homebrew/bin"
elif [[ -d "/usr/local/bin" ]]; then
    BREW_PATH="/usr/local/bin"
else
    log_error "Could not find Homebrew installation path"
    exit 1
fi

# Add Homebrew to PATH in shell config files
for shell_config in ~/.zshrc ~/.bash_profile ~/.bashrc; do
    # Only modify .zshrc by default, others only if they exist
    if [[ "$shell_config" == ~/.zshrc ]] || [[ -f "$shell_config" ]]; then
        if [[ -f "$shell_config" ]] && ! grep -q "$BREW_PATH" "$shell_config"; then
            echo "export PATH=\"$BREW_PATH:\$PATH\"" >> "$shell_config"
            log_success "Added Homebrew to PATH in $shell_config"
        elif [[ "$shell_config" == ~/.zshrc ]] && [[ ! -f "$shell_config" ]]; then
            echo "export PATH=\"$BREW_PATH:\$PATH\"" > "$shell_config"
            log_success "Created $shell_config and added Homebrew to PATH"
        fi
    fi
done

# Make brew available for the current session
export PATH="$BREW_PATH:$PATH"

# Reload shell config
safe_source ~/.zshrc
log_success "Shell configuration reloaded — Homebrew is now available"

# Install Oh My Zsh
if [[ -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
    log_success "Oh My Zsh is already installed."
else
    log_info "Installing Oh My Zsh..."
    # Backup existing .zshrc if it exists
    if [[ -f ~/.zshrc ]]; then
        cp ~/.zshrc ~/.zshrc.backup."$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing .zshrc"
    fi
    
    RUNZSH=no  # prevents the installer from launching a new zsh session
    CHSH=no    # prevents it from changing the default shell
    export RUNZSH CHSH
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    sed -i '' 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' ~/.zshrc

    # Install zsh plugins
    ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
    git clone https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM_DIR/plugins/zsh-completions"
    sed -i '' 's/plugins=(git)/plugins=(git zsh-syntax-highlighting zsh-autosuggestions zsh-completions)/' ~/.zshrc
    log_success "Oh My Zsh installation complete (theme: agnoster, plugins: zsh-syntax-highlighting, zsh-autosuggestions, zsh-completions)."
fi

# Install NVM + Node.js
if [[ -d "$HOME/.nvm" ]]; then
    log_success "NVM is already installed."
else
    log_info "Installing NVM..."
    # Install specific version for reproducibility
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    log_success "NVM installation complete."
    
    # Ensure NVM is loaded in shell config
    NVM_CONFIG='# NVM Configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Auto nvm use
autoload -U add-zsh-hook
load-nvmrc() {
  local nvmrc_path
  nvmrc_path="$(nvm_find_nvmrc)"
  if [ -n "$nvmrc_path" ]; then
    local nvmrc_node_version
    nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")
    if [ "$nvmrc_node_version" = "N/A" ]; then
      nvm install
    elif [ "$nvmrc_node_version" != "$(nvm version)" ]; then
      nvm use
    fi
  elif [ -n "$(PWD=$OLDPWD nvm_find_nvmrc)" ] && [ "$(nvm version)" != "$(nvm version default)" ]; then
    echo "Reverting to nvm default version"
    nvm use default
  fi
}
add-zsh-hook chpwd load-nvmrc
load-nvmrc'
    
    if ! grep -q 'NVM_DIR' ~/.zshrc; then
        echo "$NVM_CONFIG" >> ~/.zshrc
        log_success "Added NVM configuration and auto-use functionality to ~/.zshrc"
    fi
fi

# Load NVM for current session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install latest LTS version of Node.js
if type nvm &>/dev/null; then
    if command_exists node && nvm version default &>/dev/null; then
        log_success "Node.js $(node -v) is already installed (npm $(npm -v))"
    else
        log_info "Installing latest LTS version of Node.js with NVM..."
        nvm install --lts --latest-npm
        nvm alias default 'lts/*'
        nvm use default
        log_success "Installed Node.js $(node -v) and npm $(npm -v), set as default."
    fi
else
    log_warning "NVM not found in current session — Node.js installation skipped."
    log_info "You may need to restart your terminal and run: nvm install --lts"
fi

### --- Install Apps via Homebrew ---
log_info "Installing applications with Homebrew..."

# Update Homebrew first
brew update || log_warning "Failed to update Homebrew"

# Common apps for both setups
declare -a cask_apps=(
    "colour-contrast-analyser"
    "docker-desktop"
    "espanso"
    "ghostty"
    "google-chrome"
    "iterm2"
    "notunes"
    "postman"
    "proton-pass"
    "raycast"
    "spotify"
    "vivaldi"
    "webstorm"
)

if [[ "$IS_WORK" == true ]]; then
    # Work-specific apps
    cask_apps+=(
#       "dbeaver-community"
#       "displaylink"
#       "figma"
        "microsoft-teams"
        "microsoft-outlook"
#       "rider"
    )
else
    # Personal-specific apps
    cask_apps+=(
        "claude-code"
        "logi-options+"
        "protonvpn"
        "proton-drive"
        "proton-mail"
    )
fi

# Install each cask app
for app in "${cask_apps[@]}"; do
    if brew list --cask "$app" &>/dev/null; then
        log_success "$app is already installed"
    else
        log_info "Installing $app..."
        if brew install --cask "$app"; then
            log_success "Successfully installed $app"
        else
            log_error "Failed to install $app"
        fi
    fi
done

# Optional: Install some useful CLI tools
log_info "Installing useful CLI tools..."
declare -a cli_tools=(
    "python"
    "pnpm"
    "git"
    "curl"
    "wget"
    "jq"
    "tree"
    "imagemagick"
    "ripgrep"
    "fzf"
    "zoxide"
    "mas"
    "mpv"
    "ffmpeg"
)

for tool in "${cli_tools[@]}"; do
    if brew list "$tool" &>/dev/null || command_exists "$tool"; then
        log_success "$tool is already available"
    else
        log_info "Installing $tool..."
        if brew install "$tool"; then
            log_success "Successfully installed $tool"
        else
            log_warning "Failed to install $tool"
        fi
    fi
done

# Install Mac App Store apps using mas
if command_exists mas; then
    log_info "Installing Mac App Store applications..."

    # Check if signed into Mac App Store
    if mas account &>/dev/null; then
        log_success "Signed into Mac App Store"

        # Array of Mac App Store apps (format: "app_id:app_name")
        declare -a mas_apps=(
            "1596283165:rcmd"
        )

        for entry in "${mas_apps[@]}"; do
            app_id="${entry%%:*}"
            app_name="${entry##*:}"

            if mas list | grep -q "^$app_id"; then
                log_success "$app_name is already installed"
            else
                log_info "Installing $app_name from Mac App Store..."
                if mas install "$app_id"; then
                    log_success "Successfully installed $app_name"
                else
                    log_error "Failed to install $app_name"
                fi
            fi
        done
    else
        log_warning "Not signed into Mac App Store — skipping App Store installations"
        log_info "Sign in to the App Store..."
    fi
else
    log_warning "mas not available — skipping Mac App Store installations"
fi

# Create development directory structure
log_info "Creating development directory structure..."
CODE_DIR="$HOME/Code"
mkdir -p "$CODE_DIR"

log_success "Created development directory:"
log_info "  📁 ~/Code"

# Configure Git
log_info "Configuring Git..."
if command_exists git; then
    git config --global user.name "Joakim Tveter"
    log_success "Set global Git name to: Joakim Tveter"

    git config --global user.email "$USER_EMAIL"
    log_success "Set global Git email to: $USER_EMAIL"

    log_info "Git configuration complete:"
    log_info "  👤 Global name: Joakim Tveter"
    log_info "  📧 Email: $USER_EMAIL"
else
    log_warning "Git not found - skipping Git configuration"
fi

# Configure macOS Settings
log_info "Configuring macOS settings..."

# Dock: Auto-hide
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -int 0
log_success "Dock: Auto-hide enabled, no delay or animation"
defaults write com.apple.dock tilesize -int 32
log_success "Dock: Resize the dock"
defaults write com.apple.dock show-recents -bool false
log_success "Dock: Remove resent applications"
defaults write com.apple.dock minimize-to-application -bool true
log_success "Dock: Minimize windows into application icon"
defaults write com.apple.dock mineffect -string "scale"
log_success "Dock: Set minimize animation to scale effect"
killall Dock

defaults write -g AppleShowAllExtensions -bool true
log_success "Finder: Show file extensions"
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder ShowPathbar -bool true
log_success "Finder: Show path bar and status bar"

killall Finder;

log_success "macOS settings configured"

log_success "Setup complete! Your Mac is ready to go 🚀"
log_info "Restart your terminal or run 'source ~/.zshrc' to ensure all changes take effect."

# Display versions of installed tools
echo ""
log_info "Installed versions:"
command_exists brew && echo "  Homebrew: $(brew --version | head -n1)"
command_exists node && echo "  Node.js: $(node -v)"
command_exists npm && echo "  npm: $(npm -v)"
command_exists git && echo "  Git: $(git --version)"
command_exists claude && echo "  Claude Code: $(claude --version)"
