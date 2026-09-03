# chatwire81

Runs a Factorio dedicated server managed entirely through Discord, using
[ChatWire](https://github.com/M45-Science/ChatWire) and optionally
[SoftMod](https://github.com/M45-Science/SoftMod) — both pulled in as git
submodules pointing at your own forks, and built from that local checkout.
Docker Compose builds the image, launches the bot, and — once you run a
command in Discord — ChatWire downloads the actual Factorio headless server
itself.

> [!NOTE]
> `chatwire/` and `softmod/` are git submodules, not vendored at build
> time — run `make setup` (or `git submodule update --init --recursive`)
> after cloning to populate them before building. There is no `factorio`
> binary baked into the image; ChatWire downloads Factorio on demand (see
> [Installing Factorio](#installing-factorio)). SoftMod injection is still
> opt-in via config (see [SoftMod](#softmod)) even though the submodule is
> checked out by default.

## How it fits together

```
docker-compose.yml
├── cw-a   (built from ./Dockerfile, source in ./chatwire)   Discord bot + Factorio process
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
Dockerfile                            multi-stage build: ChatWire + runtime (source: ./chatwire)
docker-files/chatwire-entrypoint.sh   container entrypoint
Makefile                              setup/build/up/down/logs shortcuts
docker-compose.yml                    the committed service definitions — shared by everyone
docker-compose.override.yml.example   template for local tweaks (see Local overrides)
docker-compose.override.yml           yours, gitignored — merged on top automatically if present

chatwire/                        git submodule — your ChatWire fork (build source)
softmod/                         git submodule — your SoftMod fork; bind-mounted read-only to /softmod

data/                            → bind-mounted to /chatwire in the container
  cw-global-config.json          shared across all servers (Discord bot, roles, paths)
  cw-a/
    cw-local-config.json         this server's settings (port, channel, options)
    factorio/                    downloaded Factorio binary + saves (created on first install)
    log/, audit-log/             ChatWire's own logs (also mirrored to `docker logs`)

www/                             → bind-mounted to /www in cw-a, and read-only into the web container
  public_html/
    archive/                     zipped map archives (from /archive-map)
    modpack/                     zipped mod packs (from /modpack)
```

Everything under `data/` and `www/` is a bind mount, not a Docker volume —
it's just regular files on the host, owned by your user (see
[Running as your user](#running-as-your-user)). `chatwire/` and `softmod/`
are git submodules — real checkouts of your forks, not bind mounts — see
[Setup](#setup) and [SoftMod](#softmod). Edit the JSON config files
directly with any editor; there's no `.env` file or environment-variable
injection layer.

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
| `Paths.Folders.MapArchives` / `ModPack` | Where `/archive-map` and `/modpack` write zip files — points into `/www/public_html/{archive,modpack}/`, a separate bind mount from `ServersRoot`, so nginx can serve them |
| `Paths.URLs.Domain` / `PathPrefix` | Combined with `ArchivePath`/`ModPackPath`/`LogsPathWeb` to build links posted in Discord — see [The webserver](#the-webserver-www) for why `PathPrefix` is `"/"` rather than empty |
| `Options.RconOffset` | RCON port = server's `Port` + this offset |
| `Options.UseAuthserver` | Enforces Factorio's own global ban list (`--use-authserver-bans`), separate from your own moderation |

### `data/cw-a/cw-local-config.json` — per-server

| Field | What it's for |
|---|---|
| `Callsign` / `Name` | Combined into the Discord channel name (`{status-icon}{callsign}-{name}`) |
| `Port` | Game UDP port. RCON is `Port + Global.Options.RconOffset`. Must be unique per server if you run more than one (see [Running multiple servers](#running-multiple-servers)). |
| `Channel.ChatChannel` | Discord channel ID this server relays chat to and accepts commands from |
| `Options.SoftModOptions.InjectSoftMod` | Whether to inject SoftMod into new maps (see [SoftMod](#softmod) below) |
| `Options.SoftModOptions.SoftModPath` | Must point at `/softmod/` — that's where the compose bind mount puts it (see [SoftMod](#softmod)) |
| `Options.ExpUpdates` | Switches Factorio installs/updates from the `stable` release channel to `experimental` |

> [!IMPORTANT]
> ChatWire only reads these files at process start. **Restart the `cw-a`
> container after hand-editing either config file**
> (`docker compose restart cw-a`).

### SoftMod

[SoftMod](https://github.com/M45-Science/SoftMod) is a Lua gameplay mod
pack ChatWire can inject directly into a save's zip file — it isn't
installed as a normal Factorio `mods/` mod. `softmod/` is a **git
submodule** (see [`.gitmodules`](.gitmodules)) pointing at your own SoftMod
fork, and is bind-mounted read-only into the container at `/softmod`, so
you can edit it freely — locale text, permissions, whatever — without
touching the Docker build at all. Changes take effect on the next map
generation; no rebuild, just `docker compose restart cw-a`.

After cloning this repo, populate `chatwire/` and `softmod/` with:

```bash
make setup
# or: git submodule update --init --recursive
```

Since `softmod/` tracks your own fork, edits made there are a normal git
checkout — commit and push from inside `softmod/` like any other repo. To
pull in newer commits from whatever branch/remote `softmod` is set to
track:

```bash
make update-submodules
# or: git submodule update --remote --merge
```

If you don't want SoftMod at all, set `InjectSoftMod: false` in
`data/cw-a/cw-local-config.json` — the submodule can stay checked out, it's
simply never used. If `softmod/` is ever empty (submodule not initialized)
and `InjectSoftMod: true`, injection just logs `No softmod files found,
stopping.` and the map generates without it — harmless, not a crash.

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

1. Clone this repo and populate the submodules:

   ```bash
   git clone --recurse-submodules <this-repo-url>
   # or, if already cloned without --recurse-submodules:
   make setup   # same as: git submodule update --init --recursive
   ```

2. Create a Discord Application + Bot, invite it to your server with the
   `bot` and `applications.commands` scopes.
3. Fill in `data/cw-global-config.json`: `Discord.Token`, `Discord.Guild`,
   `Discord.Application`, and whichever `Discord.Roles.*` names you use.
4. Grant a role real Discord permissions (Administrator, or at least
   Manage Roles) and assign it to whoever should administer the bot.
5. Fill in `data/cw-a/cw-local-config.json`: `Channel.ChatChannel` (create a
   Discord text channel and paste its ID).
6. (Optional) Set `Options.SoftModOptions.InjectSoftMod: false` if you don't
   want SoftMod — see [SoftMod](#softmod). It's checked out by default.
7. (Optional) Change ports, add a second server, or set resource limits
   without touching the committed compose file — see
   [Local overrides](#local-overrides).

   ```bash
   make override   # copies docker-compose.override.yml.example
   ```

8. Build and start:

   ```bash
   make up
   # or: docker compose up -d --build
   ```

9. Watch it come up:

   ```bash
   make logs
   # or: docker compose logs -f cw-a
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

## Local overrides

`docker-compose.yml` is committed and shared. Anything specific to your
machine — a different host port, RCON exposed, CPU/memory limits, an extra
server — belongs in `docker-compose.override.yml` instead. Docker Compose
reads both files and merges them automatically, with no `-f` flags and no
Makefile changes, so `make up`, `make logs`, and plain `docker compose`
commands all pick it up. The override file is gitignored, so your local
tweaks stay out of every diff and `git pull` never conflicts with them.

```bash
make override          # copy docker-compose.override.yml.example (won't clobber an existing one)
$EDITOR docker-compose.override.yml
make config            # or: docker compose config — prints the merged result
make up
```

The example file is fully commented out; uncomment the blocks you want.

How the merge behaves, since it isn't uniform:

| In the override file | Result |
|---|---|
| A scalar (`image`, `restart`, `user`, `build.context`) | Replaces the base value |
| `environment`, `labels` | Merged per key — base keys you don't mention survive |
| `ports`, `volumes`, `cap_add`, `dns` | **Appended** to the base list |
| A service name not in the base file | Added to the project |

The append behavior is the part that bites: you can add a port mapping, but
you can't remove one the base file already defines. To move `web` off host
port 80 you'd end up publishing both 80 and 8080 — if that matters, change
the base file. Likewise there's no way to delete a service from an override;
to run without the webserver, start only what you want:

```bash
docker compose up -d cw-a
```

`docker compose config` renders the fully merged configuration and is the
fastest way to confirm an override did what you meant before starting
anything.

## Running multiple servers

ChatWire is one process per server, selected by working directory. To add
a second server (`cw-b`) alongside `cw-a`, sharing the same Discord bot and
`cw-global-config.json`:

1. Add another service in `docker-compose.override.yml` (see
   [Local overrides](#local-overrides) — the example file already has a
   ready-to-uncomment `cw-b` block), same build context, with:
   ```yaml
   environment:
     - CW_DIR=/chatwire/cw-b
   ports:
     - "10001:10001/udp"
   volumes:
     - ./data:/chatwire
     - ./www:/www
     - ./softmod:/softmod:ro
   ```
   A commented-out `cw-b` also sits in `docker-compose.yml` itself if you'd
   rather commit the second server for everyone.
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

ChatWire's `cwlog` package only writes to log files by default. `chatwire/`
(this fork) patches it directly in `cwlog/cwLog.go` to also print to
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

`Paths.URLs.LogsPathWeb` (`/current-logs/` by default) works the same way
for the "Log:" links ChatWire posts after bans and moderation actions —
`GetGameLogURL()` (`cfg/localCfg.go`) builds them as
`{Domain}{PathPrefix}{LogsPathWeb}{Callsign}/{filename}`. `docker-compose.yml`
bind-mounts `data/cw-a/log` read-only to `current-logs/c` in the `web`
container to match — the `c` **must** match `cw-a/cw-local-config.json`'s
`Callsign`; update the mount if you change it, and add one such line per
server for a multi-server setup. `Paths.URLs.LogPath` (`/logs/`) is defined
in config but unused by ChatWire's own code — nothing generates a link with
it — so it's left unwired.

> [!NOTE]
> Requesting `/` on the webserver returns 403 by design — there's no
> `index.html` and directory listing (`autoindex`) is off. Direct file
> links (`/archive/<file>.zip`, `/current-logs/c/<file>.log`) work fine.
