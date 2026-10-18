#!/bin/bash

if ! command -v rustup &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

GLOBAL_EXTENSIONS=(
    "rust-lang.rust-analyzer"
    "vadimcn.vscode-lldb"
    "serayuzgur.crates"
)

for ext in "${GLOBAL_EXTENSIONS[@]}"; do
    code --install-extension "$ext" --force
done
