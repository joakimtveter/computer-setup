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

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script is designed for macOS only."
    exit 1
fi

log_info "Starting macOS setup..."

# Prompt for work email
echo ""
echo -e "${BLUE}ℹ️  Please enter your work email address (or press Enter to skip):${NC}"
read -r WORK_EMAIL
if [[ -z "$WORK_EMAIL" ]]; then
    log_warning "No work email provided, work git config will be skipped"
else
    log_success "Work email set to: $WORK_EMAIL"
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
        cp ~/.zshrc ~/.zshrc.backup.$(date +%Y%m%d_%H%M%S)
        log_info "Backed up existing .zshrc"
    fi
    
    RUNZSH=no  # prevents the installer from launching a new zsh session
    CHSH=no    # prevents it from changing the default shell
    export RUNZSH CHSH
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    log_success "Oh My Zsh installation complete."
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
# NVM is a shell function, not a command, so we check if the function exists
if type nvm &>/dev/null; then
    log_info "Installing latest LTS version of Node.js with NVM..."
    nvm install --lts --latest-npm
    nvm alias default lts/*
    nvm use default
    log_success "Installed Node.js $(node -v) and npm $(npm -v), set as default."
else
    log_warning "NVM not found in current session — Node.js installation skipped."
    log_info "You may need to restart your terminal and run: nvm install --lts"
fi

# Install Claude Code CLI
if command_exists npm; then
    if command_exists claude; then
        log_success "Claude Code is already installed"
    else
        log_info "Installing Claude Code CLI..."
        if npm install -g @anthropic-ai/claude-code; then
            log_success "Successfully installed Claude Code"
        else
            log_error "Failed to install Claude Code"
        fi
    fi
else
    log_warning "npm not available — Claude Code installation skipped."
fi

### --- Install Apps via Homebrew ---
log_info "Installing applications with Homebrew..."

# Update Homebrew first
brew update || log_warning "Failed to update Homebrew"

# Array of cask apps to install
declare -a cask_apps=(
    "raycast"
    "vivaldi"
    "google-chrome"
    "ghostty"
    "postman"
    "dbeaver-community"
    "obsidian"
    "espanso"
    "docker-desktop"
    "microsoft-teams"
    "microsoft-outlook"
    "notunes"
#    Optional Work Stuff
#    "displaylink"
#    "omnissa-horizon-client"
#    "bitwarden"
)

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
CODE_DIR="$HOME/code"
if [[ ! -d "$CODE_DIR" ]]; then
    mkdir -p "$CODE_DIR"/{work,personal}
    log_success "Created development directories:"
    log_info "  📁 ~/code/work"
    log_info "  📁 ~/code/personal"
else
    # Create subdirectories if they don't exist
    [[ ! -d "$CODE_DIR/work" ]] && mkdir -p "$CODE_DIR/work" && log_success "Created ~/code/work directory"
    [[ ! -d "$CODE_DIR/personal" ]] && mkdir -p "$CODE_DIR/personal" && log_success "Created ~/code/personal directory"
    log_info "Development directory structure verified"
fi

# Configure Git
log_info "Configuring Git..."
if command_exists git; then
    # Set global git name
    git config --global user.name "Joakim Tveter"
    log_success "Set global Git name to: Joakim Tveter"

    # Configure work folder git email using conditional includes
    WORK_GITCONFIG="$CODE_DIR/work/.gitconfig"
    if [[ -n "$WORK_EMAIL" ]]; then
        cat > "$WORK_GITCONFIG" << EOF
[user]
    email = $WORK_EMAIL
EOF
        log_success "Created work-specific Git config: $WORK_GITCONFIG"
    fi
    
    # Configure personal folder git email using conditional includes
    PERSONAL_GITCONFIG="$CODE_DIR/personal/.gitconfig"
    cat > "$PERSONAL_GITCONFIG" << EOF
[user]
    email = joakim@tveter.net
EOF
    log_success "Created personal-specific Git config: $PERSONAL_GITCONFIG"
    
    # Update global gitconfig to include conditional configs
    GLOBAL_GITCONFIG="$HOME/.gitconfig"
    
    # Set a default email for repositories outside work/personal directories
    if ! git config --global user.email &>/dev/null; then
        git config --global user.email "joakim@tveter.net"
        log_success "Set default Git email to: joakim@tveter.net"
    fi

    # Check if conditional includes are already configured
    if ! grep -q "includeIf.*gitdir:.*code/work" "$GLOBAL_GITCONFIG" 2>/dev/null; then
        cat >> "$GLOBAL_GITCONFIG" << EOF

[includeIf "gitdir:~/code/work/"]
    path = ~/code/work/.gitconfig

[includeIf "gitdir:~/code/personal/"]
    path = ~/code/personal/.gitconfig
EOF
        log_success "Added conditional Git config includes to ~/.gitconfig"
    else
        log_info "Git conditional includes already configured"
    fi
    
    log_info "Git configuration complete:"
    log_info "  👤 Global name: Joakim Tveter"
    log_info "  📧 Default email: joakim@tveter.net"
    [[ -n "$WORK_EMAIL" ]] && log_info "  📧 Work email (~/code/work/*): $WORK_EMAIL"
    log_info "  📧 Personal email (~/code/personal/*): joakim@tveter.net"
else
    log_warning "Git not found - skipping Git configuration"
fi

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
