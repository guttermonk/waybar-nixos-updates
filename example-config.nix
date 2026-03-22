# Example configuration for waybar-nixos-updates
# This file demonstrates how to integrate waybar-nixos-updates into your NixOS configuration

{ config, ... }:

{
  # Example 1: Basic Home Manager configuration (full mode - default)
  # Add this to your home-manager configuration
  programs.waybar-nixos-updates = {
    enable = true;
    
    # Optional: Override default settings
    updateInterval = 3600;              # Check every hour (in seconds)
    nixosConfigPath = "~/.config/nixos"; # Path to your NixOS flake (used by both modes)
    skipAfterBoot = true;                # Don't check immediately after boot
    gracePeriod = 60;                    # Wait 60 seconds after boot before checking
    updateLockFile = false;              # Use temporary directory for safety (full mode only)
  };

  # Example 1b: Lightweight mode - single channel (fast, simple)
  # programs.waybar-nixos-updates = {
  #   enable = true;
  #   mode = "lightweight";
  #   nixosConfigPath = "~/.config/nixos";  # Used for flake.lock and .nix file scanning
  #   nixpkgsChannel = "github:NixOS/nixpkgs/nixos-unstable";
  #   
  #   # Optional: Also filter to only explicitly defined packages
  #   explicitPackagesOnly = true;
  # };

  # Example 1c: Lightweight mode - dual channel (stable + unstable)
  # Best for configs that use both pkgs and pkgs-unstable
  # programs.waybar-nixos-updates = {
  #   enable = true;
  #   mode = "lightweight";
  #   nixosConfigPath = "~/.config/nixos";  # Scans .nix files here for package sources
  #   nixpkgsChannel = {
  #     # These identifiers match what you use in your nix files:
  #     # e.g., "pkgs.bat" or "with pkgs-unstable; [ brave ]"
  #     stable = "pkgs";
  #     unstable = "pkgs-unstable";
  #   };
  #   # Channels are auto-detected from flake.lock (nixpkgs and nixpkgs-unstable inputs)
  #   # explicitPackagesOnly defaults to true in dual-channel mode
  # };

  # Example 1d: With flake input staleness checking
  # Combines package updates with stale input detection in one tooltip
  # programs.waybar-nixos-updates = {
  #   enable = true;
  #   checkMode = "lightweight";  # Works with both "full" and "lightweight"
  #   nixosConfigPath = "~/.config/nixos";
  #   nixpkgsChannel = {
  #     stable = "pkgs";
  #     unstable = "pkgs-unstable";
  #   };
  #   inputChecker = {
  #     mode = "count";    # "disabled" | "show" | "count"
  #     pinned = "show";   # "disabled" | "show" | "count"
  #   };
  #   # Tooltip will show:
  #   #   Packages:
  #   #   brave: 1.87.192 → 1.88.132
  #   #   dprint: 0.51.1 → 0.52.1
  #   #
  #   #   Inputs:
  #   #   home-manager (locked: 2026-02-14)
  #   #   hyprland (locked: 2026-02-15)
  #   #
  #   #   Pinned:
  #   #   some-fork (pinned: 2025-08-03)
  # };

  # Example 2: Complete Waybar configuration with the update module
  programs.waybar = {
    enable = true;
    
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 30;
        
        modules-left = [ "sway/workspaces" "sway/mode" ];
        modules-center = [ "clock" ];
        modules-right = [ 
          "custom/nix-updates"  # Add the update module here
          "network" 
          "battery" 
          "tray" 
        ];
        
        # Use the pre-configured waybar module from waybar-nixos-updates
        "custom/nix-updates" = config.programs.waybar-nixos-updates.waybarConfig;
        
        # Or override specific options if needed
        # "custom/nix-updates" = config.programs.waybar-nixos-updates.waybarConfig // {
        #   interval = 1800;  # Override just the interval
        # };
      };
    };
    
    # Example 3: Custom styling for the update module
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
      }
      
      window#waybar {
        background-color: rgba(30, 30, 46, 0.9);
        color: #cdd6f4;
      }
      
      /* Style for the update module */
      #custom-nix-updates {
        color: #89b4fa;
        padding: 0 10px;
        margin: 0 5px;
      }
      
      #custom-nix-updates.has-updates {
        color: #f38ba8;
        font-weight: bold;
        animation: blink 2s linear infinite;
      }
      
      #custom-nix-updates.updating {
        color: #f9e2af;
        animation: spin 2s linear infinite;
      }
      
      #custom-nix-updates.updated {
        color: #a6e3a1;
      }
      
      #custom-nix-updates.error {
        color: #eba0ac;
        font-weight: bold;
      }
      
      @keyframes blink {
        0% { opacity: 1; }
        50% { opacity: 0.5; }
        100% { opacity: 1; }
      }
      
      @keyframes spin {
        from { transform: rotate(0deg); }
        to { transform: rotate(360deg); }
      }
    '';
  };

  # Example 4: System integration with custom update scripts
  # These are shell aliases that integrate with the update checker
  
  programs.bash.shellAliases = {
    # Update flake and check for updates
    checkup = ''
      pushd ~/.config/nixos && \
      nix flake update && \
      nix build .#nixosConfigurations.$(hostname).config.system.build.toplevel && \
      nvd diff /run/current-system ./result | tee >(if grep -qe '\\[U'; then \
        touch "$HOME/.cache/nix-update-update-flag"; \
      else \
        rm -f "$HOME/.cache/nix-update-update-flag"; \
      fi) && \
      popd
    '';
    
    # Rebuild system and notify waybar
    nixup = ''
      pushd ~/.config/nixos && \
      echo "NixOS rebuilding..." && \
      sudo nixos-rebuild switch --flake .#$(hostname) && \
      if [ -f "$HOME/.cache/nix-update-update-flag" ]; then \
        touch "$HOME/.cache/nix-update-rebuild-flag" && \
        pkill -x -RTMIN+12 .waybar-wrapped; \
      fi && \
      popd
    '';
    
    # Force update check
    check-updates = "rm ~/.cache/nix-update-last-run && pkill -RTMIN+12 waybar";
    
    # Clear all update cache
    clear-update-cache = "rm -f ~/.cache/nix-update-*";
  };

  # Example 5: Alternative manual configuration (without using the module)
  # If you prefer to configure everything manually:
  
  # programs.waybar.settings.mainBar."custom/nix-updates-manual" = {
  #   exec = "${pkgs.waybar-nixos-updates}/bin/update-checker";
  #   signal = 12;
  #   on-click = "";
  #   on-click-right = "rm ~/.cache/nix-update-last-run";
  #   interval = 3600;
  #   tooltip = true;
  #   return-type = "json";
  #   format = "{} {icon}";
  #   format-icons = {
  #     has-updates = "󰚰";
  #     updating = "󰇚";
  #     updated = "󰄴";
  #     error = "󰅚";
  #   };
  # };

  # Example 6: Using environment variables to configure the script
  # If you want to override settings without using the module:
  
  # systemd.user.services.waybar.environment = {
  #   UPDATE_INTERVAL = "7200";  # 2 hours
  #   NIXOS_CONFIG_PATH = "/home/user/my-nixos-config";
  #   UPDATE_LOCK_FILE = "true";
  # };
}

# Flake configuration example
# Add this to your flake.nix:
#
# {
#   inputs = {
#     nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
#     home-manager = {
#       url = "github:nix-community/home-manager";
#       inputs.nixpkgs.follows = "nixpkgs";
#     };
#     waybar-nixos-updates = {
#       url = "github:yourusername/waybar-nixos-updates";
#       inputs.nixpkgs.follows = "nixpkgs";
#     };
#   };
#
#   outputs = { self, nixpkgs, home-manager, waybar-nixos-updates, ... }: {
#     nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
#       system = "x86_64-linux";
#       modules = [
#         ./configuration.nix
#         home-manager.nixosModules.home-manager
#         {
#           home-manager.useGlobalPkgs = true;
#           home-manager.useUserPackages = true;
#           home-manager.users.youruser = { imports = [
#             waybar-nixos-updates.homeManagerModules.default
#             ./home.nix  # Your home configuration
#           ]; };
#         }
#       ];
#     };
#   };
# }
