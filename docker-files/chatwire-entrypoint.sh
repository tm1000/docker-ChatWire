#!/bin/bash
set -eou pipefail

CW_HOME="/chatwire"
CW_DIR="${CW_DIR:-$CW_HOME/cw-a}"
WWW_HOME="/www"

mkdir -p "$CW_DIR"
cd "$CW_DIR"

# Web-servable output dir (Paths.Folders.MapArchives / ModPack write here).
# Bind-mounted separately from $CW_HOME so it's a sibling path, not nested
# inside it; nginx reads this same host path read-only. Created on every
# boot so it always exists, regardless of what's already on the host.
mkdir -p "$WWW_HOME/public_html/archive" "$WWW_HOME/public_html/modpack"

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

# Flags passed to /bin/ChatWire (e.g. -regCommands, -noDiscord, -localTest).
# Set via the CW_ARGS env var. -regCommands only needs to run once (or after
# a slash command changes) since it bulk-overwrites Discord's command list;
# no flags are passed by default.
read -ra CW_ARGS_ARR <<<"${CW_ARGS:-}"
exec /bin/ChatWire "${CW_ARGS_ARR[@]}"
