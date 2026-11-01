{
  description = "A Waybar update checking script for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        # The update-checker script package
        waybar-nixos-updates = pkgs.stdenv.mkDerivation {
          pname = "waybar-nixos-updates";
          version = "4.8";
          
          src = ./.;
          
          nativeBuildInputs = with pkgs; [
            makeWrapper
          ];
          
          installPhase = ''
            runHook preInstall
            
            # Install the script
            mkdir -p $out/bin
            cp update-checker $out/bin/update-checker
            chmod +x $out/bin/update-checker
            cp source-checker $out/bin/source-checker
            chmod +x $out/bin/source-checker
            cp upstream-info $out/bin/upstream-info
            chmod +x $out/bin/upstream-info
            cp format-upstream-line $out/bin/format-upstream-line
            chmod +x $out/bin/format-upstream-line
            cp custom-checker $out/bin/custom-checker
            chmod +x $out/bin/custom-checker
            cp preview $out/bin/preview
            chmod +x $out/bin/preview
            
            # Install icons
            mkdir -p $out/share/icons/waybar-nixos-updates
            if [ -d .icons ]; then
              cp -r .icons/* $out/share/icons/waybar-nixos-updates/
            fi
            
            # Wrap the script with required dependencies
            wrapProgram $out/bin/update-checker \
              --prefix PATH : "$out/bin:${pkgs.lib.makeBinPath [
                pkgs.coreutils
                pkgs.findutils
                pkgs.libnotify
                pkgs.nvd
                pkgs.nixVersions.stable
                pkgs.gnugrep
                pkgs.gawk
                pkgs.gnused
                pkgs.jq
                pkgs.procps
                pkgs.systemd
                pkgs.iproute2
                pkgs.inetutils
                pkgs.util-linux  # flock - serialises the check
                pkgs.sqlite  # reads the nix store db for build-time estimates
                pkgs.git  # source-checker
                pkgs.curl  # upstream-info: the GitHub compare API
              ]}"
            
            runHook postInstall
          '';
          
          meta = with pkgs.lib; {
            description = "A Waybar update checking script for NixOS";
            homepage = "https://github.com/guttermonk/waybar-nixos-updates";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.linux;
          };
        };
        
        # Lightweight mode: uses lazy nix eval instead of a full build + nvd diff
        waybar-nixos-updates-lightweight = pkgs.stdenv.mkDerivation {
          pname = "waybar-nixos-updates-lightweight";
          version = "4.8";
          
          src = ./.;
          
          nativeBuildInputs = with pkgs; [
            makeWrapper
          ];
          
          installPhase = ''
            runHook preInstall
            
            mkdir -p $out/bin
            cp lightweight-checker $out/bin/lightweight-checker
            chmod +x $out/bin/lightweight-checker
            cp source-checker $out/bin/source-checker
            chmod +x $out/bin/source-checker
            cp upstream-info $out/bin/upstream-info
            chmod +x $out/bin/upstream-info
            cp format-upstream-line $out/bin/format-upstream-line
            chmod +x $out/bin/format-upstream-line
            cp custom-checker $out/bin/custom-checker
            chmod +x $out/bin/custom-checker
            cp preview $out/bin/preview
            chmod +x $out/bin/preview
            
            # Install icons (for notifications)
            mkdir -p $out/share/icons/waybar-nixos-updates
            if [ -d .icons ]; then
              cp -r .icons/* $out/share/icons/waybar-nixos-updates/
            fi
            
            wrapProgram $out/bin/lightweight-checker \
              --prefix PATH : "$out/bin:${pkgs.lib.makeBinPath [
                pkgs.coreutils
                pkgs.findutils
                pkgs.gnugrep
                pkgs.gawk
                pkgs.gnused
                pkgs.procps
                pkgs.systemd
                pkgs.iproute2
                pkgs.jq
                pkgs.nvd
                pkgs.nixVersions.stable
                pkgs.libnotify
                pkgs.util-linux  # flock, setsid - background check serialisation
                pkgs.sqlite  # reads the nix store db for build-time estimates
                pkgs.git  # source-checker
                pkgs.curl  # upstream-info: the GitHub compare API
              ]}"

            runHook postInstall
          '';
          
          meta = with pkgs.lib; {
            description = "Lightweight NixOS update checker using lazy nix eval";
            homepage = "https://github.com/guttermonk/waybar-nixos-updates";
            license = licenses.mit;
            maintainers = [ ];
            platforms = platforms.linux;
          };
        };

        # Flake input checker: compares locked revs against upstream via git ls-remote
        waybar-nixos-updates-inputs = pkgs.stdenv.mkDerivation {
          pname = "waybar-nixos-updates-inputs";
          version = "4.8";
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp input-checker $out/bin/input-checker
            chmod +x $out/bin/input-checker
            cp upstream-info $out/bin/upstream-info
            chmod +x $out/bin/upstream-info
            cp format-upstream-line $out/bin/format-upstream-line
            chmod +x $out/bin/format-upstream-line
            # $out/bin first, as the other two packages already do: the checker
            # calls format-upstream-line, which calls upstream-info, and
            # neither is on a PATH this package controls otherwise.
            wrapProgram $out/bin/input-checker \
              --prefix PATH : "$out/bin:${pkgs.lib.makeBinPath [
                pkgs.coreutils
                pkgs.git
                pkgs.jq
                pkgs.curl  # upstream-info: the GitHub compare API
                pkgs.findutils  # upstream-info: cache and scratch pruning
                pkgs.gnugrep  # upstream-info: reads the rate-limit rejection
                pkgs.iproute2  # have_network: is there a default route
              ]}"
            runHook postInstall
          '';
          meta = with pkgs.lib; {
            description = "Flake input staleness checker for Waybar";
            homepage = "https://github.com/guttermonk/waybar-nixos-updates";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
      in
      {
        packages = {
          default = waybar-nixos-updates;
          waybar-nixos-updates = waybar-nixos-updates;
          inputs = waybar-nixos-updates-inputs;
          lightweight = waybar-nixos-updates-lightweight;
        };
        
        apps.default = flake-utils.lib.mkApp {
          drv = waybar-nixos-updates;
          name = "update-checker";
        };

        apps.inputs = flake-utils.lib.mkApp {
          drv = waybar-nixos-updates-inputs;
          name = "input-checker";
        };

        apps.lightweight = flake-utils.lib.mkApp {
          drv = waybar-nixos-updates-lightweight;
          name = "lightweight-checker";
        };
      }) // {
        # Home-Manager module
        homeManagerModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.programs.waybar-nixos-updates;
            isLightweight = cfg.checkMode == "lightweight";
            checkerBin = if isLightweight
              then "${self.packages.${pkgs.stdenv.hostPlatform.system}.lightweight}/bin/lightweight-checker"
              else "${cfg.package}/bin/update-checker";
            sourceCheckType = types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Display name shown in the tooltip.";
                };
                mode = mkOption {
                  type = types.enum [ "disabled" "show" "count" ];
                  default = "show";
                  description = "Whether to skip this check, show it only, or also add it to the waybar count.";
                };
                current = mkOption {
                  type = types.enum [ "flake-input" "package" "revision" "tag" "local" ];
                  description = "Where the currently configured version comes from.";
                };
                input = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Flake input name, when current = \"flake-input\".";
                };
                attribute = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  example = "codex";
                  description = ''
                    Package attribute to read the pin out of, when current = "package".
                    Dotted paths work ("python3Packages.foo").

                    The attribute is resolved against the configuration's own package set,
                    so an overlay that pins a source is what gets read. An overrideAttrs
                    applied at the point of use - inside environment.systemPackages or
                    home.packages - is not reachable by name and will read the unpinned
                    nixpkgs version instead. Pin through an overlay for this to be correct.
                  '';
                };
                revision = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Pinned commit, when current = \"revision\".";
                };
                tag = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Pinned tag, when current = \"tag\".";
                };
                path = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Local git checkout, when current = \"local\".";
                };
                repository = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    Canonical upstream Git repository URL to compare against.

                    Required for every source except current = "package", which reads it
                    from the package's own src. Set it there too to track a different
                    upstream than the one the package fetches from, which is the usual
                    case for a fork.
                  '';
                };
                policy = mkOption {
                  type = types.enum [ "branch" "tag" ];
                  description = "Whether upstream is the tip of a branch or the latest matching tag.";
                };
                ref = mkOption {
                  type = types.str;
                  default = "HEAD";
                  description = "Branch to track, when policy = \"branch\".";
                };
                tagPattern = mkOption {
                  type = types.str;
                  default = "*";
                  description = "Shell pattern the tag must match, when policy = \"tag\".";
                };
                excludeTagPatterns = mkOption {
                  type = types.listOf types.str;
                  default = [ "*-alpha*" "*-beta*" "*-rc*" "*-pre*" ];
                  description = "Tag patterns to ignore, so prereleases don't register as updates.";
                };
              };
            };

            customCheckType = types.submodule {
              options = {
                name = mkOption {
                  type = types.str;
                  description = "Display name, used as a tooltip header and in failure messages.";
                };
                mode = mkOption {
                  type = types.enum [ "disabled" "show" "count" ];
                  default = "show";
                  description = "Whether to skip this check, show it only, or also add it to the waybar count.";
                };
                command = mkOption {
                  type = types.str;
                  description = ''
                    Command to run. Its stdout is the result: one line per thing worth
                    reporting, and no output at all when there is nothing to report.

                    Run through `bash -c`, so a pipeline is fine. PATH is inherited
                    rather than replaced, but a waybar session's PATH is not the one
                    you tested in -- prefer an absolute store path.
                  '';
                };
                requiresNetwork = mkOption {
                  type = types.bool;
                  default = true;
                  description = ''
                    Skip this check when there is no default route. Defaults to true
                    because a check worth running on a timer usually reaches out
                    somewhere, and one that fails every cycle on a disconnected
                    machine is noise. Set false for a purely local check.
                  '';
                };
              };
            };
          in {
            options.programs.waybar-nixos-updates = {
              enable = mkEnableOption "waybar-nixos-updates";
              
              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.stdenv.hostPlatform.system}.waybar-nixos-updates;
                defaultText = literalExpression "waybar-nixos-updates";
                description = "The waybar-nixos-updates package to use.";
              };
              
              checkMode = mkOption {
                type = types.enum [ "lightweight" "full" ];
                default = "lightweight";
                description = ''
                  Update check strategy.

                  "lightweight" (default) resolves each package's .version attribute
                  by lazy nix eval and compares it against what is installed. Nothing
                  is built or downloaded. Fast - measured around two minutes - and
                  approximate: it reports version differences, so a package whose
                  version is unchanged but whose dependencies moved is not counted.

                  "full" resolves a speculative lock and then *realises the closure* -
                  it runs `nix build` on the new system and diffs it against the
                  current one with nvd. That is exactly as accurate as a rebuild,
                  because it performs the fetching and building a rebuild would, then
                  reports what changed.

                  The cost of "full" is therefore the cost of the update itself, not
                  of inspecting it: every scheduled check downloads and builds the
                  entire pending update in the background. On a large or long-deferred
                  update that is gigabytes of traffic and many minutes of CPU, and it
                  repeats on every updateInterval until you rebuild. Enable it
                  deliberately, and not on a metered or slow connection.

                  If you want to know what an update would cost without paying for it,
                  see dryRunPreview - it asks nix for a build plan instead of executing
                  one, on demand rather than on a timer.
                '';
              };
              
              afterRebuild = mkOption {
                type = types.enum [ "recheck" "reconcile" "assume-updated" ];
                default = "recheck";
                description = ''
                  What to do when a rebuild that changed package versions is detected.

                  "recheck" discards the previous result and runs a real check, so the
                  count reflects what is actually still outstanding. A rebuild that
                  applied only some of the pending updates - updating a single flake
                  input rather than all of them - is reported correctly. Costs one
                  check per rebuild, which in "full" mode means building the new
                  closure.

                  "reconcile" subtracts the packages the rebuild demonstrably changed
                  and keeps the rest. The rebuild is already detected by diffing the
                  old and new closures with nvd, so the list of what changed is
                  available at no extra cost, and the pending entries matching it are
                  dropped. Usually right and effectively free. What it cannot see is
                  the channel moving forward since the last check, so it can undercount
                  - it never reports an update as resolved that was not, and the next
                  scheduled check replaces the estimate with a measurement. Falls back
                  to "recheck" when there is nothing to reconcile against, such as a
                  previous closure that has been garbage collected.

                  "assume-updated" treats the rebuild as having applied everything and
                  reports zero without checking, deferring the next real check to the
                  normal updateInterval. Cheapest, and right when you always update
                  every input before rebuilding; wrong until the next scheduled check
                  if you did not, since updates from inputs you left alone stay
                  outstanding but are reported as zero.

                  All three keep the flake-input, pinned-input and source-check
                  sections of the tooltip.
                '';
              };

              notifications = mkOption {
                type = types.bool;
                default = true;
                description = "Whether to show desktop notifications for update checks.";
              };
              
              updateInterval = mkOption {
                type = types.int;
                default = 3600;
                description = "Time in seconds between update checks";
              };
              
              nixosConfigPath = mkOption {
                type = types.str;
                default = "~/.config/nixos";
                description = "Path to your NixOS configuration flake directory (used by both modes)";
              };
              
              nixpkgsChannel = mkOption {
                type = types.either types.str (types.submodule {
                  options = {
                    stable = mkOption {
                      type = types.str;
                      default = "pkgs";
                      description = "Identifier used for stable packages (e.g., 'pkgs' matches 'with pkgs;' and 'pkgs.foo')";
                    };
                    unstable = mkOption {
                      type = types.str;
                      default = "pkgs-unstable";
                      description = "Identifier used for unstable packages (e.g., 'pkgs-unstable' matches 'with pkgs-unstable;')";
                    };
                  };
                });
                default = "github:NixOS/nixpkgs/nixpkgs-unstable";
                description = ''
                  Nixpkgs channel configuration for lightweight mode.
                  
                  Simple (single channel): Set to a flake ref string like "github:NixOS/nixpkgs/nixpkgs-unstable"
                  
                  Dual channel: Set to an attrset with:
                    - stable: Identifier for stable packages (default: "pkgs")
                    - unstable: Identifier for unstable packages (default: "pkgs-unstable")
                  
                  In dual channel mode, nixosConfigPath is used to scan .nix files for package sources,
                  and flake refs are auto-detected from flake.lock.
                '';
              };
              
              skipAfterBoot = mkOption {
                type = types.bool;
                default = true;
                description = "Whether to skip update checks right after boot/resume";
              };
              
              gracePeriod = mkOption {
                type = types.int;
                default = 60;
                description = "Time in seconds to wait after boot/resume before checking";
              };

              clockFormat = mkOption {
                type = types.enum [ "24h" "12h" ];
                default = "24h";
                description = ''
                  Clock format for tooltip timestamps.
                  - "24h": 14:23
                  - "12h": 2:23 PM

                  A time that is not from today carries its day in front:
                  "Last checked: Sat 23:47" for the hour after midnight, and
                  "10-23 09:12" once the gap passes a week and a weekday name
                  stops saying which week it means. Times from today are bare,
                  which is almost all of them.
                '';
              };
              
              updateLockFile = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to update the lock file directly or use a temporary copy (full mode only)";
              };
              
              explicitPackagesOnly = mkOption {
                type = types.nullOr types.bool;
                default = null;
                description = ''
                  Only report updates for packages explicitly defined in your config files (lightweight mode only).
                  This filters out system dependencies and provides more accurate results.
                  
                  Defaults to true when nixpkgsChannel is set to dual-channel mode (attrset),
                  false otherwise. Set explicitly to override the default.
                '';
              };

              dryRunPreview = {
                enable = mkEnableOption ''
                  an on-demand update-cost preview, bound to middle-click.

                  Resolves a temporary lock file and runs a Nix dry-run to report how
                  many derivations would be built and how much would be downloaded if
                  you updated your flake inputs and rebuilt. Your flake.lock and
                  configuration are never modified, and the update count is unchanged.

                  Off by default, and never runs on a timer: a preview is a full system
                  evaluation costing a few minutes and well over a gigabyte of memory.
                  Setting this back to false also clears any result already computed.

                  A result is retired when your flake.lock changes, a check finds
                  something different, or the packages your configuration declares
                  change. A rebuild on its own only marks it - the stamp reads
                  "pre-rebuild" and the numbers stay - because a rebuild that changed
                  only settings moves the plan by far less than a recompute costs.
                '';
                recalculateOnChange = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Recompute the cost by itself once it no longer describes anything,
                    instead of showing "middle-click to recalculate" and waiting.

                    Triggers when your flake.lock changes, when a check finds something
                    different from what the cost was priced against, or when the
                    packages your configuration declares change. Not on a rebuild
                    alone: what happens after one is already afterRebuild's business,
                    and each option leads to a check whose result triggers this anyway.

                    Only ever refreshes a cost you already have. The first one is always
                    a middle-click, so enabling this cannot commit a machine to an
                    evaluation it has never asked for - but do read what dryRunPreview
                    costs before turning it on, because that is the price per recompute.

                    Has no effect unless dryRunPreview.enable is true.
                  '';
                };
                target = mkOption {
                  type = types.str;
                  default = ".#nixosConfigurations.\${hostname}.config.system.build.toplevel";
                  description = "Flake target to price; literal \${hostname} is replaced at run time.";
                };
              };

              sourceChecks = mkOption {
                type = types.listOf sourceCheckType;
                default = [ ];
                description = ''
                  Explicit upstream policies for sources the ordinary package and flake-input
                  checks cannot interpret on their own: fixed revisions in package expressions,
                  local checkouts, named release lines, and forks.

                  Each check needs a current source and an upstream policy, so intent is stated
                  rather than guessed. Checks run git ls-remote against the upstream repository,
                  bounded by SOURCE_CHECK_TIMEOUT (default 60s) per call, and are skipped
                  entirely when there is no network.

                  The policy has to match the shape of the current value: "branch" resolves
                  upstream to a commit and "tag" to a tag name, so pairing a revision with a
                  tag policy (or a tag with a branch policy) compares two things that can
                  never be equal and reports an update on every run. Both are reported rather
                  than compared. flake-input is exempt, taking its current value from the
                  policy and so consistent by construction.

                  A tag policy goes further and checks that the current value is a tag the
                  upstream actually has, which catches what the shape rule cannot: a branch
                  name from a flake input's ref, an abbreviated revision, a typo, or a tag
                  renamed away. The tag list is already fetched to find the latest, so this
                  costs no additional ls-remote.

                  current = "package" derives both the pin and the repository from a package
                  attribute's src instead of restating them here, leaving only the upstream
                  policy to configure. It costs one nix eval per package check - measured
                  around 4s warm - bounded by PACKAGE_EVAL_TIMEOUT (default 120s), and
                  reads sources fetched with
                  fetchFromGitHub, fetchFromGitLab, fetchFromGitea or fetchgit. A release
                  tarball or a vendored source carries no revision and is reported as such.
                '';
              };

              customChecks = mkOption {
                type = types.listOf customCheckType;
                default = [ ];
                description = ''
                  Arbitrary commands run on the same cycle as the update check, with their
                  stdout folded into the tooltip under a "Checks" section.

                  The escape hatch for things that are worth knowing on a schedule but are
                  not package or flake-input updates, and so cannot be derived from the
                  flake: a retired API model id, an expiring certificate, a drifted remote.

                  The contract is plain text, not JSON. A line of output is a thing worth
                  reporting; no output is a clean result and prints nothing. With
                  mode = "count" each line also adds one to the waybar count, which is what
                  makes a check visible without opening the tooltip -- mode = "show" only
                  ever reaches someone already hovering.

                  Failures are reported rather than swallowed: a command that is missing,
                  crashes, or exceeds CUSTOM_CHECK_TIMEOUT (default 60s) shows up as
                  "name (exit N)" or "name (timed out)". Silence already means "all clear",
                  so a broken check must not be able to imitate it.
                '';
                example = literalExpression ''
                  [
                    {
                      name = "Anthropic models";
                      mode = "count";
                      command = "''${pkgs.anthropic-model-check}/bin/anthropic-model-check";
                    }
                  ]
                '';
              };

              lightweightExcludePatterns = mkOption {
                type = types.listOf types.str;
                default = [ "*-fish-completions" ];
                example = [ "*-fish-completions" "*-zsh-completions" ];
                description = ''
                  Shell patterns matched against store output names and skipped before
                  version parsing (lightweight mode only).

                  Generated outputs such as "atuin-18.7.1-fish-completions" otherwise have
                  their suffix parsed as part of the version, producing a phantom update in
                  both the count and the tooltip. Patterns are matched against the whole
                  name, so keep them anchored - "*-completions" would also drop genuine
                  packages like nix-bash-completions.

                  This is distinct from explicitPackagesOnly, which filters package names
                  rather than output suffixes.
                '';
              };

              inputChecker = {
                mode = mkOption {
                  type = types.enum [ "disabled" "show" "count" ];
                  default = "disabled";
                  description = ''
                    How to handle stale flake inputs (checked via git ls-remote).
                    - "disabled": Don't check inputs (no resources used)
                    - "show": Check and show in tooltip, but don't include in count
                    - "count": Check, show in tooltip, and include in waybar count

                    Two kinds of line are shown without being counted even under "count",
                    because a count is for updates there are to apply and neither of these
                    is one: an input whose upstream could not be reached, where whether
                    there is an update is exactly what failed to be established, and an
                    input whose locked revision is ahead of the ref it tracks, which has
                    nothing to move to.
                  '';
                };
                pinned = mkOption {
                  type = types.enum [ "disabled" "show" "count" ];
                  default = "disabled";
                  description = ''
                    How to handle pinned flake inputs (inputs with original.rev set).
                    - "disabled": Don't check pinned inputs (no resources used)
                    - "show": Check and show in separate "Pinned:" section, but don't count
                    - "count": Check, show, and include in waybar count
                  '';
                };
              };

              upstreamInfo = {
                mode = mkOption {
                  type = types.enum [ "api" "disabled" ];
                  default = "api";
                  description = ''
                    Whether input and source lines may resolve the upstream commit's date
                    and the number of commits behind, turning
                    "nixpkgs: 1a62cd4 → b03ef19" into
                    "nixpkgs: 2026-10-14 → 2026-10-20 (412 commits)".

                    "api" asks the host's API; "disabled" leaves every line on the
                    revision-pair form and makes no network calls beyond the git ls-remote
                    the check already performs.

                    GitHub answers with the upstream date and both distances in a single
                    request per stale input. Bitbucket needs a different shape: its commit
                    listing returns no total, so a count is reached by walking it, and the
                    absence of a "next" link is what proves the running total exact rather
                    than a sample -- a range of 100 or fewer costs one request per
                    direction, and the walk stops at UPSTREAM_INFO_PAGE_MAX pages
                    (default 5) and reports a floor, "(500+ commits)", instead of following
                    pages indefinitely. Both directions are walked, because the reverse
                    range is the only thing that tells behind apart from diverged: a newer
                    tip upstream says when upstream last moved, not that the current side
                    carries nothing of its own. Any other host gets a date from
                    allowShallowFetch and no count.

                    The glyph between the two sides states how they have moved relative to
                    each other: "->" behind, "<-" ahead of upstream with nothing to pull,
                    "<->" diverged, and an em dash where no resolver established which way.
                    The operands keep their positions throughout -- current on the left,
                    upstream on the right -- so only the glyph changes. A "<-" line is shown
                    but not counted, since there is nothing there to apply.

                    An arrow takes a counted distance in both directions, so the hosts
                    without a compare endpoint get the em dash rather than a "->" asserting
                    a fast-forward nothing checked. Those lines are still counted: the glyph
                    reports what was established, while the waybar number has to choose, and
                    choosing "nothing to do" would hide real updates behind a resolver that
                    fell short.

                    Results are cached on the revision pair, so a line costs a request only
                    when one of its two sides actually moves, and a second checker reading
                    the same pair costs nothing.

                    Both hosts give an unauthenticated caller 60 requests per hour against
                    the whole outbound IP -- not per process, and shared with anything else
                    making API calls from the same address. The two budgets are tracked
                    separately, so a spent hour on one does not stop the other resolving. A
                    configuration with a handful of inputs on the default interval sits well
                    inside them; a large one, or a shared address, may not. Set
                    githubTokenFile to lift GitHub's to 5000/hour. Exhausting a budget is
                    not an error: its reset time is recorded, calls are declined until it
                    passes, and lines fall back to revision pairs in the meantime.
                  '';
                };

                githubTokenFile = mkOption {
                  type = types.nullOr types.path;
                  default = null;
                  example = "/run/secrets/github-token";
                  description = ''
                    Path to a file holding a GitHub token, read at check time to raise the
                    API budget from 60 to 5000 requests per hour.

                    A path rather than the token itself, so the secret stays out of the Nix
                    store and out of the process table. Only public repository metadata is
                    read, so a token with no scopes selected is sufficient and is what to
                    use -- nothing here needs the access a broader one would grant.

                    Ignored when upstreamInfo.mode is "disabled".
                  '';
                };

                allowShallowFetch = mkOption {
                  type = types.bool;
                  default = true;
                  description = ''
                    Whether a non-GitHub remote may be asked for the upstream commit date
                    with a shallow fetch, since it has no compare endpoint to ask instead.
                    No commit distance comes out of this -- counting commits needs the
                    history between the two revisions, and deepening a fetch until it is
                    present has no bound that a tooltip refresh can live with. So a line
                    from such a host reads "name: 2026-10-10 -> 2026-10-18", with dates
                    on both sides and no commit count.

                    The cheap form of that fetch -- depth 1 with trees filtered out --
                    needs the server to advertise uploadpack.allowFilter, and one that
                    does not serves the entire tree at that commit instead. A server
                    cannot be asked in advance which it will do, and a fetch cannot be
                    capped by size, so what arrived is measured afterwards: past
                    UPSTREAM_INFO_FETCH_MAX_KIB (default 2048) the filter is taken to
                    have been ignored and that host is recorded and not fetched from
                    again for 30 days. The overrun therefore costs one fetch rather than
                    one per hour, which is what makes leaving this on reasonable.

                    Turn it off to keep non-GitHub lines on the revision-pair form and
                    make no fetches at all.

                    GitHub inputs are unaffected either way.
                  '';
                };
              };
              
              waybarConfig = mkOption {
                type = types.attrs;
                default = {
                  exec = "~/.config/waybar/scripts/update-checker";
                  exec-on-event = false;
                  signal = 12;
                  on-click = "~/.config/waybar/scripts/update-checker toggle";
                  on-click-right = "~/.config/waybar/scripts/update-checker refresh";
                  # How often waybar asks the script what to display, which is
                  # deliberately not how often a check runs - updateInterval is,
                  # and the script throttles itself against it.
                  #
                  # These were the same value, and that is a phase trap rather
                  # than a tidy default: a check started by the poll at T only
                  # stamps its timestamp at T+duration, so the poll at T+interval
                  # sees interval-duration elapsed, decides it is early, and skips.
                  # Every second poll was lost and the effective period was twice
                  # what was configured. Measured here at 123s for a lightweight
                  # check, and a full check realises the closure, so its duration
                  # is the whole update - there is no duration small enough for
                  # the two periods to coexist safely.
                  #
                  # Polling well inside the interval removes the coincidence:
                  # some poll always lands after the check becomes due, so a
                  # check is late by at most this value and never early. Capped
                  # so a long interval does not mean a rare poll, and scaled for
                  # short ones so lateness stays under a tenth of the period.
                  interval = lib.max 60 (lib.min 500 (cfg.updateInterval / 10));
                } // optionalAttrs cfg.dryRunPreview.enable {
                  # Only bound when the preview is enabled, so it cannot be
                  # triggered by accident on a default configuration.
                  on-click-middle = "~/.config/waybar/scripts/update-checker preview";
                } // {
                  tooltip = true;
                  return-type = "json";
                  format = "{icon} {text}";
                  format-icons = {
                    has-updates = "󰚰";
                    updating = "";
                    updated = "";
                    error = "";
                    disabled = "󰔞";
                  };
                };
                description = "Waybar module configuration for nix-updates";
              };
            };
            
            config = mkIf cfg.enable {
              home.packages =
                if isLightweight
                then [ self.packages.${pkgs.stdenv.hostPlatform.system}.lightweight ]
                else [ cfg.package ];
              
              # Install icons to user's home directory
              home.file.".icons" = {
                source = if isLightweight
                  then "${self.packages.${pkgs.stdenv.hostPlatform.system}.lightweight}/share/icons/waybar-nixos-updates"
                  else "${cfg.package}/share/icons/waybar-nixos-updates";
                recursive = true;
              };
              
              # Create a wrapper script with user's configuration
              home.file.".config/waybar/scripts/update-checker" = {
                executable = true;
                text = let
                  # Helper to expand ~ to $HOME in paths
                  expandTilde = path: builtins.replaceStrings ["~"] ["\${HOME}"] path;
                in if isLightweight then ''
                  #!/usr/bin/env bash
                  export UPDATE_INTERVAL="${toString cfg.updateInterval}"
                  export FLAKE_DIR="${expandTilde cfg.nixosConfigPath}"
                  export SKIP_AFTER_BOOT="${if cfg.skipAfterBoot then "true" else "false"}"
                  export GRACE_PERIOD="${toString cfg.gracePeriod}"
                  export NOTIFICATIONS_ENABLED="${if cfg.notifications then "true" else "false"}"
                  export CLOCK_FORMAT="${cfg.clockFormat}"
                  export AFTER_REBUILD="${cfg.afterRebuild}"
                  export INPUT_CHECKER_MODE="${cfg.inputChecker.mode}"
                  export INPUT_CHECKER_PINNED="${cfg.inputChecker.pinned}"
                  export UPSTREAM_INFO_MODE="${cfg.upstreamInfo.mode}"
                  export UPSTREAM_INFO_FETCH="${if cfg.upstreamInfo.allowShallowFetch then "enabled" else "disabled"}"
                  ${lib.optionalString (cfg.upstreamInfo.githubTokenFile != null) ''
                  # Read at check time rather than interpolated: the point of a
                  # token *file* is that the secret never enters the store.
                  # Exported only when non-empty, so an unreadable or empty file
                  # leaves upstream-info unauthenticated instead of sending an
                  # "Authorization: Bearer" header with nothing after it, which
                  # GitHub answers with 401 rather than the 60/hour it would
                  # otherwise have allowed.
                  GITHUB_TOKEN="$(cat ${escapeShellArg (toString cfg.upstreamInfo.githubTokenFile)} 2>/dev/null || true)"
                  [ -n "$GITHUB_TOKEN" ] && export GITHUB_TOKEN || unset GITHUB_TOKEN
                  ''}
                  export LIGHTWEIGHT_EXCLUDE_PATTERNS_JSON=${escapeShellArg (builtins.toJSON cfg.lightweightExcludePatterns)}
                  export SOURCE_CHECKS_JSON=${escapeShellArg (builtins.toJSON cfg.sourceChecks)}
                  export CUSTOM_CHECKS_JSON=${escapeShellArg (builtins.toJSON cfg.customChecks)}
                  export DRY_RUN_PREVIEW="${if cfg.dryRunPreview.enable then "true" else "false"}"
                  export PREVIEW_TARGET="${builtins.replaceStrings ["\${hostname}"] ["$(hostname)"] cfg.dryRunPreview.target}"
                  export PREVIEW_AUTO="${if cfg.dryRunPreview.recalculateOnChange then "true" else "false"}"
                  ${if builtins.isString cfg.nixpkgsChannel then ''
                  export NIXPKGS_CHANNEL="${cfg.nixpkgsChannel}"
                  ${if cfg.explicitPackagesOnly != null then ''
                  export EXPLICIT_PACKAGES_ONLY="${if cfg.explicitPackagesOnly then "true" else "false"}"
                  '' else ""}
                  '' else ''
                  export DUAL_CHANNEL_MODE="true"
                  export STABLE_IDENTIFIER="${cfg.nixpkgsChannel.stable}"
                  export UNSTABLE_IDENTIFIER="${cfg.nixpkgsChannel.unstable}"
                  ${if cfg.explicitPackagesOnly != null then ''
                  export EXPLICIT_PACKAGES_ONLY="${if cfg.explicitPackagesOnly then "true" else "false"}"
                  '' else ""}
                  ''}
                  exec ${checkerBin} "$@"
                '' else ''
                  #!/usr/bin/env bash
                  export UPDATE_INTERVAL="${toString cfg.updateInterval}"
                  export NIXOS_CONFIG_PATH="${expandTilde cfg.nixosConfigPath}"
                  export SKIP_AFTER_BOOT="${if cfg.skipAfterBoot then "true" else "false"}"
                  export GRACE_PERIOD="${toString cfg.gracePeriod}"
                  export UPDATE_LOCK_FILE="${if cfg.updateLockFile then "true" else "false"}"
                  export NOTIFICATIONS_ENABLED="${if cfg.notifications then "true" else "false"}"
                  export CLOCK_FORMAT="${cfg.clockFormat}"
                  export AFTER_REBUILD="${cfg.afterRebuild}"
                  export INPUT_CHECKER_MODE="${cfg.inputChecker.mode}"
                  export INPUT_CHECKER_PINNED="${cfg.inputChecker.pinned}"
                  export UPSTREAM_INFO_MODE="${cfg.upstreamInfo.mode}"
                  export UPSTREAM_INFO_FETCH="${if cfg.upstreamInfo.allowShallowFetch then "enabled" else "disabled"}"
                  ${lib.optionalString (cfg.upstreamInfo.githubTokenFile != null) ''
                  # Read at check time rather than interpolated: the point of a
                  # token *file* is that the secret never enters the store.
                  # Exported only when non-empty, so an unreadable or empty file
                  # leaves upstream-info unauthenticated instead of sending an
                  # "Authorization: Bearer" header with nothing after it, which
                  # GitHub answers with 401 rather than the 60/hour it would
                  # otherwise have allowed.
                  GITHUB_TOKEN="$(cat ${escapeShellArg (toString cfg.upstreamInfo.githubTokenFile)} 2>/dev/null || true)"
                  [ -n "$GITHUB_TOKEN" ] && export GITHUB_TOKEN || unset GITHUB_TOKEN
                  ''}
                  export SOURCE_CHECKS_JSON=${escapeShellArg (builtins.toJSON cfg.sourceChecks)}
                  export CUSTOM_CHECKS_JSON=${escapeShellArg (builtins.toJSON cfg.customChecks)}
                  export DRY_RUN_PREVIEW="${if cfg.dryRunPreview.enable then "true" else "false"}"
                  export PREVIEW_TARGET="${builtins.replaceStrings ["\${hostname}"] ["$(hostname)"] cfg.dryRunPreview.target}"
                  export PREVIEW_AUTO="${if cfg.dryRunPreview.recalculateOnChange then "true" else "false"}"
                  exec ${checkerBin} "$@"
                '';
              };
              
              # Note: Users will need to manually add cfg.waybarConfig to their waybar configuration
              # This could be documented in the README
            };
          };
        
        # NixOS module (alternative to home-manager)
        nixosModules.default = { config, lib, pkgs, ... }:
          with lib;
          let
            cfg = config.services.waybar-nixos-updates;
          in {
            options.services.waybar-nixos-updates = {
              enable = mkEnableOption "waybar-nixos-updates";
              
              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.stdenv.hostPlatform.system}.waybar-nixos-updates;
                defaultText = literalExpression "waybar-nixos-updates";
                description = "The waybar-nixos-updates package to use.";
              };
            };
            
            config = mkIf cfg.enable {
              environment.systemPackages = [ cfg.package ];
            };
          };
      };
}
