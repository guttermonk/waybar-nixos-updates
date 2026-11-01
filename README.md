# 🔄 waybar-nixos-updates
[![License: GPL-3.0](https://img.shields.io/badge/license-GPLv3-blue.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![GitHub stars](https://img.shields.io/github/stars/guttermonk/waybar-nixos-updates?style=for-the-badge)](https://github.com/guttermonk/waybar-nixos-updates/stargazers)

A [Waybar](https://github.com/Alexays/Waybar) update checking script for NixOS that checks for available updates and displays them in your Waybar.

Here's how the module looks in Waybar with and without updates:

![Screenshot with updates](/resources/screenshot-thumbnail-has-updates.png)
![Screenshot updates](/resources/screenshot-thumbnail-updated.png)

Here's how the module's tooltip looks when updates are available:
![Screenshot with updates](/resources/screenshot-has-updates.png)

Credit goes to [this project](https://github.com/J-Carder/waybar-apt-updates) for the idea and starting point.

## 📦 Dependencies

When using the flake, all dependencies are automatically handled. The script requires:

### 🔧 Commands/Programs:
1. `nix` - Used for `nix flake update` and `nix build` commands
2. `nvd` - Used for comparing system versions (`nvd diff`)
3. `notify-send` - For desktop notifications
4. Standard utilities: `bash`, `grep`, `awk`, `sed`, `iproute2` (for `ip` command)

### 💻 System Requirements:
1. NixOS operating system
2. A running Waybar instance (the script outputs JSON for Waybar integration)
3. Internet connectivity for performing update checks
4. Desktop notification system compatible with `notify-send`, able to render
   SVG icons — which means librsvg's gdk-pixbuf loader is installed. It is
   present on most desktops, and on NixOS the common daemons pull it in
   themselves: mako and swaync are wrapped with `GDK_PIXBUF_MODULE_FILE`
   pointing at librsvg's loader cache, and dunst links librsvg directly.
   Without it the notifications still appear, just without their icon.

### 📋 Configuration Assumptions:
- Your flake is in `~/.config/nixos` (configurable via Home Manager module)
- Your flake's nixosConfigurations is named the same as your `$hostname`

## ⚡ Check Modes

waybar-nixos-updates supports two update checking strategies:

### Lightweight Mode (Default)
Resolves each package's `.version` attribute by lazy Nix evaluation and compares it against what is installed. **Nothing is built or downloaded.**
- A single `nix eval`, no closure realisation
- Around two minutes on a ~340-package configuration
- Checks both NixOS system packages AND home-manager packages (auto-detected)
- Supports single-channel or dual-channel (stable + unstable) configurations
- ~80-85% attribute name coverage (some store paths don't map to nixpkgs attrs)
- No transitive dependency tracking: a package whose own version is unchanged but whose dependencies moved is not counted

### Full Mode
Exactly as accurate as a rebuild, because it *performs* one. It resolves a speculative lock, runs `nix build` on the new system closure, and diffs the result against the current system with `nvd`.
- Runs `nix flake update` + `nix build` + `nvd diff`
- Detects all package changes including transitive dependencies
- Shows added/removed packages

> [!WARNING]
> **Full mode downloads and builds the entire pending update, on every scheduled check.** Its cost is the cost of the update itself, not of inspecting it — `nvd` can only diff store paths that exist, so the closure has to be realised first. On a large or long-deferred update that is gigabytes of traffic and many minutes of CPU, and it repeats every `updateInterval` until you actually rebuild. Don't enable it on a metered or slow connection.
>
> To find out what an update would cost *without* paying for it, use `dryRunPreview` (see Configuration Options) instead — it asks Nix for a build plan rather than executing one, on demand rather than on a timer.

| | Lightweight (default) | Full |
| --- | --- | --- |
| Builds / downloads | **No** | **Yes — the whole update** |
| Duration | ~2 min (evaluation) | As long as the update takes |
| Bandwidth per check | none | up to the full update size |
| Accuracy | Top-level packages only | Complete closure diff |
| Transitive deps | ✗ | ✓ |
| Added/removed pkgs | ✗ | ✓ |
| Attr name coverage | ~80-85% | 100% |

**Explicit Packages Filter**: When `CONFIG_DIR` is set, lightweight mode automatically enables `EXPLICIT_PACKAGES_ONLY` mode, which only reports updates for packages explicitly defined in your nix configuration files. This significantly reduces false positives from system dependencies and provides results closer to what full mode would report.

**Lightweight** is the default and the right choice for almost everyone: it answers "is there anything to update?" without doing the update. Choose **full** only when you need a complete closure diff — transitive dependencies, added and removed packages — and are willing to pay the update's own cost on every check to get it.

## 🚀 How to Use

### 💿 Installation Methods

This project provides multiple installation methods through its Nix flake:

#### 1. Using the Flake as a Package

Add to your flake inputs:
```nix
{
  inputs.waybar-nixos-updates.url = "github:yourusername/waybar-nixos-updates";
  
  # In your system configuration:
  environment.systemPackages = [
    inputs.waybar-nixos-updates.packages.${system}.default
  ];
}
```

#### 2. Using Home Manager Module (Recommended)

This provides the most flexibility for configuration:

```nix
{
  inputs.waybar-nixos-updates.url = "github:yourusername/waybar-nixos-updates";
  
  # In your home-manager configuration:
  imports = [ inputs.waybar-nixos-updates.homeManagerModules.default ];
  
  programs.waybar-nixos-updates = {
    enable = true;
    checkMode = "lightweight";      # "lightweight" (default) or "full" - see Check Modes
    updateInterval = 3600;          # Check every hour
    notifications = true;           # Set to false to disable desktop notifications
    
    # Path to your NixOS flake (used by both modes):
    # - Full mode: for nix build and nvd diff
    # - Lightweight mode: for flake.lock and .nix file scanning
    nixosConfigPath = "~/.config/nixos";
    
    # Full mode only:
    updateLockFile = false;         # Use temp dir for checks
    
    # Lightweight mode - Option A: Single channel (simple)
    nixpkgsChannel = "github:NixOS/nixpkgs/nixpkgs-unstable";
    
    # Lightweight mode - Option B: Dual channel (for mixed stable/unstable)
    # Scans nixosConfigPath for .nix files to determine package sources
    # nixpkgsChannel = {
    #   stable = "pkgs";                  # Matches: pkgs.foo, with pkgs; [...]
    #   unstable = "pkgs-unstable";       # Matches: pkgs-unstable.foo, with pkgs-unstable; [...]
    # };
    
    # Common options:
    skipAfterBoot = true;           # Skip checks after boot/resume
    gracePeriod = 60;               # Wait 60s after boot
  };
  
  # Then add to your waybar configuration:
  programs.waybar.settings.mainBar."custom/nix-updates" = 
    config.programs.waybar-nixos-updates.waybarConfig;
}
```

#### 3. Using NixOS Module

For system-wide installation:
```nix
{
  imports = [ inputs.waybar-nixos-updates.nixosModules.default ];
  
  services.waybar-nixos-updates.enable = true;
}
```

#### 4. Using the Legacy default.nix

You can still use the included `default.nix` file with Home Manager:
```nix
imports = [ ./path-to-waybar-nixos-updates/default.nix ];
```

#### 5. Manual Installation

For a manual installation, download the `update-checker` script, put it in your [PATH](https://unix.stackexchange.com/a/26059) and make it executable (`chmod +x update-checker`). Add the icons to your ~/.icons folder.

Two optional features are separate helper scripts that `update-checker` invokes by name, so they must be on your `PATH` too if you use them — the flake handles this for you, a manual install does not:

- `source-checker` — required by `sourceChecks`
- `custom-checker` — required by `customChecks`
- `preview` — required by the update-cost preview (`update-checker preview`, bound to middle-click)

### ⚙️ Configuration Options

When using the Home Manager module, you can configure these options:

- `checkMode`: Update check strategy - `"lightweight"` (default) or `"full"`. See **Check Modes** above — **`"full"` downloads and builds the whole pending update on every check.**
  - In lightweight mode, versions are compared with Nix's own ordering (`builtins.compareVersions`), so `5.3p9 → 5.3p15` is correctly an upgrade and `1.16.1 → 1.3.6` is not
  - A pending change where the channel is *behind* what you have installed is reported and marked `(downgrade)` rather than hidden — moving a package from `pkgs-unstable` to `pkgs` is a deliberate change worth seeing before you rebuild
- `updateInterval`: Minimum time in seconds between update checks (default: 3600)
  - This is the *check* interval, not waybar's poll interval. The module polls more often than it checks — at `updateInterval / 10`, capped at 500s — and the script throttles itself against `updateInterval`. A check therefore runs at the first poll after it comes due: never early, and late by at most the poll interval (under 9 minutes on a 6-hour setting).
  - The two must not be equal. A check started by the poll at `T` only records its timestamp at `T + duration`, so a poll at `T + updateInterval` sees slightly less than the interval elapsed and skips — losing every second poll and doubling the effective period.
- `afterRebuild`: What to do when a rebuild that changed package versions is detected - `"recheck"` (default), `"reconcile"` or `"assume-updated"`
  - `"recheck"`: discard the previous result and run a real check, so the count reflects what is still outstanding. A rebuild that applied only *some* of the pending updates — you ran `nix flake update nixpkgs` but not the rest, or updated a single input — is reported correctly. Costs one check per rebuild, which in `"full"` mode means building the new closure.
  - `"reconcile"`: subtract the packages the rebuild demonstrably changed and keep the rest. Detecting the rebuild already means diffing the old and new closures with `nvd`, so the list of what changed is there for free:
    ```
    [U*]  #13  thunderbird  153.0.2 -> 153.0.3     ← pending entry dropped
    (ripgrep not mentioned)                        ← pending entry kept
    ```
    Usually right, and costs no work beyond the diff already being run. What it cannot see is the **channel moving forward** since the last check, so it can undercount — it never reports an update as resolved that wasn't, and the next scheduled check replaces the estimate with a measurement. Falls back to `"recheck"` when there is nothing to reconcile against, such as a previous closure that has been garbage collected.
  - `"assume-updated"`: treat the rebuild as having applied everything and report zero without checking, deferring the next real check to the normal `updateInterval`. Cheapest, and right if you always update every input before rebuilding. If you did not, updates from the inputs you left alone are still outstanding but read as zero until the next scheduled check.
  - Only the **package** count is affected. A rebuild does not resolve stale flake inputs, pinned inputs or source drift, so those keep both their counts and their tooltip sections under all three settings.
  - A right-click forces a real check immediately under any setting.
- `notifications`: Whether to show desktop notifications (default: true)
- `skipAfterBoot`: Whether to skip update checks right after boot/resume (default: true)
- `gracePeriod`: Time in seconds to wait after boot/resume before checking (default: 60)
- `clockFormat`: Clock format for tooltip timestamps - `"24h"` (e.g. `14:23`, default) or `"12h"` (e.g. `2:23 PM`)
- `inputChecker.mode`: How to handle stale flake inputs (default: `"disabled"`)
  - `"disabled"`: Don't check inputs (no resources used)
  - `"show"`: Check and show in tooltip, but don't include in count
  - `"count"`: Check, show in tooltip, and include in waybar count
  - Uses `git ls-remote` to compare locked revisions against upstream
  - Each stale input reads `name: current → upstream (distance)` — `nixpkgs: 2026-10-14 → 2026-10-20 (412 commits)`. The arrow is the point: a line naming only a locked date said nothing about there being an update, so a section of them read as an inventory of every input rather than the ones with work waiting. See `upstreamInfo` below for where the dates and the count come from, and what the line falls back to when they can't be had.
  - Every tooltip section carries its heading, including a lone one, so `Inputs:` and `Packages:` are never left to be inferred from the lines themselves
  - **An unreachable upstream is reported, not skipped:** `gone (upstream unreachable)`, keeping the `name (reason)` shape failures use elsewhere. Going silent made an unreachable remote indistinguishable from an input that is up to date — the input left both the section and the count, which reads as "nothing to do here" when the truth is "nobody knows".
    - **Not counted.** A count is for updates there are to apply, and whether such an input has one is exactly what failed to be established. So the section now appears whenever there are lines to show, rather than only when the count is non-zero.
    - Only one remote failing produces this. With no default route the checkers report the outage and never run the input checks at all, so being offline gives one message rather than one line per input.
  - Supported input types:
    - GitHub inputs (`github:owner/repo/branch`)
    - Generic git inputs (`git+https://...`) - Bitbucket, GitLab, self-hosted, etc.
    - Local inputs (`git+file:///path`, which nix locks as `file:/path`). The single-slash form is normalised before the lookup, since git otherwise reads `file:` as an ssh hostname and fails on a directory it could read perfectly well.
- `inputChecker.pinned`: How to handle pinned flake inputs (default: `"disabled"`)
  - `"disabled"`: Don't check pinned inputs (no resources used)
  - `"show"`: Check and show in separate "Pinned:" section, but don't count
  - `"count"`: Check, show, and include in waybar count
  - Pinned inputs are those with `original.rev` set in flake.lock
- `upstreamInfo.mode`: Whether input and source lines may resolve the upstream commit's **date** and the **number of commits behind** (default: `"api"`)
  - `"api"`: ask the host's API, turning `nixpkgs: 1a62cd4 → b03ef19` into `nixpkgs: 2026-10-14 → 2026-10-20 (412 commits)`. GitHub and Bitbucket are supported; any other host gets dates via `allowShallowFetch` below, and no count.
  - **Bitbucket** needs a different shape than GitHub. Its commit listing returns no total — the `size` field every other paginated collection there provides is simply absent for commits, at every page length and for every range — so the count is reached by walking, and the absence of a `next` link is what proves the running total is exact rather than a sample. A range of 100 or fewer therefore costs one request per direction. `fields=` trims each page from ~187 KB to ~3.4 KB, since only the page length and whether another follows are wanted. The walk stops at `UPSTREAM_INFO_PAGE_MAX` pages (default 5) and reports a floor — `(500+ commits)` — rather than following `next` for as long as a repository cares to produce pages.
    - Both directions are walked, so a Bitbucket line spends two of those requests: the reverse range is the only thing that tells *behind* apart from *diverged*, and no date ordering substitutes for it (upstream's tip being newer says when upstream last moved, not that your side carries nothing of its own). The reverse walk stops at one page, so a fork more than 100 commits ahead reads `(7 behind, 100+ ahead)` — a fork's own commits are the kind of thing there are tens of, and the exact number past that point wouldn't read any differently.
    - The date is taken from the shallow fetch when that's allowed, since it costs no API budget, and from `/commit/{rev}` only when it isn't.
    - Bitbucket's anonymous budget is also 60/hour, tracked **separately** from GitHub's, so a spent hour on one host doesn't stop the other resolving.
  - `"disabled"`: leave every line on the revision-pair form, with no network calls beyond the `git ls-remote` the check already makes
  - **Each enriched GitHub line costs one request**, not two. The comparison is issued with the sides reversed (`compare/{upstream}...{locked}`) because the response describes its *base* and only summarises its head — so the upstream commit's date and the behind-count both come out of a single call. Reading the head date from the response's `commits` array instead would be wrong rather than merely slower: that array is capped at 250 entries, so for anything nixpkgs-sized its last element is the 250th commit of the range and not upstream's tip at all.
  - A second request is made only for a `revision` or `package` source check, which has no local date to start from. Flake inputs never need it — `flake.lock` already records `lastModified` — and neither does a working tree.
  - Results are cached on the revision pair, so a line costs a request only when one of its sides actually moves, and a second checker reading the same pair costs nothing. Entries older than 30 days are pruned.
  - **GitHub's unauthenticated budget is 60 requests per hour against your whole outbound IP** — not per process, and shared with anything else making API calls from the same address. A handful of inputs on the default hourly interval sits well inside it; a large configuration, or a shared address, may not. Exhausting it is not an error: the reset time is recorded, calls are declined until it passes, and lines fall back to revision pairs meanwhile.
  - Degradation is per line, not per run: a GitHub input gets dates while a self-hosted one beside it falls back to `name: ce09258 (2025-10-13) → 10b877b`, keeping the locked date on the side it describes.
  - **The glyph states which way the two sides have moved:**

    | | line | meaning |
    |---|---|---|
    | `→` | `nixpkgs: 2026-10-14 → 2026-10-20 (412 commits)` | behind — a clean forward move |
    | `←` | `myfork: 2026-10-10 ← 2026-08-06 (85 ahead)` | ahead — upstream could move to you; nothing to pull |
    | `↔` | `inlyne: 2026-10-10 ↔ 2026-08-06 (51 behind, 85 ahead)` | diverged — both sides carry commits the other lacks |

    The operands keep their positions in all three — current on the left, upstream on the right — and only the glyph changes. Swapping them to express direction would mean you could no longer tell which side is yours without stopping to read the counts.
  - **Dates appear on every relationship**, whenever both can be resolved — `inlyne: 2026-10-10 ↔ 2026-08-06 (51 behind, 85 ahead)`. The glyph is what carries the direction, not the left-to-right order: the arrowhead always points at the more recent side, rightward when upstream is newer and leftward when yours is, while `↔` has a head at each end and so claims no order at all. A revision pair is the fallback for when a date can't be had, not a signal in itself.
  - **The suffix carries only counts that were actually counted.** The glyph already states the relationship, so nothing is hedged in prose — a `←` with no number after it says "ahead, by an amount nobody established". GitHub and Bitbucket both count the two directions, and the glyph follows those counts rather than the dates. A shallow fetch counts nothing, so such a host can reach `←` from the date ordering — upstream's tip predating yours takes commits of your own to explain — but never a number, and never `↔`, since the converse doesn't hold: a newer upstream rules nothing out about your side.
- `upstreamInfo.githubTokenFile`: Path to a file holding a GitHub token, read at check time to raise the budget from 60 to 5000 requests per hour (default: `null`)
  - A path rather than the token itself, so the secret stays out of the Nix store and out of the process table
  - Only public repository metadata is read, so **a token with no scopes selected is sufficient** and is what to use
- `upstreamInfo.allowShallowFetch`: Whether a non-GitHub remote may be asked for the upstream date with a shallow fetch, having no compare endpoint to ask instead (default: `true`)
  - Gets such a host to the standard format minus the suffix — `yamis-icon-theme: 2026-10-10 → 2026-10-18`. No commit distance comes out of it: counting commits needs the history between the two revisions, and deepening a fetch until it's present has no bound a tooltip refresh can live with.
  - **Size guard.** The cheap form (`--depth=1 --filter=tree:0`) needs the server to advertise `uploadpack.allowFilter`; one that doesn't serves the entire tree at that commit instead. A server can't be asked in advance which it will do, and a fetch can't be capped by size — so what arrived is measured afterwards. Past `UPSTREAM_INFO_FETCH_MAX_KIB` (default 2048) the filter is taken to have been ignored, and that **host** is recorded and not fetched from again for 30 days. A single commit object is a few KiB; a tree-bearing snapshot of any real repository is orders of magnitude more, so the threshold has wide margins on both sides.
    - The overrun therefore costs one fetch rather than one per hour, which is what makes this safe to leave on by default. The date from that one fetch is still used — it's already been paid for.
    - Recorded per host, not per repository, because filter support is a server configuration: one repository's answer holds for every repository beside it. Expired after 30 days so a host that upgrades git gets re-probed.
    - Each fetch uses a fresh scratch repository (created with `--template=` so no sample hooks skew the measurement) and deletes it afterwards, so nothing accumulates and the measurement reads that fetch rather than every fetch ever made.
  - Set to `false` to keep non-GitHub lines on the revision-pair form and make no fetches at all
  - GitHub inputs are unaffected either way
- `sourceChecks`: Explicit upstream policies for sources the package and input checks can't interpret on their own — fixed revisions in package expressions, local checkouts, named release lines, and forks. Each entry states a current source (`flake-input`, `package`, `revision`, `tag`, or `local`), an upstream `repository`, and a `policy` of `branch` or `tag`, so intent is declared rather than guessed. Set `mode` per entry to `"disabled"`, `"show"`, or `"count"`.
  - Checks run `git ls-remote`, bounded by `SOURCE_CHECK_TIMEOUT` (default 60s) per call, and are skipped entirely when there is no default route
  - Findings read `name: current → upstream`, the same grammar the Packages and Inputs sections use — `my-fork: 2026-09-12 → 2026-10-20 (17 commits)` under a branch policy, `helix: 25.01 → 25.07` under a tag policy. A tag policy gets no date enrichment on purpose: a release name is already the most legible thing either side could be called, so replacing it with the day it was cut would cost information rather than add it. A fork compared against a different upstream gets `←` or `↔`; see `upstreamInfo.mode` above.
  - **A `←` line is shown but not counted.** A current revision that's strictly ahead has nothing to pull, so putting a number on the waybar for it would be counting work that doesn't exist — and no rebuild could ever clear it. A `↔` line *is* counted: there are commits upstream to take, whatever else is also true. Behind by an unknown amount is counted too, since without a count there's no basis for claiming the difference runs only one way.
  - Misconfiguration is reported in the tooltip rather than passing silently: `current revision not found`, `upstream unreachable`, `unknown policy`, `Invalid sourceChecks configuration`. These keep the `name (reason)` shape rather than taking the colon, so a finding and a check that could not be made don't read as the same kind of statement.
  - **The `policy` must match the shape of the current value.** `branch` resolves upstream to a commit, `tag` resolves it to a tag name, and a commit never equals a tag name — so `current = "revision"` with `policy = "tag"` (or `current = "tag"` with `policy = "branch"`) reports an update on *every* run, forever, and no rebuild can clear it. Both combinations are now reported instead of compared:
    ```
    my-pin (tag policy needs a tag, got a revision)
    my-fork (branch policy needs a revision, got "v0.70.0")
    ```
    This applies to `revision`, `tag`, `local` and `package` alike. `flake-input` is exempt: it picks its current value from the policy, so it is consistent by construction.
    - **Behavior change.** A config with one of these pairings previously showed a permanent phantom update, and one set to `mode = "count"` was inflating the waybar badge by one. Both now become a tooltip line that doesn't count. If your count drops by one after upgrading, this is why — the check was never valid, and the tooltip now says so.
  - **A `tag` policy also verifies the current value is actually a tag upstream.** The shape rule rules out a commit, but a tag policy can still be handed something that only looks like a tag: a branch name from a flake input's `ref`, an abbreviated revision, a typo, or a tag renamed or deleted upstream. Each compares unequal to every real tag forever — the same permanent phantom update, in a shape no syntactic test can catch:
    ```
    hyprland ("main" is not a tag upstream)
    my-pin ("v0.70.99" is not a tag upstream)
    ```
    This closes the one gap the shape rule leaves, including `flake-input` with `policy = "tag"` where the input tracks a branch rather than a release. It costs nothing extra: the tag list is already fetched to find the latest, so a tag policy is still a single `ls-remote`.
    - Membership is tested against **every** tag, not just the ones `tagPattern` admits — so deliberately sitting on an older release line (`tag = "0.24.0"` with `tagPattern = "v*"`) still compares normally rather than being reported as broken.
  - **`current = "flake-input"` follows a local path override.** Pointing an input at a working copy (`url = "path:/home/you/src/thing"`) to test a change before pushing locks it to `{path, narHash}` with no `rev` — so the revision is read from that checkout's `HEAD` instead, and the check keeps working across the override rather than reporting a revision missing that plainly exists. A `policy = "tag"` override reads the nearest tag reachable from `HEAD`.
    - Uncommitted changes are named, because the tree is what got built, not the commit: a `HEAD` matching upstream reports `thing: 21f47db, uncommitted local changes` instead of going silent, and one behind upstream reports `thing: 21f47db + uncommitted → 8738e3e`. Neither is counted — there is nothing upstream to move to, which is what a count is for. A clean checkout sitting on upstream's tip reports nothing at all.
    - A path pointing somewhere that isn't a git checkout is reported as `local path override is not a git checkout`, which is deliberately distinct from the generic missing-revision message a typo'd input name produces.
  - **`current = "package"` reads the pin instead of restating it.** Give it an `attribute` (`"codex"`, or a dotted path like `"python3Packages.foo"`) and it evaluates that package's `src`, taking both the current revision and the `repository` from it — so the pin lives only in the package expression, and only the upstream policy is configured here:
    ```nix
    sourceChecks = [{
      name = "codex";
      mode = "count";
      current = "package";
      attribute = "codex";
      policy = "tag";
      tagPattern = "rust-v*";
    }];
    ```
    - Works for sources fetched with `fetchFromGitHub`, `fetchFromGitLab`, `fetchFromGitea` or `fetchgit`, all of which pass `rev`/`tag` and `gitRepoUrl` through to the fetched derivation. A release tarball or a vendored source carries no revision and is reported as `no revision in "<attr>" src` rather than passing silently.
    - Costs one `nix eval` per package check — measured around 4s warm — bounded by `PACKAGE_EVAL_TIMEOUT` (default 120s).
    - **`overrideAttrs` is recognised through an overlay, not inline.** The attribute is resolved by name against the configuration's own package set (`nixosConfigurations.<host>.pkgs`, then `homeConfigurations.<user>.pkgs`), so an overlay that pins a source is read correctly. An `overrideAttrs` applied at the point of use — inside `environment.systemPackages` or `home.packages` — is not reachable by name, and the check would read the unpinned nixpkgs version and compare the wrong thing. Pin through an overlay.
    - The shape rule above applies here too, and bites more easily because you never see the pin: use `"tag"` for a src pinned to a tag and `"branch"` for one pinned to a commit.
    - `tagPattern` matters more here than for a hand-written pin, because you never see the tag's shape. A repository that tags subcrates alongside releases — ripgrep tags `wincolor-0.1.6` — returns the wrong "latest" under the default `"*"`. Anchor the pattern to the release line the package follows.
    - Setting `repository` explicitly still wins, which is how you track a fork's upstream rather than the URL the package fetches from.
  - Only an *unset* `SOURCE_CHECKS_JSON` means "no checks configured". An empty or malformed value is reported as invalid rather than read as an empty list, so a broken environment can't look like a clean result
- `customChecks`: Arbitrary commands run on the same cycle as the update check, with their stdout folded into the tooltip under a **Checks** section. The escape hatch for things worth knowing on a schedule that aren't package or flake-input updates and so can't be derived from the flake — a retired API model id, an expiring certificate, a drifted remote.
  - **The contract is plain text, not JSON.** A line of output is a thing worth reporting; no output is a clean result and prints nothing. Your script needs no `jq` and no awareness of this project's internals.
  - Set `mode` per entry to `"disabled"`, `"show"`, or `"count"`. With `"count"` each output line also adds one to the waybar badge, which is what makes a check *visible* — `"show"` only ever reaches someone already hovering over the module.
  - `requiresNetwork` (default `true`) skips the check when there's no default route, so a network-dependent check doesn't fail every cycle on a disconnected machine. Set it `false` for a purely local check.
  - Failures are reported rather than swallowed: a command that is missing, crashes, or exceeds `CUSTOM_CHECK_TIMEOUT` (default 60s) shows up as `name (exit N)` or `name (timed out)`. Silence already means "all clear", so a broken check must not be able to imitate it.
  - Commands run through `bash -c`, so a pipeline is fine. `PATH` is inherited rather than replaced, but a waybar session's `PATH` is not the one you tested in — prefer an absolute store path.
  - With one check reporting, its output appears verbatim. With two or more, each block gets a `name:` header so you can tell them apart.
  - Only an *unset* `CUSTOM_CHECKS_JSON` means "no checks configured". An empty or malformed value is reported as `Invalid customChecks configuration` rather than read as an empty list.

    ```nix
    customChecks = [{
      name = "Anthropic models";
      mode = "count";
      command = "${pkgs.anthropic-model-check}/bin/anthropic-model-check";
    }];
    ```

    A check that prints nothing contributes nothing. One that prints two lines with `mode = "count"` adds 2 to the badge and both lines to the tooltip:

    ```
    Checks:
    smartcat: claude-sonnet-4-20250514 no longer resolves
    zed: claude-sonnet-4-5 is 2 generations behind
    ```

**Both modes:**
- `nixosConfigPath`: Path to your NixOS configuration flake directory (default: `~/.config/nixos`)
  - Full mode: Used for `nix build` and `nvd diff`
  - Lightweight mode: Used for reading `flake.lock` and scanning `.nix` files for package sources

**Full mode only:**
- `updateLockFile`: Whether to update the lock file directly or use a temporary copy (default: false)

**Lightweight mode only:**
- `nixpkgsChannel`: Either a single flake ref string, or an attrset for dual-channel mode:
  - Simple (single channel): `"github:NixOS/nixpkgs/nixpkgs-unstable"`
  - Dual channel (mixed stable/unstable):
    ```nix
    {
      stable = "pkgs";                 # Identifier for stable packages
      unstable = "pkgs-unstable";      # Identifier for unstable packages
    }
    ```
  - In dual-channel mode, `nixosConfigPath` is scanned for `.nix` files to determine package sources, and flake refs are auto-detected from your `flake.lock`
- `explicitPackagesOnly`: Only report updates for packages explicitly defined in your config files (default: `true` in dual-channel mode, `false` otherwise)
- `dryRunPreview.enable`: Adds an on-demand update-cost preview on **middle-click** (default: `false`). Resolves a temporary lock file and runs a Nix dry-run to report how many derivations would be built and how much would be downloaded if you updated your flake inputs and rebuilt. Your `flake.lock` and configuration are never modified, and the update count is unchanged.
  - Never runs on a timer. A preview is a full system evaluation — roughly 2–3 minutes and well over a gigabyte of memory — so it only runs when you ask for it.
  - Where possible it also estimates **time**, fetching first because it usually dominates: one measured rebuild here spent 30 of its 43 minutes fetching and 13 building.
    ```
    Update cost (14:23):
    621 to download · 62 to build
    ~26m to fetch & unpack (1.8 GiB, 5.3 GiB)
    ~16m+ build (48 timed of 62)
    ```
    Nix records no build durations, so both figures come from the gaps between path registrations in your own store: a substitution rate from fetched paths, build time from the median of each package's past local builds. That makes the estimate **self-calibrating to your machine** — your CPU, disk and link — rather than depending on shipped constants. Nothing is shared between machines, and none is needed.
    - **`fetch & unpack` is the whole operation, not the transfer.** A path is registered only once it has been downloaded, decompressed *and* written, so all three are inside that figure. On one measured machine decompression ran at ~420 MiB/s — under 1% of a fetch-bound job — but on a fast link and a slow CPU it would dominate, and the same measurement absorbs either case.
    - **The two sizes are the wire and the disk**, in the order the label names them: `1.8 GiB` is what crosses the network, `5.3 GiB` is what it becomes on disk. The estimate is computed from the second against a rate measured in the same uncompressed units — the store database records `narSize` and has no column for the compressed size — which holds exactly when a job compresses like your past ones did. One sample gave 3.64× historically against 2.94× for the job being priced, so treat it as an assumption that mostly cancels rather than one that always does.
    - `(48 timed of 62)` is the coverage, counted in derivations, so it agrees with the build count above it. A derivation never built on this machine has no timing sample and contributes nothing to the sum — so anything short of full coverage makes the figure a **floor**, which is what the trailing `+` on `~16m+` marks. At full coverage the `+` disappears. Expect roughly ±30% even then; remote builders and heavy parallelism skew it further.
    - History is matched per package **version**, so `waybar` draws on past builds of `waybar-0.13.0` but not on `waybar-nixos-updates-4.1`, whose name merely starts the same way.
    - The two estimates overlap, since Nix fetches while it builds — treat the wall clock as nearer the larger of them than their sum.
    - A fresh install has no history, and an unreadable store database simply omits the line rather than guessing.
  - The result is stamped with the time it was taken, and stops being shown once it no longer describes anything. Three things retire it: your `flake.lock` changes, a check finds something different from what the cost was priced against, or **the packages your configuration declares change** — one added or removed adds or drops a whole closure from the plan.
  - **A rebuild on its own marks the cost rather than discarding it.** Once `/run/current-system` no longer matches, the stamp reads `Update cost (14:23, pre-rebuild)` and the numbers stay. A rebuild that only changes settings shifts the plan by a few config-file derivations against hundreds of paths, which is not worth throwing away a three-minute evaluation for; a rebuild that adds a package is caught by the declared-package key above, and retires the cost outright.
    - The package key reads your `.nix` files rather than the built system, so it fires when you **save**, not when you rebuild — the plan changes at the edit either way. It is deliberately not derived from `nvd`: measured across 19 real commits of one configuration, `nvd` reported added packages for config-generated systemd units and for transitive dependencies pulled in by ordinary upgrades, while the declared list stayed put for all 15 settings-only commits and moved for exactly the 4 that changed packages.
    - The extraction is a heuristic and its contents are noisy; only whether it *changed* matters here, so a stable false positive cancels. If it can find nothing to read it simply never fires, rather than retiring a cost on no evidence.
  - Setting this back to `false` removes the binding *and* clears any result already computed.
  - Shares a lock with the background check, so the two never evaluate at once. Middle-clicking during a check reports `check in progress — try again shortly` rather than queueing.
  - `dryRunPreview.target`: flake target to price; literal `${hostname}` is replaced at run time. A leading `.#` resolves against `nixosConfigPath`, not your shell's working directory.
  - `dryRunPreview.recalculateOnChange`: Recompute the cost by itself when it goes stale, instead of showing `middle-click to recalculate` and waiting (default: `false`). Requires `dryRunPreview.enable`.
    - Fires on all three staleness reasons above: `flake.lock` changing, a check finding something different, and the declared package set changing. **Not on a rebuild alone**, which is consistent with a rebuild no longer retiring a cost — what happens after one is already `afterRebuild`'s business, and each of its options leads to a check whose result fires this anyway.
    - **Only ever refreshes a cost you already have.** With no stored result it does nothing, so the first preview on any machine is always a middle-click and enabling this cannot commit a machine to an evaluation it has never asked for. Middle-click once to establish a baseline; after that it maintains itself.
    - Each recompute costs what a preview costs — the 2–3 minutes and gigabyte above. There is no minimum interval between automatic recomputes, so on a fast-moving channel with a short `updateInterval` this can run several times a day.
    - Skipped, not queued, when the check holds the lock. It runs on a later poll instead, which is the right order anyway: the check settles what the new cost should be priced against.
    - A failed recompute is not retried. The cost reads `unavailable` until you middle-click, rather than re-attempting a several-minute evaluation on a schedule.
- `lightweightExcludePatterns`: Shell patterns for generated store outputs to skip before version parsing (default: `[ "*-fish-completions" ]`). Outputs like `atuin-18.7.1-fish-completions` otherwise have their suffix read as part of the version, showing a phantom update. Keep patterns anchored — `*-completions` would also drop real packages such as `nix-bash-completions`.

**Lightweight mode features:**
- **Home-manager packages**: Automatically detected and included (no config needed)
- **Dual-channel support**: Parses your nix configs to determine which packages are stable vs unstable
- **Caching**: Parse results are cached and only refreshed when `flake.lock` changes

You can also modify these environment variables or set them at the top of the script to customize behavior:

**Common variables (both modes):**
- `UPDATE_INTERVAL`: Time in seconds between update checks (default: 3599)
- `CACHE_DIR`: Directory for storing cache files (default: ~/.cache)
- `NOTIFICATIONS_ENABLED`: Set to "false" to disable desktop notifications (default: "true")
- `SKIP_AFTER_BOOT`: Whether to skip update checks right after boot/resume (default: true)
- `GRACE_PERIOD`: Time in seconds to wait after boot/resume before checking (default: 60)
- `CLOCK_FORMAT`: Clock format for tooltip timestamps: "24h" | "12h" (default: "24h")
- `INPUT_CHECKER_MODE`: How to handle stale inputs: "disabled" | "show" | "count" (default: "disabled")
- `INPUT_CHECKER_PINNED`: How to handle pinned inputs: "disabled" | "show" | "count" (default: "disabled")

**Full mode variables:**
- `NIXOS_CONFIG_PATH`: Path to your NixOS configuration (default: ~/.config/nixos)
- `UPDATE_LOCK_FILE`: Whether to update the lock file directly or use a temporary copy (default: false)

**Lightweight mode variables:**
- `FLAKE_DIR`: Path to flake directory - used for reading `flake.lock` and scanning `.nix` files (default: ~/.config/nixos)
- `NIXPKGS_CHANNEL`: Nixpkgs flake ref for single-channel mode (e.g., "github:NixOS/nixpkgs/nixpkgs-unstable")
- `DUAL_CHANNEL_MODE`: Set to "true" to enable dual-channel detection from flake.lock (default: "false")
- `EXPLICIT_PACKAGES_ONLY`: Only report updates for packages explicitly in config files (default: "true" when `DUAL_CHANNEL_MODE` is enabled, "false" otherwise). This filters out system dependencies and provides more accurate results.
- `STABLE_IDENTIFIER`: Identifier for stable packages in dual-channel mode (default: "pkgs")
- `UNSTABLE_IDENTIFIER`: Identifier for unstable packages in dual-channel mode (default: "pkgs-unstable")

### 🔄 Toggle Functionality
The script supports toggling update checks on/off. When disabled, it will show the last known state without performing new checks:
- To toggle: Run `update-checker toggle`
- The toggle state is preserved across restarts
- When disabled, the module shows "disabled" state with the last check timestamp

### 🎨 Waybar Integration

If you're using the Home Manager module, the waybar configuration is automatically provided through `config.programs.waybar-nixos-updates.waybarConfig`. It emits `on-click-middle` only when `dryRunPreview.enable = true`, so the preview cannot be triggered by accident on a default configuration. Otherwise, configure manually:

To configure manually, add one of the following configurations to your Waybar config (`~/.config/waybar/config`).

In json (if adding directly to the config file):
```json
"custom/nix-updates": {
    "exec": "$HOME/bin/update-checker", // <--- path to script
    "signal": 12,
    "on-click": "$HOME/bin/update-checker toggle", // toggle update checking
    "on-click-right": "$HOME/bin/update-checker refresh", // force an update
    // Optional: on-demand update-cost preview. Omit this line to leave the
    // feature unbound. Requires the `preview` helper script on your PATH.
    "on-click-middle": "$HOME/bin/update-checker preview",
    "interval": 3600, // refresh every hour
    "tooltip": true,
    "return-type": "json",
    "format": "{} {icon}",
    "format-icons": {
        "has-updates": "󰚰", // icon when updates needed
        "updating": "", // icon when updating
        "updated": "", // icon when all packages updated
        "disabled": "󰚰", // icon when update checking is disabled
        "error": "" // icon when errot occurs
    },
},
```

In nix (if adding it "the nix way" through home-manager):
```nix
"custom/nix-updates" = {
  exec = "$HOME/bin/update-checker";  # Or "${pkgs.waybar-nixos-updates}/bin/update-checker" if using the flake
  signal = 12;
  on-click = "$HOME/bin/update-checker toggle";  # Toggle update checking
  on-click-right = "$HOME/bin/update-checker refresh";  # Force an update
  # Optional: on-demand update-cost preview. Omit this line to leave the
  # feature unbound. Requires the `preview` helper script on your PATH.
  on-click-middle = "$HOME/bin/update-checker preview";
  interval = 3600;
  tooltip = true;
  return-type = "json";
  format = "{} {icon}";
  format-icons = {
    has-updates = "󰚰";
    updating = "";
    updated = "";
    disabled = "󰚰";
    error = "";
  };
};
```

**Note:** If using the Home Manager module, you can simply reference the pre-configured waybar settings:
```nix
programs.waybar.settings.mainBar."custom/nix-updates" = 
  config.programs.waybar-nixos-updates.waybarConfig;
```

To style use the `#custom-nix-updates` ID in your Waybar styles file (`~/.config/waybar/styles.css`). For more information see the [Waybar wiki](https://github.com/Alexays/Waybar/wiki).

### 💡 Complete Configuration Example

Here's a complete example of using waybar-nixos-updates with Home Manager:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    waybar-nixos-updates.url = "github:yourusername/waybar-nixos-updates";
  };

  outputs = { self, nixpkgs, home-manager, waybar-nixos-updates, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        home-manager.nixosModules.home-manager
        {
          home-manager.users.youruser = { config, ... }: {
            imports = [ waybar-nixos-updates.homeManagerModules.default ];
            
            # Enable the waybar-nixos-updates module
            programs.waybar-nixos-updates = {
              enable = true;
              checkMode = "lightweight";  # default; "full" is exact but rebuilds every check
              updateInterval = 3600;
              notifications = true;       # set to false to disable notifications
              
              # For single-channel (all packages from one nixpkgs):
              # nixpkgsChannel = "github:NixOS/nixpkgs/nixpkgs-unstable";
              
              # For dual-channel (mixed stable + unstable packages):
              # nixosConfigPath is used to scan .nix files for package sources
              nixpkgsChannel = {
                stable = "pkgs";
                unstable = "pkgs-unstable";
              };
            };
            
            # Configure Waybar
            programs.waybar = {
              enable = true;
              settings = {
                mainBar = {
                  modules-right = [ "custom/nix-updates" "clock" "battery" ];
                  "custom/nix-updates" = config.programs.waybar-nixos-updates.waybarConfig;
                };
              };
              style = ''
                #custom-nix-updates {
                  color: #89b4fa;
                  margin: 0 10px;
                }
                #custom-nix-updates.has-updates {
                  color: #f38ba8;
                  font-weight: bold;
                }
                #custom-nix-updates.updating {
                  color: #f9e2af;
                }
                #custom-nix-updates.disabled {
                  color: #6c7086;
                  opacity: 0.7;
                }
                #custom-nix-updates.error {
                  color: #eba0ac;
                }
              '';
            };
          };
        }
      ];
    };
  };
}
```

### 📤 Flake Outputs

The flake provides the following outputs:

- **packages.default**: The waybar-nixos-updates package (full mode)
- **packages.lightweight**: The lightweight checker package
- **homeManagerModules.default**: Home Manager module for user-level configuration
- **nixosModules.default**: NixOS module for system-level installation
- **apps.default**: Direct execution of the update-checker script (full mode)
- **apps.lightweight**: Direct execution of the lightweight-checker script

### 🔍 Troubleshooting

#### Common Issues and Solutions

1. **Script not finding NixOS configuration**
   - Ensure your configuration is at `~/.config/nixos` or update the `nixosConfigPath` option
   - Verify your hostname matches your nixosConfiguration name: `echo $HOSTNAME`

2. **Icons not displaying**
   - When using Home Manager module, icons are automatically installed to `~/.icons`
   - For manual installation, ensure icons are in `~/.icons/` directory
   - Check that your notification daemon supports PNG icons

3. **Updates not being detected**
   - Check network connectivity: `ping -c 1 8.8.8.8`
   - Verify nvd is installed: `which nvd`
   - Clear cache and force update: `rm ~/.cache/nix-update-* && pkill -RTMIN+12 waybar`

4. **"Check tooltip for detailed error message"**
   - Hover over the waybar module to see the full error
   - Common causes: missing dependencies, flake evaluation errors, network issues

5. **Module shows "updating" indefinitely**
   - In lightweight mode a background check may still be running; it holds `~/.cache/nix-update-check.lock` for its duration
   - A check still holding the lock after 15 minutes is treated as wedged — its process group is killed and the next check proceeds. Override with `MAX_CHECK_SECONDS`.
   - Force a fresh check: `update-checker refresh` — this keeps the current count, tooltip and last-checked time on screen, and swaps the header's "Next check" for "Checking for updates..." while it runs
   - Refreshing while a check is already running shows a "Please Wait" notification instead of doing nothing, and does not queue a second check for when the current one finishes
   - In full mode, clear the updating flag: `rm ~/.cache/nix-update-updating-flag`
   - Restart waybar: `pkill waybar && waybar &`

6. **Configuration changes not taking effect**
   - When using the wrapper script, restart waybar after rebuilding
   - Verify the correct script is being executed: check waybar config `exec` path

### ⚡ System Integration
No integration is required. The checker automatically detects both rebuilds and flake input updates on its own - you do **not** need to modify your rebuild script or `nix flake update` aliases, and there are no flag files to `touch`.

#### Automatic Rebuild Detection
The checker caches the `/run/current-system` path (in `nix-update-system-path`) and compares it on each run. When it changes, the system has been rebuilt. It then runs `nvd diff` on the two existing store paths — no building, since both closures already exist, though it is not instant either (~4s here) — to distinguish a real package update from a config-only rebuild:
- **Package versions changed:** handled according to `afterRebuild` — re-checked, reconciled against what the diff shows changed, or assumed applied.
- **Config-only rebuild:** the existing package state is preserved, so a config change doesn't clear a pending update count.

#### Automatic Input-Update Detection
The checker caches a hash of your `flake.lock` (in `nix-update-flake-lock-input-hash`). When the hash changes - i.e. any input was updated via `nix flake update`, regardless of which command or alias ran - it triggers an immediate input re-check while preserving package state.

#### Automatic Check-Definition Detection
`sourceChecks` and `customChecks` results are cached, so that a rebuild can redraw the Sources and Checks sections without re-running network calls or your commands. But a cached finding is only worth anything while two things hold: the definition that asked for it, and the code that produced it. Both arrive with a rebuild — the definitions from your configuration, the code from an upgrade — and a rebuild is also the one moment those cached results get replayed instead of recomputed.

So the checker caches a hash (in `nix-update-check-defs-hash`) covering both lists *and* the content of the checker scripts themselves. When it changes, the cached results are answers to a question no longer being asked, and both `afterRebuild` fast paths degrade to `recheck` rather than redrawing them.

Without this, editing a check and rebuilding kept showing what the *old* run found, for up to a full `updateInterval` afterwards — so a `sourceChecks` entry corrected to point at the right branch went on reporting the phantom update the wrong branch produced, and the fix looked like it had not worked. The same held for upgrading the module itself: the new code never got to speak, because the rebuild that installed it also stamped `last-run` as though a check had just completed.

The scripts are hashed by content rather than by store path, so this works for a checkout run in place during development, and a version bump that changes no behaviour doesn't force a check for nothing.

Because of the above, a rebuild/update script can be as simple as:
```nix
nixup =
  "pushd ~/.config/nixos &&
  echo \"NixOS rebuilding...\" &&
  sudo nixos-rebuild switch --upgrade --flake .#hyprnix &&
  popd";
