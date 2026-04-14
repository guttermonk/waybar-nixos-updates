{ pkgs, ... }:
let

  update_checker = pkgs.writeShellScriptBin "update_checker" ''

    # ===== Configuration =====
    UPDATE_INTERVAL=3599  # Check interval in seconds (1 hour)
    NIXOS_CONFIG_PATH="$HOME/.config/nixos"  # Path to NixOS configuration
    CACHE_DIR="$HOME/.cache"
    STATE_FILE="$CACHE_DIR/nix-update-state"
    LAST_RUN_FILE="$CACHE_DIR/nix-update-last-run"
    LAST_RUN_TOOLTIP="$CACHE_DIR/nix-update-tooltip"
    BOOT_MARKER_FILE="$CACHE_DIR/nix-update-boot-marker"  # Marker file to detect boot/resume
    TOGGLE_FILE="$CACHE_DIR/nix-update-toggle"  # Toggle file to enable/disable update checking

    # The grace period prevents the update checker from running immediately after:
    # 1. First boot - when the system has just started up
    # 2. Resume from hibernation/suspension - when the system has just woken up
    # This avoids unnecessary resource usage and notifications during these transition periods.
    SKIP_AFTER_BOOT=true  # Set to false if you want to run the checker even after boot/resume
    GRACE_PERIOD=60  # Grace period in seconds (60 seconds) after boot/resume

    # If true, update the lock file in the config folder.
    # If false, copy config to temp folder first, and then update the temp dir's lock file.
    UPDATE_LOCK_FILE="false"

    # If you have a separate script to update your lock file (i.e. "nix flake update" script)
    # and you have UPDATE_LOCK_FILE set to "false",
    # the UPDATE_FLAG will signal that your lock file has been updated.
    # Add the following to your update script so that the output of nvd diff is piped in:
    # | tee >(if grep -qe '\\[U'; then touch \"$HOME/.cache/nix-update-update-flag\"; else rm -f \"$HOME/.cache/nix-update-update-flag\"; fi) &&
    UPDATE_FLAG="$CACHE_DIR/nix-update-update-flag"

    # The REBUILD_FLAG signals this script to run after your system has been rebuilt.
    # Add this to your update script:
    # if [ -f \"$HOME/.cache/nix-update-update-flag\" ]; then touch \"$HOME/.cache/nix-update-rebuild-flag\" && pkill -x -RTMIN+12 .waybar-wrapped; fi &&
    REBUILD_FLAG="$CACHE_DIR/nix-update-rebuild-flag"

    # The UPDATING_FLAG signals if upgrade process is currently performing
    # This is required to force waybar module to render while we wait for nixos rebuild.
    UPDATING_FLAG="$CACHE_DIR/nix-update-updating-flag"


    # ===== Initialize Files =====
    function init_files() {
        # Ensure cache directory exists
        mkdir -p "$CACHE_DIR"
        
        # Create the state file if it doesn't exist
        if [ ! -f "$STATE_FILE" ]; then
            echo "0" > "$STATE_FILE"
        fi

        # Create the last run file if it doesn't exist
        if [ ! -f "$LAST_RUN_FILE" ]; then
            echo "0" > "$LAST_RUN_FILE"
        fi

        # Create the tooltip file if it doesn't exist
        if [ ! -f "$LAST_RUN_TOOLTIP" ]; then
            updates=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
            if [ "$updates" = "0" ] || [ -z "$updates" ]; then
                echo "System updated" > "$LAST_RUN_TOOLTIP"
            else
                # Will be populated during update check
                echo "Checking for updates..." > "$LAST_RUN_TOOLTIP"
            fi
        fi
        
        # Create the toggle file if it doesn't exist (default: enabled)
        if [ ! -f "$TOGGLE_FILE" ]; then
            echo "enabled" > "$TOGGLE_FILE"
        fi
    }

    # ===== Helper Functions =====
    function send_notification() {
        local icon="$1"
        local title="$2"
        local message="$3"
        local expire_flag="$4" # Optional fourth parameter for -e flag
        notify-send -i "$HOME/.icons/$icon.png" "$title" "$message" $expire_flag
    }

    function check_boot_resume() {
            # This function detects if the system has recently booted or resumed from hibernation/sleep
            # Returns 0 (true) if we're in the grace period, 1 (false) otherwise

            local current_time=$(date +%s)
            local uptime_seconds=$(cat /proc/uptime | awk '{print int($1)}')
            local last_boot_time=$((current_time - uptime_seconds))

            # Check if this is first run after boot
            if [ ! -f "$BOOT_MARKER_FILE" ] || [ $((current_time - last_boot_time)) -lt "$GRACE_PERIOD" ]; then
                # We're either in first run or within grace period after boot
                echo "$current_time" > "$BOOT_MARKER_FILE"
                return 0
            fi

            # Initialize resume timestamp
            local last_resume=0

            # Try to detect resume using systemd logs
            if command -v journalctl >/dev/null 2>&1; then
                # Get timestamp of last resume/wakeup event from systemd journal
                local resume_log=$(journalctl -b -u systemd-suspend.service -u systemd-hibernate.service -n 1 -o short-unix 2>/dev/null)
                if [ -n "$resume_log" ]; then
                    # Extract just the numeric timestamp from the beginning of the line
                    local timestamp=$(echo "$resume_log" | sed -E 's/^([0-9]+).*/\1/')
                    if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                        last_resume=$timestamp
                    fi
                fi

                # If no direct service logs, try looking for resume messages in kernel logs
                if [ $last_resume -eq 0 ]; then
                    local wake_log=$(journalctl -b -k -g "PM: resumed" -n 1 -o short-unix 2>/dev/null)
                    if [ -n "$wake_log" ]; then
                        # Extract just the numeric timestamp from the beginning of the line
                        local timestamp=$(echo "$wake_log" | sed -E 's/^([0-9]+).*/\1/')
                        if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                            last_resume=$timestamp
                        fi
                    fi
                fi
            fi

            # Check if we can find resume info in NixOS-specific locations
            if [ $last_resume -eq 0 ] && [ -d "/run/systemd/system" ]; then
                # Check systemd sleep state
                if [ -f "/run/systemd/suspend/active" ] || [ -f "/run/systemd/hibernate/active" ]; then
                    last_resume=$current_time  # Just woke up
                fi
            fi

            # If we detected a resume and it's recent, we're in grace period
            if [ $last_resume -gt 0 ] && [ $((current_time - last_resume)) -lt "$GRACE_PERIOD" ]; then
                echo "$current_time" > "$BOOT_MARKER_FILE"
                return 0
            fi

            # Check if we have a saved boot marker and we're still in grace period
            if [ -f "$BOOT_MARKER_FILE" ]; then
                local marker_time=$(cat "$BOOT_MARKER_FILE")
                if [[ "$marker_time" =~ ^[0-9]+$ ]] && [ $((current_time - marker_time)) -lt "$GRACE_PERIOD" ]; then
                    return 0  # Still in grace period from marker
                fi
            fi

            # Not in grace period
            return 1
        }

    function check_network_connectivity() {
        # Check if we have a default route and an IP on a non-loopback interface
        if ip route | grep -q "^default" && \
           ip -4 addr show | grep -E "inet .* scope global" > /dev/null 2>&1; then
            return 0  # Network is configured
        else
            return 1  # No network
        fi
    }

    function sys_updated() {
      if [ -f "$REBUILD_FLAG" ]; then
        return 0 # System has been updated
      else
        return 1 # System has not been updated
      fi
    }

    function calc_next_update() {
        local last_run=$(cat "$LAST_RUN_FILE")
        local current_time=$(date +%s)
        local next_update=$((UPDATE_INTERVAL - (current_time - last_run)))
        local next_update_min=$((next_update / 60))
        echo "$next_update_min"
    }

    function var_setter() {
        # Ensure updates is a number
        if [ -z "$updates" ]; then
            updates=0
        fi
        
        if [ "$updates" -ne 0 ]; then
            alt="has-updates"
            tooltip=$(cat "$LAST_RUN_TOOLTIP" 2>/dev/null || echo "$updates updates available")
        else
            alt="updated"
            tooltip="System updated"
        fi
    }

    # ===== Update Check Logic =====
    function check_for_updates() {
        local tempdir=$(mktemp -d)
        # Ensure cleanup happens when script exits
        trap "rm -rf '$tempdir'" EXIT
    
        send_notification "updates-checking" "Checking for Updates" "Please be patient" -e
    
        local updates=0
        local tooltip=""
        local error_output=""

        if [ "$UPDATE_LOCK_FILE" = "true" ]; then
            # Use the config directory directly
            cd "$NIXOS_CONFIG_PATH" || return 1
            nix flake update
            # Capture stderr and extract the error line
            error_output=$(nix build .#nixosConfigurations.$(hostname).config.system.build.toplevel 2>&1)
            if [ "$?" -eq 0 ]; then
                updates=$(nvd diff /run/current-system ./result | grep -e '\[U' | wc -l)
                tooltip=$(nvd diff /run/current-system ./result | grep -e '\[U' | awk '{ for (i=3; i<NF; i++) printf $i " "; if (NF >= 3) print $NF; }' | awk '{printf "%s%s", (NR>1 ? "\\n" : ""), $0}')
            else
                # Extract just the error line starting with "error:"
                error_line=$(echo "$error_output" | grep "^       error:" | head -1 | sed 's/^[[:space:]]*//')
                echo "$error_line" > "$LAST_RUN_TOOLTIP"
                return 1
            fi
        else
            # Use a temp directory to avoid modifying lock file
            cp -r "$NIXOS_CONFIG_PATH"/* "$tempdir"
            cd "$tempdir" || return 1
            nix flake update
            # Capture stderr and extract the error line
            error_output=$(nix build .#nixosConfigurations.$(hostname).config.system.build.toplevel 2>&1)
            if [ "$?" -eq 0 ]; then
                updates=$(nvd diff /run/current-system ./result | grep -e '\[U' | wc -l)
                tooltip=$(nvd diff /run/current-system ./result | grep -e '\[U' | awk '{ for (i=3; i<NF; i++) printf $i " "; if (NF >= 3) print $NF; }' | awk '{printf "%s%s", (NR>1 ? "\\n" : ""), $0}')
            else
                # Extract just the error line starting with "error:"
                error_line=$(echo "$error_output" | grep "^       error:" | head -1 | sed 's/^[[:space:]]*//')
                echo "$error_line" > "$LAST_RUN_TOOLTIP"
                return 1
            fi
        fi

        # Save results
        echo "$updates" > "$STATE_FILE"
        echo "$(date +%s)" > "$LAST_RUN_FILE"
    
        if [ "$updates" -eq 0 ]; then
            echo "System updated" > "$LAST_RUN_TOOLTIP"
            send_notification "updates-complete" "Update Check Complete" "No updates available" -e
        elif [ "$updates" -eq 1 ]; then
            echo "$tooltip" > "$LAST_RUN_TOOLTIP"
            send_notification "updates-pending" "Update Check Complete" "Found 1 update" -e
        else
            echo "$tooltip" > "$LAST_RUN_TOOLTIP"
            send_notification "updates-pending" "Update Check Complete" "Found $updates updates" -e
        fi
    
        return 0
    }

    # ===== Toggle Function =====
    function toggle_updates() {
        CACHE_DIR="$HOME/.cache"
        TOGGLE_FILE="$CACHE_DIR/nix-update-toggle"
        
        # Initialize toggle file if it doesn't exist (default: enabled)
        if [ ! -f "$TOGGLE_FILE" ]; then
            echo "enabled" > "$TOGGLE_FILE"
        fi
        
        # Get current state
        current_state=$(cat "$TOGGLE_FILE")
        
        # Toggle the state
        if [ "$current_state" = "enabled" ]; then
            echo "disabled" > "$TOGGLE_FILE"
        else
            echo "enabled" > "$TOGGLE_FILE"
        fi
        
        # Send signal to refresh waybar update module
        pkill -x -RTMIN+12 .waybar-wrapped
    }

    # ===== Main Function =====
    function main() {
        init_files

        # Check if update checking is disabled via toggle
        if [ -f "$TOGGLE_FILE" ] && [ "$(cat "$TOGGLE_FILE")" = "disabled" ]; then
            # Updates are disabled, show last known state without checking
            local updates=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
            local alt=""
            local tooltip=""
            
            # Read the existing tooltip (which contains the actual update list)
            local existing_tooltip=$(cat "$LAST_RUN_TOOLTIP" 2>/dev/null || "")
            
            # Get last run timestamp and format it
            local last_run=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
            local last_run_formatted=""
            if [ "$last_run" != "0" ]; then
                last_run_formatted=$(date -d "@$last_run" "+%Y-%m-%d %H:%M")
            else
                last_run_formatted="never"
            fi
            
            if [ "$updates" = "0" ] || [ -z "$updates" ]; then
                alt="disabled"
                tooltip="Updates disabled (Last checked: $last_run_formatted)"
            else
                alt="disabled"
                # Show the original tooltip content with disabled indicator and timestamp
                if [ -n "$existing_tooltip" ] && [ "$existing_tooltip" != "System updated" ]; then
                    # Preserve the original update list with timestamp
                    tooltip="Updates disabled (Last checked: $last_run_formatted)\n─────────────────────────────────────────────────\n$existing_tooltip"
                else
                    # Fallback if no proper tooltip exists
                    tooltip="Updates disabled ($updates pending)\nLast checked: $last_run_formatted"
                fi
            fi
            # Output JSON without modifying the tooltip file
            echo "{ \"text\":\"$updates\", \"alt\":\"$alt\", \"tooltip\":\"$tooltip\" }"
            exit 0
        fi

        # Check if we're in post-boot/resume grace period
        if [ "$SKIP_AFTER_BOOT" = "true" ] && check_boot_resume; then
            # Skip update check during grace period after boot or resume from hibernation
            # This prevents unnecessary resource usage during system startup or wakeup
            local updates=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
            local alt=""
            local tooltip=""
            var_setter
            echo "{ \"text\":\"$updates\", \"alt\":\"$alt\", \"tooltip\":\"$tooltip\" }"
            exit 0
        fi

        # Check for network connectivity before proceeding
        if check_network_connectivity; then
          local updates=""
          local alt=""
          local tooltip=""

          # Delete flags if system was just updated
          if sys_updated; then
              updates=0
              alt="updated"
              tooltip="System updated"
              echo "$updates" > "$STATE_FILE"
              echo "$tooltip" > "$LAST_RUN_TOOLTIP"
              if [ -f "$UPDATE_FLAG" ]; then
                rm "$UPDATE_FLAG"
              fi
              rm "$REBUILD_FLAG"
          else
              # Read state from files
              updates=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
              local last_run=$(cat "$LAST_RUN_FILE" 2>/dev/null || echo "0")
              local current_time=$(date +%s)

             
              # Decide whether to show saved state or perform new check
              if [ $((current_time - last_run)) -gt "$UPDATE_INTERVAL" ]; then
                  # Separating updating and updated phase
                  if [ -f $UPDATING_FLAG ]; then
                      # Time to check for updates
                      if check_for_updates; then
                          updates=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
                          var_setter
                      else
                          # Update check failed - read the full error from tooltip file
                          updates="0"
                          alt="error"
                          tooltip=$(cat "$LAST_RUN_TOOLTIP" 2>/dev/null || echo "Check failed")
                          send_notification "updates-failed" "Update Check Failed" "Check tooltip for detailed error message"
                      fi
                      
                      rm $UPDATING_FLAG
                  else
                      updates=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
                      alt="updating"
                      # Show previous updates while checking for new ones
                      local existing_tooltip=$(cat "$LAST_RUN_TOOLTIP" 2>/dev/null || "")
                      if [ "$updates" != "0" ] && [ -n "$existing_tooltip" ] && [ "$existing_tooltip" != "System updated" ]; then
                          tooltip="Checking for updates... Previous check found:\n=============================================\n$existing_tooltip"
                      else
                          tooltip="Checking for updates..."
                      fi
                      touch $UPDATING_FLAG
                      # Rerun same script just to show updating status and
                      # run update process in separate thread
                      pkill -x -RTMIN+12 .waybar-wrapped
                  fi
              else
                  # Use saved state
                  send_notification "updates-wait" "Please Wait" "Next update is in $(calc_next_update) min." -e
                  var_setter
              fi
          fi
        else
            updates=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
            if [ -z "$updates" ]; then
                updates="0"
            fi
            alt="updated"
            tooltip="No network connection"
            send_notification "updates-failed" "Update Check Failed" "Not connected to the internet"
        fi

        # Output JSON for Waybar
        echo "{ \"text\":\"$updates\", \"alt\":\"$alt\", \"tooltip\":\"$tooltip\" }"
    }

    # Error handler to ensure we always output valid JSON
    trap 'echo "{ \"text\":\"?\", \"alt\":\"error\", \"tooltip\":\"Script error occurred\" }"' ERR
    
    # Check for command-line arguments
    if [ "$1" = "toggle" ]; then
        toggle_updates
    else
        # Execute main function
        main
    fi
  '';

  in
  {
    home.packages = [
      update_checker
    ];

    home.file.".icons" = {
      recursive = true;
      source = ./.icons;
    };
  }
