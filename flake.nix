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
          version = "1.0.0";
          
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
            
            # Install icons
            mkdir -p $out/share/icons/waybar-nixos-updates
            if [ -d .icons ]; then
              cp -r .icons/* $out/share/icons/waybar-nixos-updates/
            fi
            
            # Wrap the script with required dependencies
            wrapProgram $out/bin/update-checker \
              --prefix PATH : ${pkgs.lib.makeBinPath [
                pkgs.coreutils
                pkgs.libnotify
                pkgs.nvd
                pkgs.nixVersions.stable
                pkgs.gnugrep
                pkgs.gawk
                pkgs.gnused
                pkgs.procps
                pkgs.systemd
                pkgs.iproute2
                pkgs.inetutils
              ]}
            
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
          version = "1.0.0";
          
          src = ./.;
          
          nativeBuildInputs = with pkgs; [
            makeWrapper
          ];
          
          installPhase = ''
            runHook preInstall
            
            mkdir -p $out/bin
            cp lightweight-checker $out/bin/lightweight-checker
            chmod +x $out/bin/lightweight-checker
            
            wrapProgram $out/bin/lightweight-checker \
              --prefix PATH : ${pkgs.lib.makeBinPath [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gawk
                pkgs.gnused
                pkgs.procps
                pkgs.systemd
                pkgs.iproute2
                pkgs.jq
                pkgs.nixVersions.stable
                pkgs.nix-output-monitor
              ]}
            
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
      in
      {
        packages = {
          default = waybar-nixos-updates;
          waybar-nixos-updates = waybar-nixos-updates;
          lightweight = waybar-nixos-updates-lightweight;
        };
        
        apps.default = flake-utils.lib.mkApp {
          drv = waybar-nixos-updates;
          name = "update-checker";
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
              then "${self.packages.${pkgs.system}.lightweight}/bin/lightweight-checker"
              else "${cfg.package}/bin/update-checker";
          in {
            options.programs.waybar-nixos-updates = {
              enable = mkEnableOption "waybar-nixos-updates";
              
              package = mkOption {
                type = types.package;
                default = self.packages.${pkgs.system}.waybar-nixos-updates;
                defaultText = literalExpression "waybar-nixos-updates";
                description = "The waybar-nixos-updates package to use.";
              };
              
              checkMode = mkOption {
                type = types.enum [ "full" "lightweight" ];
                default = "full";
                description = ''
                  Update check strategy.
                  "full" builds the new system closure and diffs with nvd (accurate, slow).
                  "lightweight" uses lazy nix eval of .version attributes (fast, approximate).
                '';
              };
              
              updateInterval = mkOption {
                type = types.int;
                default = 3600;
                description = "Time in seconds between update checks";
              };
              
              nixosConfigPath = mkOption {
                type = types.str;
                default = "~/.config/nixos";
                description = "Path to your NixOS configuration (full mode only)";
              };
              
              nixpkgsChannel = mkOption {
                type = types.str;
                default = "github:NixOS/nixpkgs/nixpkgs-unstable";
                description = "Nixpkgs flake ref to check against (lightweight mode only)";
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
              
              updateLockFile = mkOption {
                type = types.bool;
                default = false;
                description = "Whether to update the lock file directly or use a temporary copy (full mode only)";
              };
              
              waybarConfig = mkOption {
                type = types.attrs;
                default = {
                  exec = checkerBin;
                  signal = 12;
                  on-click = "";
                  on-click-right = "rm ~/.cache/nix-update-last-run";
                  interval = cfg.updateInterval;
                  tooltip = true;
                  return-type = "json";
                  format = "{} {icon}";
                  format-icons = {
                    has-updates = "󰚰";
                    updating = "";
                    updated = "";
                    error = "";
                  };
                };
                description = "Waybar module configuration for nix-updates";
              };
            };
            
            config = mkIf cfg.enable {
              home.packages =
                if isLightweight
                then [ self.packages.${pkgs.system}.lightweight ]
                else [ cfg.package ];
              
              # Install icons to user's home directory (full mode only)
              home.file.".icons" = mkIf (!isLightweight) {
                source = "${cfg.package}/share/icons/waybar-nixos-updates";
                recursive = true;
              };
              
              # Create a wrapper script with user's configuration
              home.file.".config/waybar/scripts/update-checker" = {
                executable = true;
                text = if isLightweight then ''
                  #!/usr/bin/env bash
                  export UPDATE_INTERVAL="${toString cfg.updateInterval}"
                  export NIXPKGS_CHANNEL="${cfg.nixpkgsChannel}"
                  export SKIP_AFTER_BOOT="${if cfg.skipAfterBoot then "true" else "false"}"
                  export GRACE_PERIOD="${toString cfg.gracePeriod}"
                  exec ${checkerBin} "$@"
                '' else ''
                  #!/usr/bin/env bash
                  export UPDATE_INTERVAL="${toString cfg.updateInterval}"
                  export NIXOS_CONFIG_PATH="${cfg.nixosConfigPath}"
                  export SKIP_AFTER_BOOT="${if cfg.skipAfterBoot then "true" else "false"}"
                  export GRACE_PERIOD="${toString cfg.gracePeriod}"
                  export UPDATE_LOCK_FILE="${if cfg.updateLockFile then "true" else "false"}"
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
                default = self.packages.${pkgs.system}.waybar-nixos-updates;
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