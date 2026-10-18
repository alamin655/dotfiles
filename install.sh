#!/bin/bash
set -e

echo "🚀 Starting GitHub Codespaces dotfiles setup..."

# 1. Update package lists & install Redis, Node.js, and npm
echo "📦 Checking system packages (Redis, Node.js, npm)..."
sudo apt-get update -y

if ! command -v redis-server &> /dev/null; then
    echo "Installing redis-server..."
    sudo apt-get install -y redis-server
fi
# Ensure Redis is running in the background
sudo service redis-server start || redis-server --daemonize yes

if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo "Installing Node.js and npm..."
    sudo apt-get install -y nodejs npm
fi

# 2. Install Rust & Cargo
if ! command -v rustup &> /dev/null; then
    echo "🦀 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "🦀 Rust is already installed."
    source "$HOME/.cargo/env" 2>/dev/null || true
fi

# Add essential Rust components
rustup component add clippy rustfmt rust-src

# 3. Install Google Antigravity CLI (agy)
if ! command -v agy &> /dev/null && [ ! -f "$HOME/.local/bin/agy" ]; then
    echo "🌌 Installing Antigravity CLI (agy)..."
    curl -fsSL https://antigravity.google/cli/install.sh | bash
else
    echo "🌌 Antigravity CLI is already installed."
fi

# Ensure ~/.local/bin and ~/.cargo/bin are in PATH for bash/zsh sessions
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        grep -qxF 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "$rc" || \
            echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "$rc"
    fi
done

# 4. Install VS Code Extensions for Rust & Development
GLOBAL_EXTENSIONS=(
    # Core Rust
    "rust-lang.rust-analyzer"       # Rust language server
    "vadimcn.vscode-lldb"           # CodeLLDB debugger for Rust
    "tamasfe.even-better-toml"      # Full-featured Cargo.toml / TOML support
    "fill-labs.dependi"             # Manage Cargo/npm dependencies (replaces deprecated 'crates')
    "serayuzgur.crates"             # Legacy Crates.io helper (kept if preferred)
    "swellaby.rust-pack"            # Convenient Rust extension bundle
    
    # DX & Error Handling
    "usernamehw.errorlens"          # Inline compiler & clippy error highlighting
    "JScearcy.rust-doc-viewer"      # Preview cargo doc directly inside VS Code
)

if command -v code &> /dev/null; then
    echo "🧩 Installing VS Code extensions..."
    for ext in "${GLOBAL_EXTENSIONS[@]}"; do
        code --install-extension "$ext" --force || echo "⚠️ Failed to install $ext"
    done
else
    echo "ℹ️ 'code' CLI not found in current PATH. Skipping extension install."
fi

echo "✅ Dotfiles setup complete!"
