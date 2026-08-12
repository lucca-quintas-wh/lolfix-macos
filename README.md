# lolfix

Detect and fix stuck **League of Legends** processes on macOS.

Fixes the classic **"Play button flashes and nothing happens"** after a patch — without rebooting.

```bash
lolfix              # detect and list — changes nothing
lolfix --unstick    # clear the kernel's stale code signature cache
lolfix --fix        # kill + unstick + cache: the full recipe
```

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/lucca-quintas-wh/lolfix-macos/main/install.sh | bash
```

Or from a clone:

```bash
git clone https://github.com/lucca-quintas-wh/lolfix-macos.git
cd lolfix-macos && ./install.sh
```

Installs to `~/.local/bin` by default. Override with `PREFIX=/usr/local/bin ./install.sh`. No dependencies beyond what ships with macOS.

> The CLI's output is in Portuguese. Everything else — flags, docs, behavior — is English.

---

## The main problem

After a patch, you click **Play** in the Riot Client. The button greys out for a moment, then resets. No window, no error message. Rebooting your Mac fixes it — and it's the only thing that does.

The macOS crash report shows what's really happening:

```
signal:        SIGKILL (Code Signature Invalid)
termination:   CODESIGNING / "Taskgated Invalid Signature"
codeSigningID: ""
procName:      LeagueClient
```

The macOS kernel caches a binary's code signature **keyed to the file's inode**. When a patch rewrites `LeagueClient`, the kernel's cache still points at the old contents. Every attempt to load the new binary fails validation, and the process is killed with `SIGKILL` before it can draw a single window.

Rebooting works only because it flushes that cache.

This explains the set of symptoms that otherwise looks contradictory:

| Symptom | Cause |
|---|---|
| `codesign` reports `valid on disk`, yet the kernel kills it | disk is fine, kernel cache is stale |
| Reboot fixes it, reinstalling is unnecessary | the reboot only clears the cache |
| The button resets with no error at all | the process dies before its first window |
| Clearing the client's cache doesn't help | wrong cache — it's the kernel's, not the app's |

### The fix

Recreating the file gives it a **new inode**, forcing the kernel to re-read the signature from scratch:

```bash
lolfix --unstick
```

It processes 7 binaries (`LeagueClient`, `LeagueClientUx`, both crash handlers, Chromium Embedded Framework, vivox, discord sdk). It uses `ditto` to preserve permissions, xattrs and ACLs, then an atomic `mv` over the original.

The old file **must not** be left inside the bundle — any leftover breaks the code signing seal with `a sealed resource is missing or invalid`. That's why the replacement is atomic, and why `--unstick` verifies both bundles' signatures at the end, aborting with a pointer to the Riot Repair Tool if anything fails to check out.

Measured result: exit `137` (SIGKILL) → exit `0`, across consecutive runs with no new crash reports.

---

## Usage

| Command | What it does |
|---|---|
| `lolfix` | Detect and list. **Read-only.** |
| `lolfix --kill` / `-k` | Terminate processes (`TERM`, then `KILL -9` for stragglers) |
| `lolfix --unstick` / `-u` | Clear the kernel's code signature cache. Replaces the reboot |
| `lolfix --cache` / `-c` | Clear Riot/League caches and lockfiles |
| `lolfix --fix` / `-f` | `--kill` + `--unstick` + `--cache` |
| `lolfix --reset-config` | Reset in-game settings (backs up first) |
| `lolfix -y` | Skip confirmation prompts |
| `lolfix --help` / `-h` | Help |

The default mode changes nothing: it lists processes with PID/CPU/memory/uptime, shows pending lockfiles, and reports how much each cache directory is using.

### Detection

Matches `RiotClientServices`, `RiotClientUx`, `LeagueClient`, `LeagueCrashHandler`, `RiotClientCrashHandler`, the Riot Repair Tool, and the game binary itself — deduplicating PIDs, with guards so it never kills itself or the shell that invoked it.

### Safety

- Default mode is read-only
- Every destructive action prompts for confirmation (`-y` to skip)
- `--cache` refuses to run while the client is open
- `--reset-config` takes a timestamped backup first
- `--unstick` verifies signatures afterwards and aborts if they don't check out
- With no TTY available to confirm, the script cancels rather than proceeding

---

## Cache cleanup

`--cache` removes the directories below, all of which the client regenerates on its own:

```
~/Library/Application Support/Riot Client/{Cache,Code Cache,GPUCache,DawnCache,blob_storage}
~/Library/Application Support/riot-client-ux/{Cache,Code Cache,GPUCache,DawnCache,blob_storage}
~/Library/Application Support/com.riotgames.LeagueofLegends.{LeagueClient,GameClient}/logs
/Applications/League of Legends.app/Contents/LoL/Logs
```

Plus the lockfiles left behind when the client dies uncleanly. On an installation with some mileage this routinely exceeds 600 MB.

---

## Related problem: "The application can't be opened"

If launching from the Finder icon gives you that error, it's a **different** problem — the outer bundle is corrupted, missing both `Contents/MacOS/` and `_CodeSignature`:

```
Contents/
├── LoL/          ok
├── Resources/    ok
├── Info.plist    ok
└── MacOS/        missing
```

Every macOS app needs `Contents/MacOS/<executable>`. Without it, LaunchServices gives up before running anything, and the Finder's message doesn't say why.

`lolfix` **does not fix this** — doing so would mean writing inside a signed bundle. Your options are the **Riot Repair Tool** or reinstalling the launcher.

In the meantime, launch through the Riot Client, which bypasses the broken shell and goes straight to the inner `LeagueClient.app`:

```bash
open "/Users/Shared/Riot Games/Riot Client.app" --args \
     --launch-product=league_of_legends --launch-patchline=live
```

---

## Caveats

**The inode hypothesis was confirmed empirically, not from Apple documentation.** The behavior reproduces consistently (`137` → `0`), but if `--unstick` ever fails to help, rebooting remains the guaranteed fallback.

Paths were mapped from a real installation. If Riot restructures things in a major patch, the script skips whatever isn't there — it won't break, it'll just clean less.

Tested on macOS 26 (Darwin 25.6), Apple Silicon (M4 Pro), with `LeagueClient` running under Rosetta.

---

## License

MIT
