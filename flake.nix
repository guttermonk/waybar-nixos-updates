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
          version = "4.2";
          
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
          version = "4.2";
          
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
          version = "4.2";
          src = ./.;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp input-checker $out/bin/input-checker
            chmod +x $out/bin/input-checker
            wrapProgram $out/bin/input-checker \
              --prefix PATH : ${pkgs.lib.makeBinPath [
                pkgs.coreutils
                pkgs.git
                pkgs.jq
              ]}
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
                  type = types.enum [ "flake-input" "revision" "tag" "local" ];
                  description = "Where the currently configured version comes from.";
                };
                input = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Flake input name, when current = \"flake-input\".";
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
                  type = types.str;
                  description = "Canonical upstream Git repository URL to compare against.";
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
                '';
                recalculateOnChange = mkOption {
                  type = types.bool;
                  default = false;
                  description = ''
                    Recompute the cost by itself once it no longer describes anything,
                    instead of showing "middle-click to recalculate" and waiting.

                    Triggers when your flake.lock changes, or when a check finds
                    something different from what the cost was priced against. Not on a
                    rebuild: what happens after one is already afterRebuild's business,
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
                  export LIGHTWEIGHT_EXCLUDE_PATTERNS_JSON=${escapeShellArg (builtins.toJSON cfg.lightweightExcludePatterns)}
                  export SOURCE_CHECKS_JSON=${escapeShellArg (builtins.toJSON cfg.sourceChecks)}
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
                  export SOURCE_CHECKS_JSON=${escapeShellArg (builtins.toJSON cfg.sourceChecks)}
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