```
Waybar will reflect the new state on its next poll (or immediately if you send it the `RTMIN+12` signal via `pkill -x -RTMIN+12 .waybar-wrapped`).

## ℹ️ Additional Information
Some additional things to expect in regards to 1) what notifications you'll receive, 2) what files will be written, 3) and how the script uses your network connection.

### 🔔 Notifications
These notifications require `notify-send` to be installed on your system. The script sends desktop notifications to keep you informed.

**To disable notifications:** Set `notifications = false;` in your Home Manager configuration, or set the environment variable `NOTIFICATIONS_ENABLED="false"`.

Notifications include:
- When starting an update check: "Checking for Updates - Please be patient"
- When throttled due to recent checks: "Please Wait" with time until next check
- When updates are found: "Update Check Complete" with the number of updates
- When no updates are found: "Update Check Complete - No updates available"
- When connectivity fails: "Update Check Failed - Not connected to the internet"
- When an update fails: "Update Check Failed - Check tooltip for detailed error message"

### 💾 Cache Files
The script uses several cache files in your ~/.cache directory:
- `nix-update-state`: Stores the current number of available updates
- `nix-update-last-run`: Tracks when the last update check was performed
- `nix-update-tooltip`: Contains the tooltip text with update details
- `nix-update-boot-marker`: Used to detect system boot/resume events
- `nix-update-toggle`: Stores the enabled/disabled state for update checking
- `nix-update-system-path`: Caches the last-seen `/run/current-system` path, used to auto-detect rebuilds
- `nix-update-flake-lock-input-hash`: Caches a hash of `flake.lock`, used to auto-detect input updates
- `nix-update-updating-flag`: Signals that a check is mid-run (full mode only)
- `nix-update-check.lock`: Held while a background check runs, so only one runs at a time (lightweight mode only)
- `nix-update-error`: Present when the last check failed, holding the reason; makes the module show its error state instead of a healthy count. Removed by the next successful check.
- `nix-update-diagnostic` / `.prev`: What the last two checks actually resolved — channels, package-to-channel mapping size, and for each reported package which channel it was compared against versus which one the mapping put it in. The previous run is kept because a wrong result is usually followed immediately by a correct one, which would otherwise overwrite the evidence. If the module reports something you don't expect, `cat ~/.cache/nix-update-diagnostic.prev` is the place to start.
- `nix-update-source-count` / `-shown` / `-tooltip`: Last `sourceChecks` result, so a rebuild can redraw the Sources section without reaching the network
- `nix-update-custom-count` / `-shown` / `-tooltip`: Last `customChecks` result, so a rebuild can redraw the Checks section without re-running your commands
- `nix-update-check-defs-hash`: Hash of the `sourceChecks` and `customChecks` definitions, plus the content of the checker scripts, that produced the two results above. When it no longer matches, those results are discarded instead of redrawn — see [Automatic Check-Definition Detection](#automatic-check-definition-detection)
- `nix-update-force-check`: Set by `refresh` to request a check before the interval is up; cleared once that check starts
- `nix-update-result-hash`: Fingerprint of what the last check found, used to expire a stored update-cost preview when upstream moves
- `nix-update-preview`: Last update-cost preview, with the `flake.lock` hash and system path it was computed against, plus the evaluating process while one is running so an interrupted preview is reported rather than left reading "calculating"; removed when `dryRunPreview.enable` is `false`

### 🔒 Privacy and Security Considerations
The script checks network connectivity locally using the `ip` command to verify network interfaces and routing tables. This approach:
- Does not send any external network requests for connectivity checking
- Only checks local network configuration (interfaces and routes)
- Performs actual network requests only when fetching updates from configured Nix repositories
- Provides better privacy as no external connectivity checks are performed

## 🤝 Contributing

PRs are welcome! Please test your changes and ensure they work with both the flake installation methods and manual installation.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
