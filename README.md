# chatwire81

Runs a Factorio dedicated server managed entirely through Discord, using
[ChatWire](https://github.com/M45-Science/ChatWire) (built from source) and
optionally [SoftMod](https://github.com/M45-Science/SoftMod). Docker Compose
builds the image, launches the bot, and — once you run a command in Discord —
ChatWire downloads the actual Factorio headless server itself.

> [!NOTE]
> There is no `factorio` binary baked into the image, and no SoftMod either.
> ChatWire downloads Factorio on demand (see
> [Installing Factorio](#installing-factorio)); SoftMod is up to you to
> provide, so you can freely edit it for your own server (see
> [SoftMod](#softmod)).

## How it fits together

```
docker-compose.yml
├── cw-a   (built from factorio/Dockerfile)   Discord bot + Factorio process
└── web    (nginx:alpine)                     serves map archives / modpacks
```

**`cw-a`** runs a single Go binary, `ChatWire`, which:

- connects to Discord as a bot and registers slash commands in your guild
- on command, downloads the Factorio headless server from factorio.com,
  verifies its checksum, and spawns it as a subprocess
- relays chat between Discord and the running game
- injects [SoftMod](https://github.com/M45-Science/SoftMod) (a Lua gameplay
  mod pack) into new maps, if enabled and present in `softmod/`

ChatWire has no multi-instance flag — **which server a process manages is
determined entirely by its current working directory** (`CW_DIR`). It reads
`cw-local-config.json` from that directory and `cw-global-config.json` from
its parent. This is why the layout below has one global config shared by
every server, and one local config per server.

**`web`** is a plain nginx container serving `www/public_html/`, which
ChatWire itself writes into when you archive a map or build a modpack. It's
optional — everything else works without it.

## Directory layout

```
chatwire/
  Dockerfile                    multi-stage build: ChatWire + runtime
  files/chatwire-entrypoint.sh  container entrypoint

data/                            → bind-mounted to /chatwire in the container
  cw-global-config.json          shared across all servers (Discord bot, roles, paths)
  cw-a/
    cw-local-config.json         this server's settings (port, channel, options)
    factorio/                    downloaded Factorio binary + saves (created on first install)
    log/, audit-log/             ChatWire's own logs (also mirrored to `docker logs`)

www/
  public_html/
    archive/                     zipped map archives (from /archive-map)
    modpack/                     zipped mod packs (from /modpack)

softmod/                         → bind-mounted read-only to /softmod
                                    empty by default; clone SoftMod here yourself (see SoftMod)
```

Everything under `data/`, `www/`, and `softmod/` is a bind mount, not a
Docker volume — it's just regular files on the host, owned by your user
(see [Running as your user](#running-as-your-user)). Edit the JSON config
files directly with any editor; there's no `.env` file or
environment-variable injection layer.

## Configuration

### `data/cw-global-config.json` — shared across all servers

| Field | What it's for |
|---|---|
| `Discord.Token` | Bot token (Discord Developer Portal → Bot → Reset Token) |
| `Discord.Guild` | The Discord server (guild) ID the bot operates in |
| `Discord.Application` | The bot's Application/Client ID — required for slash commands to register at all |
| `Discord.Roles.*` | Discord role **names** (e.g. `"Admin"`, `"Regular"`) ChatWire looks for |
| `Discord.Roles.RoleCache.*` | Resolved role **IDs** — auto-populated by ChatWire (`startGuildSyncLoop`, ~1x/min) once `Guild` is valid. Leave blank; don't hand-edit unless a role got recreated and the cache is stale. |
| `Factorio.Username` / `Factorio.Token` | Your factorio.com account, used for mod-portal downloads |
| `Paths.Folders.ServersRoot` | Base directory ChatWire installs Factorio/saves/mods under. Pinned to `/chatwire/` by the entrypoint on every boot (see below) — don't change it. |
| `Paths.Folders.MapArchives` / `ModPack` | Where `/archive-map` and `/modpack` write zip files — points into `data/cw-a/../www/public_html/{archive,modpack}/` so nginx can serve them |
| `Paths.URLs.Domain` / `PathPrefix` | Combined with `ArchivePath`/`ModPackPath` to build the download links posted in Discord |
| `Options.RconOffset` | RCON port = server's `Port` + this offset |
| `Options.UseAuthserver` | Enforces Factorio's own global ban list (`--use-authserver-bans`), separate from your own moderation |

### `data/cw-a/cw-local-config.json` — per-server

| Field | What it's for |
|---|---|
| `Callsign` / `Name` | Combined into the Discord channel name (`{status-icon}{callsign}-{name}`) |
| `Port` | Game UDP port. RCON is `Port + Global.Options.RconOffset`. Must be unique per server if you run more than one (see [Running multiple servers](#running-multiple-servers)). |
| `Channel.ChatChannel` | Discord channel ID this server relays chat to and accepts commands from |
| `Options.SoftModOptions.InjectSoftMod` | Whether to inject SoftMod into new maps (see [SoftMod](#softmod) below) |
| `Options.SoftModOptions.SoftModPath` | Must point at `/softmod/` — that's where the Dockerfile puts it (see [SoftMod](#softmod)) |
| `Options.ExpUpdates` | Switches Factorio installs/updates from the `stable` release channel to `experimental` |

> [!IMPORTANT]
> ChatWire only reads these files at process start. **Restart the `cw-a`
> container after hand-editing either config file**
> (`docker compose restart cw-a`).

### SoftMod

[SoftMod](https://github.com/M45-Science/SoftMod) is a Lua gameplay mod
pack ChatWire can inject directly into a save's zip file — it isn't
installed as a normal Factorio `mods/` mod, and the Dockerfile doesn't
fetch it. It's **not bundled** — `softmod/` starts out empty
(only a `.gitignore` that excludes everything except itself) and is
bind-mounted read-only into the container at `/softmod`, so you can clone
your own copy there and freely edit it — locale text, permissions, whatever
— without touching the Docker build at all. Changes take effect on the next
map generation; no rebuild, just `docker compose restart cw-a`.

To provide it, download and unzip the archive straight from GitHub — no
git required, and no `.git` directory to worry about:

```bash
curl -L -o /tmp/softmod.zip https://github.com/M45-Science/SoftMod/archive/refs/heads/Main.zip
unzip -q /tmp/softmod.zip -d /tmp/softmod-extract
cp -r /tmp/softmod-extract/SoftMod-Main/. ./softmod/
rm -rf /tmp/softmod.zip /tmp/softmod-extract
```

(GitHub's archive zip extracts into a `SoftMod-Main/` subdirectory, so the
contents get copied out of it into `softmod/` directly.)

Alternatively, if you'd rather track it with git so you can pull upstream
updates:

```bash
git clone https://github.com/M45-Science/SoftMod.git /tmp/softmod-clone
rm -rf /tmp/softmod-clone/.git
cp -r /tmp/softmod-clone/. ./softmod/
rm -rf /tmp/softmod-clone
```

(cloning through a temp directory avoids committing a nested `.git` into
`softmod/`, and avoids `git clone`'s refusal to target a non-empty
directory — `softmod/.gitignore` is already there.)

If `softmod/` is empty and `InjectSoftMod: true`, injection just logs
`No softmod files found, stopping.` and the map generates without it —
harmless, not a crash.

**`SoftModPath` default is wrong for this setup.** If left empty,
ChatWire auto-generates it as:

```
ServersRoot + ChatWirePrefix + Callsign + "/" + FactorioDir + "/softmod/"
```

which resolves to `/usr/cw-a/factorio/softmod/` here — a path that doesn't
exist and (as a non-root container) isn't even writable. It must be set
explicitly to `/softmod/`, matching the bind mount above.

Customizing it: most of the M45-Science-specific branding (server name,
welcome text, rules, links) lives in a plain key=value file, not Lua code —
`locale/en/locale.cfg` — so it's editable without touching game logic at
all. Look for keys like `info_m45_science`, `info_commands_website`, and
`info_rule8` for the branded bits.

**Verifying it actually loaded** — injecting the files into the save and
the game actually running them are two different things to confirm:

1. When a new map is generated with `InjectSoftMod: true`, ChatWire logs
   `SoftMod injected.` (or a specific failure reason if it didn't work).
2. Once the server is actually running, SoftMod's own `control.lua` prints
   a `[SVERSION] <version>` line on the console, which ChatWire watches
   for and logs as `Softmod detected: <version>` — this only appears if
   SoftMod's Lua code is genuinely executing inside the live game.
3. In Discord, `/info` only shows a **"SoftMod version"** field once
   ChatWire has seen that `[SVERSION]` line.

Both log lines show up in `docker compose logs -f cw-a` thanks to the
stdout patch (see [Logging](#logging)).

Injection only happens when a *new* map is generated with
`Settings.Scenario` empty/`"none"` — enabling `InjectSoftMod` after a map
already exists won't retroactively inject it; run `/factorio new-map`.

### Discord role permissions (a separate layer from `RoleCache`)

`RoleCache` is ChatWire's own internal permission check — it does **not**
affect whether a Discord user can even *see* the slash command in the
picker. Discord itself hides commands from users who lack the permission
bits declared in `DefaultMemberPermissions`:

- Commands marked `AdminOnly` in ChatWire require the **Administrator**
  Discord permission
- Commands marked `ModeratorOnly` (including `/factorio`) require
  **Manage Roles**

Freshly created Discord roles get no permissions by default. Whoever needs
to run `/factorio start`, `/rcon`, etc. needs a role with at least
**Manage Roles**, regardless of what `RoleCache` says.

## Setup

1. Create a Discord Application + Bot, invite it to your server with the
   `bot` and `applications.commands` scopes.
2. Fill in `data/cw-global-config.json`: `Discord.Token`, `Discord.Guild`,
   `Discord.Application`, and whichever `Discord.Roles.*` names you use.
3. Grant a role real Discord permissions (Administrator, or at least
   Manage Roles) and assign it to whoever should administer the bot.
4. Fill in `data/cw-a/cw-local-config.json`: `Channel.ChatChannel` (create a
   Discord text channel and paste its ID).
5. (Optional) Populate `softmod/` if you want SoftMod — see
   [SoftMod](#softmod). Leave it empty to skip it.
6. Build and start:

   ```bash
   docker compose up -d --build
   ```

7. Watch it come up:

   ```bash
   docker compose logs -f cw-a
   ```

   You should see `Discord bot ready.` and `Bulk registering commands!`
   followed by the full command list. If a Discord client was already open,
   restart it to pick up the new slash commands.

## Installing Factorio

There's no download-a-specific-version option — `/factorio install-factorio`
and `/factorio update-factorio` both always resolve to whatever
factorio.com currently reports as latest on the selected channel
(`stable`, or `experimental` if `ExpUpdates: true`). To run a pinned
version, download the headless tarball yourself and extract it into
`data/cw-a/factorio/` before starting.

In Discord (as a user with the required role, see above):

```
/factorio install-factorio     # first time only
/factorio start                # generates a new map automatically if none exists
```

Other actions under `/factorio`: `stop`, `new-map`, `update-factorio`,
`update-mods`, `sync-mods`, `archive-map`.

## Running as your user

The `cw-a` service runs as `user: "1000:1000"` so everything it creates
under `data/` and `www/` is owned by your host user, not root — no `sudo`
or throwaway containers needed to clean up. `web` (nginx) deliberately
does **not** set this: nginx needs to start as root to bind port 80 and
then drops privileges to its own unprivileged worker internally.

## Running multiple servers

ChatWire is one process per server, selected by working directory. To add
a second server (`cw-b`) alongside `cw-a`, sharing the same Discord bot and
`cw-global-config.json`:

1. Add another service to `docker-compose.yml`, same build context, with:
   ```yaml
   environment:
     - CW_DIR=/chatwire/cw-b
   ports:
     - "10001:10001/udp"
   volumes:
     - ./data:/chatwire
     - ./www:/chatwire/www
     - ./softmod:/softmod:ro
   ```
2. After its first boot, edit `data/cw-b/cw-local-config.json`: set `Port`
   to something distinct (e.g. `10001`) and `Channel.ChatChannel` to a
   different Discord channel.

Both processes connect to Discord with the same bot token; each only acts
on commands sent in *its own* configured channel
(`commands/util.go` filters every interaction by `ChannelID`), so this is
safe by design — it's the intended way ChatWire supports server groups.

There's no meaningful performance cost to this beyond normal OS process/CPU
contention — Docker isn't adding overhead here (no network virtualization
in play, bind mounts are native filesystem I/O, no resource limits are set
on the service).

## Logging

ChatWire's `cwlog` package only writes to log files by default. The
Dockerfile patches it (`sed`, guarded by an assertion so an upstream change
fails the build loudly rather than shipping unpatched) to also print to
stdout, so:

```bash
docker compose logs -f cw-a
```

shows the same content as `data/cw-a/log/newest.log` and
`data/cw-a/audit-log/*.log`, live.

## The webserver (`www/`)

`Paths.Folders.MapArchives` / `ModPack` and `Paths.URLs.Domain` /
`PathPrefix` / `ArchivePath` / `ModPackPath` exist so ChatWire can post a
working download link in Discord after `/archive-map` or `/modpack`. The
`web` service is a minimal nginx container serving exactly that directory,
read-only, on port 80.

This is entirely optional. If `Domain` is left as `localhost` (the
default), ChatWire's own code skips link generation — `/archive-map` still
writes the zip file, it just won't post a clickable link.

> [!NOTE]
> Requesting `/` on the webserver returns 403 by design — there's no
> `index.html` and directory listing (`autoindex`) is off. Direct file
> links (`/archive/<file>.zip`) work fine.
