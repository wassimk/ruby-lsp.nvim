#!/usr/bin/env bash
#
# Prepares /tmp/ruby-lsp-demo for recording the README demo (see demo/ruby-lsp.tape).
#
# Copies demo/sample to /tmp and installs its bundle there, since bundler and Ruby LSP write
# Gemfile.lock, .bundle/, and .ruby-lsp/ into the project.

set -euo pipefail

DEMO_DIR=/tmp/ruby-lsp-demo
# Installed gems live outside DEMO_DIR, so re-renders reuse them instead of recompiling
BUNDLE_DIR=/tmp/ruby-lsp-demo-bundle
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

rm -rf "$DEMO_DIR"
mkdir -p "$DEMO_DIR"
cp -R "$REPO_DIR/demo/sample" "$DEMO_DIR/calculator"

cd "$DEMO_DIR/calculator"
bundle config set --local path "$BUNDLE_DIR" >/dev/null
bundle install --quiet

# Run bundle through a symlink in the sandbox, so paths the debugger shows (the process
# name in dap-ui's Stacks panel) don't reveal where Ruby is installed on this machine
mkdir -p "$DEMO_DIR/bin"
ln -sf "$(command -v bundle)" "$DEMO_DIR/bin/bundle"

# Environment for the demo shell: ignore personal git config, keep nvim data in the sandbox
cat >"$DEMO_DIR/env.sh" <<ENV
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export XDG_DATA_HOME=$DEMO_DIR/data XDG_STATE_HOME=$DEMO_DIR/state
export DEMO_INIT=$REPO_DIR/demo/init.lua
export PATH=$DEMO_DIR/bin:\$PATH
ENV
