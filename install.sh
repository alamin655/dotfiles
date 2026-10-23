#!/usr/bin/env bash
#
# GitHub Codespaces dotfiles installer
#   - Redis (installed + started, headless-safe)
#   - Node.js + npm (reuses the image's nvm toolchain, apt only as fallback)
#   - Rust toolchain + clippy / rustfmt / rust-src
#   - Google Antigravity CLI (agy)
#   - VS Code extensions (installed now, or retried in the background until
#     the VS Code server is attached)
#
set -uo pipefail

echo "🚀 Starting GitHub Codespaces dotfiles setup..."

# Avoid interactive prompts during apt-get
export DEBIAN_FRONTEND=noninteractive

# Use sudo only when needed; works both in Codespaces (passwordless sudo)
# and when the script happens to run as root.
SUDO=()
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
fi

have() { command -v "$1" >/dev/null 2>&1; }

apt_get() {
    "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive \
        apt-get -y -o Dpkg::Options::=--force-confold "$@"
}

# Canonical PATH line, used both for this shell and for future shells
# shellcheck disable=SC2016
PATH_LINE='export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"'
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

redis_up() {
    local reply
    have redis-cli || return 1
    reply="$(timeout 2 redis-cli ping 2>/dev/null)" || return 1
    case "$reply" in
        *PONG*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 1. System packages: Redis, Node.js, npm
# ---------------------------------------------------------------------------
echo "📦 Checking system packages (Redis, Node.js, npm)..."

if ! have apt-get; then
    echo "⚠️ apt-get not found; skipping system packages (not a Debian-based image?)"
else
    apt_get update || echo "⚠️ apt-get update failed; continuing with cached package lists"

    if ! have redis-server; then
        echo "Installing redis-server..."
        apt_get install redis-server || echo "⚠️ Could not install redis-server"
    fi

    # Reuse the Node toolchain that already ships with the Codespaces image
    # (nvm) before falling back to apt: `apt-get install npm` pulls in an old
    # Node that can shadow the nvm-managed one.
    nvm_sh=""
    for candidate in "${NVM_DIR:-$HOME/.nvm}/nvm.sh" /usr/local/share/nvm/nvm.sh; do
        if [ -s "$candidate" ]; then
            nvm_sh="$candidate"
            break
        fi
    done
    if [ -n "$nvm_sh" ]; then
        set +u
        # shellcheck disable=SC1090
        . "$nvm_sh" >/dev/null 2>&1 || true
        set -u
    fi

    if ! have node; then
        # nvm installs live under versions/node/*/bin; pick the newest one.
        node_bin="$(find "$HOME/.nvm/versions/node" /usr/local/share/nvm/versions/node \
            -maxdepth 2 -type d -name bin 2>/dev/null | sort -V | tail -n 1)"
        if [ -n "$node_bin" ] && [ -x "$node_bin/node" ]; then
            PATH="$node_bin:$PATH"
            export PATH
        fi
    fi

    if ! have node; then
        echo "Installing Node.js and npm (apt fallback)..."
        apt_get install nodejs npm || echo "⚠️ Could not install Node.js/npm"
    fi
fi

# Start Redis (no systemd in Codespaces containers, so fall back to a
# daemonized server with an explicit log/dir we are allowed to write to)
if have redis-server; then
    if redis_up; then
        echo "✅ Redis already running"
    else
        "${SUDO[@]}" service redis-server start >/dev/null 2>&1 \
            || redis-server --daemonize yes --dir /tmp --logfile /tmp/redis-server.log >/dev/null 2>&1 \
            || echo "⚠️ Could not start redis-server"
        if redis_up; then
            echo "✅ Redis started"
        else
            echo "⚠️ Redis installed but not responding yet"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 2. Rust toolchain
# ---------------------------------------------------------------------------
if ! have rustup && [ ! -x "$HOME/.cargo/bin/rustup" ]; then
    echo "🦀 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSfL https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path \
        || echo "⚠️ Rust installation failed"
fi

# rustup writes ~/.cargo/env; load it so cargo/rustc work in this session
if [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
fi

if have rustup; then
    echo "🔧 Adding Rust components (clippy, rustfmt, rust-src)..."
    rustup component add clippy rustfmt rust-src \
        || echo "⚠️ Could not add some Rust components"
fi

# ---------------------------------------------------------------------------
# 3. Google Antigravity CLI (agy) — installs the binary into ~/.local/bin
# ---------------------------------------------------------------------------
if ! have agy && [ ! -x "$HOME/.local/bin/agy" ]; then
    echo "🌌 Installing Antigravity CLI (agy)..."
    mkdir -p "$HOME/.local/bin"
    curl --proto '=https' --tlsv1.2 -fsSL https://antigravity.google/cli/install.sh | bash \
        || echo "⚠️ Antigravity CLI install skipped/failed"
fi

# ---------------------------------------------------------------------------
# 4. Persist PATH for future shells
# ---------------------------------------------------------------------------
append_line() {
    local file="$1" line="$2"
    touch "$file" 2>/dev/null || return 0
    grep -qxF "$line" "$file" && return 0
    # don't glue the new line onto an existing one without a trailing newline
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then
        printf '\n' >> "$file"
    fi
    printf '%s\n' "$line" >> "$file"
}

rc_files=("$HOME/.bashrc")
if have zsh; then
    rc_files+=("$HOME/.zshrc")
fi
for rc in "${rc_files[@]}"; do
    append_line "$rc" "$PATH_LINE"
done

# ---------------------------------------------------------------------------
# 5. VS Code extensions
# ---------------------------------------------------------------------------
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

# List every VS Code CLI we could use. `code` is the normal CLI, but in
# Codespaces it only works once a client is attached; the server's own
# `code-server` binary can install extensions without any client.
find_code_clis() {
    local c glob
    for c in code code-insiders; do
        if command -v "$c" >/dev/null 2>&1; then
            command -v "$c"
        fi
    done
    for glob in \
        "/vscode/bin/code-server" \
        "$HOME/.vscode-server/bin/"*/bin/code-server \
        "$HOME/.vscode-remote/bin/"*/bin/code-server \
        "/vscode/bin/remote-cli/code" \
        "$HOME/.vscode-server/bin/"*/bin/remote-cli/code \
        "$HOME/.vscode-remote/bin/"*/bin/remote-cli/code
    do
        [ -x "$glob" ] && printf '%s\n' "$glob"
    done
    return 0
}

# Try every candidate CLI until one installs the whole list.
# Returns 0 = all installed, 1 = a CLI exists but an install failed,
#         2 = no VS Code CLI available (server not attached yet)
install_extensions() {
    local bin ext
    local -a bins=() failed=()
    mapfile -t bins < <(find_code_clis)
    if [ "${#bins[@]}" -eq 0 ]; then
        echo "⚠️ No VS Code CLI found"
        return 2
    fi
    for bin in "${bins[@]}"; do
        failed=()
        for ext in "$@"; do
            "$bin" --install-extension "$ext" --force >/dev/null 2>&1 \
                || failed+=("$ext")
        done
        if [ "${#failed[@]}" -eq 0 ]; then
            echo "🧩 VS Code extensions installed via $bin"
            return 0
        fi
        echo "⚠️ $bin could not install: ${failed[*]}"
    done
    return 1
}

# Spawn a detached retry loop that waits for the VS Code server and then
# installs the extensions. The helper script is generated with the functions
# above so there is no duplicated extension list or copy-pasted logic.
start_extension_watcher() {
    local helper log
    helper="$(mktemp "${TMPDIR:-/tmp}/vscode-ext-install.XXXXXX")" || return 1
    log="${TMPDIR:-/tmp}/vscode-ext-install.log"
    {
        echo '#!/usr/bin/env bash'
        declare -f find_code_clis install_extensions
        cat <<'EOS'
trap 'rm -f "$0"' EXIT
# arguments: the extension IDs to install
cli_failures=0
for attempt in $(seq 1 180); do            # 180 * 10s = up to 30 minutes
    install_extensions "$@"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "✅ Extensions installed on attempt $attempt"
        exit 0
    fi
    if [ "$rc" -eq 1 ]; then
        # a CLI exists, so this is not "client not attached yet": retry a
        # few times in case the server is warming up, then fail loudly
        cli_failures=$((cli_failures + 1))
        if [ "$cli_failures" -ge 6 ]; then
            echo "❌ A VS Code CLI is present but extensions failed 6 times; giving up."
            exit 1
        fi
    fi
    echo "⏳ attempt $attempt: retrying in 10s"
    sleep 10
done
echo "❌ Gave up waiting for the VS Code server"
exit 1
EOS
    } > "$helper"
    chmod +x "$helper"
    nohup bash "$helper" "${GLOBAL_EXTENSIONS[@]}" > "$log" 2>&1 &
    echo "⏳ VS Code server not attached yet; extensions will install in the background (log: $log)"
}

echo "🧩 Ensuring VS Code extensions..."
install_extensions "${GLOBAL_EXTENSIONS[@]}"
case $? in
    0) ;;
    1) echo "⚠️ Some extensions failed even though a VS Code CLI is available (see above)." ;;
    2) start_extension_watcher ;;
esac

echo "✅ Dotfiles setup complete!"
echo "   New terminals will have ~/.cargo/bin and ~/.local/bin on PATH."
