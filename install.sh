#!/bin/bash

echo "🚀 Starting GitHub Codespaces dotfiles setup..."

# Avoid interactive prompts during apt-get
export DEBIAN_FRONTEND=noninteractive

# 1. Update package lists & install Redis, Node.js, and npm
echo "📦 Checking system packages (Redis, Node.js, npm)..."
sudo apt-get update -y

if ! command -v redis-server &> /dev/null; then
    echo "Installing redis-server..."
    sudo apt-get install -y redis-server
fi
sudo service redis-server start || redis-server --daemonize yes || true

if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo "Installing Node.js and npm..."
    sudo apt-get install -y nodejs npm
fi

# 2. Install Rust & Cargo (using direct sh.rustup.rs endpoint + -L for redirects)
if ! command -v rustup &> /dev/null && [ ! -f "$HOME/.cargo/bin/rustup" ]; then
    echo "🦀 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSfL https://sh.rustup.rs | sh -s -- -y
fi

# Load Cargo environment into current script session
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi

# Verify Rust installed before adding components
if command -v rustup &> /dev/null; then
    echo "🔧 Adding Rust components (clippy, rustfmt, rust-src)..."
    rustup component add clippy rustfmt rust-src || true
fi

# 3. Install Google Antigravity CLI (agy)
if ! command -v agy &> /dev/null && [ ! -f "$HOME/.local/bin/agy" ]; then
    echo "🌌 Installing Antigravity CLI (agy)..."
    curl -fsSL https://antigravity.google/cli/install.sh | bash || echo "⚠️ Antigravity CLI install skipped/failed"
fi

# Ensure ~/.local/bin and ~/.cargo/bin are in PATH for future bash/zsh terminals
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        grep -qxF 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' "$rc" || \
            echo 'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' >> "$rc"
    fi
done

# 4. Install VS Code Extensions
GLOBAL_EXTENSIONS=(
    "rust-lang.rust-analyzer"
    "vadimcn.vscode-lldb"
    "tamasfe.even-better-toml"
    "fill-labs.dependi"
    "serayuzgur.crates"
    "swellaby.rust-pack"
    "usernamehw.errorlens"
    "JScearcy.rust-doc-viewer"
)

# Find the active VS Code CLI binary (either in PATH or inside .vscode-remote)
CODE_BIN=""
if command -v code &> /dev/null; then
    CODE_BIN="code"
elif command -v code-insiders &> /dev/null; then
    CODE_BIN="code-insiders"
else
    # Search for the remote server CLI if dotfiles ran before the UI attached
    CODE_BIN=$(find /vscode /workspaces/.codespaces "$HOME/.vscode-server" "$HOME/.vscode-remote" -name "code" -type f -executable 2>/dev/null | head -n 1)
fi

install_extensions() {
    local bin="$1"
    for ext in "${GLOBAL_EXTENSIONS[@]}"; do
        "$bin" --install-extension "$ext" --force || echo "⚠️ Could not install $ext"
    done
}

if [ -n "$CODE_BIN" ]; then
    echo "🧩 Installing VS Code extensions using $CODE_BIN..."
    install_extensions "$CODE_BIN"
else
    echo "⏳ VS Code server not attached yet. Spawning background watcher to install extensions once connected..."
    nohup bash -c '
        for i in {1..30}; do
            BIN=$(command -v code || find /vscode "$HOME/.vscode-server" "$HOME/.vscode-remote" -name "code" -type f -executable 2>/dev/null | head -n 1)
            if [ -n "$BIN" ]; then
                for ext in "rust-lang.rust-analyzer" "vadimcn.vscode-lldb" "tamasfe.even-better-toml" "fill-labs.dependi" "serayuzgur.crates" "swellaby.rust-pack" "usernamehw.errorlens" "JScearcy.rust-doc-viewer"; do
                    "$BIN" --install-extension "$ext" --force
                done
                break
            fi
            sleep 5
        done
    ' >/tmp/vscode-ext-install.log 2>&1 &
fi

echo "✅ Dotfiles setup complete!"
