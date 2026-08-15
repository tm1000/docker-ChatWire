#!/bin/bash
set -eou pipefail

CW_HOME="/chatwire"
CW_DIR="${CW_DIR:-$CW_HOME/cw-a}"

mkdir -p "$CW_DIR"
cd "$CW_DIR"

# First run: let ChatWire lay down its default cw-local-config.json (here)
# and cw-global-config.json (in $CW_HOME, one level up).
if [[ ! -f cw-local-config.json || ! -f "$CW_HOME/cw-global-config.json" ]]; then
  timeout 3 /bin/ChatWire || true
fi

# ServersRoot defaults to the parent of the ChatWire binary's own directory,
# which is outside $CW_HOME and would not persist. Pin it to the mounted
# volume so downloaded Factorio binaries, saves, and mods survive restarts.
jq --arg v "$CW_HOME/" '.Paths.Folders.ServersRoot = $v' "$CW_HOME/cw-global-config.json" >"$CW_HOME/.cw-global-config.json.tmp"
mv "$CW_HOME/.cw-global-config.json.tmp" "$CW_HOME/cw-global-config.json"

exec /bin/ChatWire -regCommands
