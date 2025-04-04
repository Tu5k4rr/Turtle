#!/bin/bash

# Set -o pipefail ensures that a pipeline returns a failure if any command fails
set -o pipefail
# Define log_success and log_error functions for better feedback
log_success() {
    echo "✅ SUCCESS: $1"
}

log_error() {
    echo "❌ ERROR: $1"
    # Don't exit by default, let the caller decide
}

# Check for sudo privileges but run Homebrew as non-root
check_privileges() {
    # Store whether the script was started with sudo
    SCRIPT_STARTED_WITH_SUDO=false
    if [ "$EUID" -eq 0 ]; then
        SCRIPT_STARTED_WITH_SUDO=true
        # Get the actual user who invoked sudo
        SUDO_USER_HOME=$(eval echo ~${SUDO_USER})
        echo "Script is running with sudo privileges. Will drop to normal user for Homebrew."
    else
        echo "Script is running without sudo. Will use sudo for operations that require it."
    fi
    
    # Make sure we can use sudo when needed
    if ! sudo -v &>/dev/null; then
        echo "This script requires the ability to run commands with sudo."
        echo "Please enter your password to continue."
        sudo -v
        if [ $? -ne 0 ]; then
            echo "Failed to obtain sudo privileges. Exiting."
            exit 1
        fi
    fi
    
    # Keep sudo alive for the duration of the script
    # Update existing sudo time stamp if set, otherwise do nothing
    while true; do sudo -n true; sleep 60; kill -0 "$" || exit; done 2>/dev/null &
    
    # Store the background process ID so we can kill it later
    SUDO_KEEP_ALIVE_PID=$!
}

# Function to check macOS version
check_macos_version() {
    if [[ $(sw_vers -productVersion) != "15"* ]]; then
        echo "Error: This tool is designed for macOS 15 (Sequoia). Update your machine!!"
        exit 1
    fi
}

#Function to check and enable firewall hardening
check_firewall() {
    echo "Checking firewall status..."
    if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q "enabled"; then
        log_success "Firewall is already enabled."
    else
        # Enable the firewall
        echo "Enabling Application Layer Firewall..."
        /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
        if [ $? -ne 0 ]; then
            log_error "Failed to enable firewall"
            return 1
        fi
    fi
    
    # Block all incoming connections except those explicitly allowed
    echo "Blocking all incoming connections..."
    /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned off
    /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsignedapp off
    /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on

    # Enable stealth mode (don't respond to pings)
    echo "Enabling stealth mode..."
    /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
    
    # Verify firewall settings
    if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q "enabled"; then
        log_success "Firewall properly configured"
    else
        log_error "Firewall configuration failed"
        return 1
    fi
    
    return 0
}

# Function for check privacy and enhance
check_privacy() {
    # Disable telemetry (diagnostic reports)
    echo "Disabling diagnostic reports..."
    defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmit -bool false
    defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmitVersion -int 0

    # Disable Siri analytics
    echo "Disabling Siri analytics..."
    defaults write com.apple.assistant.analytics "AnalyticsEnabled" -bool false

    # Configure Safari privacy settings
    echo "Configuring Safari privacy settings..."
    defaults write com.apple.Safari UniversalSearchEnabled -bool false
    defaults write com.apple.Safari SuppressSearchSuggestions -bool true

    # Disable mDNS multicast advertisements (Bonjour)
    echo "Disabling mDNS multicast advertisements..."
    defaults write /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist ProgramArguments -array-add "-NoMulticastAdvertisements"

    # Verify mDNS setting
    echo "Verifying mDNS setting..."
    if cat /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist | grep -q "NoMulticastAdvertisements"; then
        log_success "mDNS multicast advertisements disabled successfully!"
    else
        log_error "Failed to disable mDNS multicast advertisements."
        # Don't exit, continue with other settings
    fi

    # Verify a setting (example: Safari search suggestions)
    echo "Verifying Safari privacy settings..."
    if defaults read com.apple.Safari SuppressSearchSuggestions | grep -q "1"; then
        log_success "Safari privacy settings applied successfully!"
    else
        log_error "Failed to apply Safari privacy settings."
        # Don't exit, continue with other settings
    fi
    
    # Fix screen saver corners
    echo "Fixing Screen Saver Corners"
    # Replace placeholder with all four corner settings to ensure none are set to '6' (Start Screen Saver)
    defaults write com.apple.dock wvous-tl-corner -int 0
    defaults write com.apple.dock wvous-tr-corner -int 0
    defaults write com.apple.dock wvous-bl-corner -int 0
    defaults write com.apple.dock wvous-br-corner -int 0
    
    return 0
}

# Function for filevault check and enable
check_filevault() {
    echo "Checking FileVault status..."
    if diskutil apfs list | grep -q "FileVault: Yes"; then
        log_success "FileVault is already enabled."
        return 0
    fi

    # Enable FileVault
    echo "Enabling FileVault..."
    fdesetup enable
    filevault_result=$?

    # Note: FileVault enabling requires user interaction to set up a recovery key
    echo "Please follow the prompts to set up FileVault. A recovery key will be generated."
    echo "After enabling, the system may need to restart to complete encryption."

    if [ $filevault_result -eq 0 ]; then
        log_success "FileVault setup initiated. Full encryption will begin after restart."
    else
        log_error "FileVault enabling failed"
        return 1
    fi
    
    return 0
}

check_gatekeeper() {
    # Enable Gatekeeper
    echo "Enabling Gatekeeper..."
    spctl --master-enable

    # Verify Gatekeeper status
    echo "Verifying Gatekeeper status..."
    if spctl --status | grep -q "assessments enabled"; then
        log_success "Gatekeeper successfully enabled!"
    else
        log_error "Failed to enable Gatekeeper."
        return 1
    fi

    # Check for Hardened Runtime (example: check a system app like Safari)
    echo "Checking Hardened Runtime for Safari..."
    if codesign -dv --verbose /Applications/Safari.app 2>&1 | grep -q "hardened"; then
        log_success "Safari uses Hardened Runtime."
    else
        echo "Warning: Safari does not use Hardened Runtime."
    fi

    # Note: Hardened Runtime verification is informational; not all apps may support it
    echo "Note: Some third-party apps may not use Hardened Runtime. Check critical apps manually."
    
    # Check SIP status instead of trying to enable it
    echo "Checking System Integrity Protection status..."
    if csrutil status | grep -q "enabled"; then
        log_success "System Integrity Protection is enabled"
    else
        echo "WARNING: System Integrity Protection is disabled!"
        echo "To enable SIP, reboot into Recovery Mode and run 'csrutil enable' from Terminal."
    fi
    
    return 0
}

check_accounts() {
    echo "Checking root account status..."
    rootCheck=`dscl . read /Users/root | grep AuthenticationAuthority 2>&1 > /dev/null ; echo $?`
    if [ "${rootCheck}" == 1 ]; then
        log_success "Root is already disabled"
    else
        echo "Root is enabled - disabling it now"

        # remove the AuthenticationAuthority from the user's account
        dscl . delete /Users/root AuthenticationAuthority

        # Put a single asterisk in the password entry, thus locking the account.
        dscl . -create /Users/root Password '*'

        # Disable root login by setting root's shell to /usr/bin/false
        ## This will prevent use of 'su root' or 'su -' to elevate to root.
        ## Comment out, remove, or use 'sudo' with another admin account if needed.
        dscl . -create /Users/root UserShell /usr/bin/false

        # Let's validate and report back the post-script results.
        rootCheck=`dscl . read /Users/root | grep AuthenticationAuthority 2>&1 > /dev/null ; echo $?`
        if [ "${rootCheck}" == 1 ]; then
            log_success "Root was Enabled and is now Disabled"
        else
            log_error "Root was Enabled and is still Enabled, Please try again!"
        fi
    fi
    
    echo "Checking guest account status..."
    guest_status=$(dscl . -read /Users/Guest 2>/dev/null | grep -c "AuthenticationAuthority")    
    if [ "$guest_status" -gt 0 ]; then
        echo "Guest account is enabled. Attempting to disable..."        
        # Disable guest account
        if ! dscl . -delete /Users/Guest AuthenticationAuthority 2>/dev/null; then
            log_error "Failed to disable guest account."
        else       
            # Disable guest account login
            if ! defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool NO; then
                log_error "Failed to disable guest login."
            else
                log_success "Guest account successfully disabled."
            fi
        fi        
    else
        log_success "Guest account is already disabled. No action needed."
    fi    
    
    return 0
}

# Function for remote access
check_access() {
    #automatic login
    echo "Disabling Auto Login"
    defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null
    
    #remote login
    echo "Disabling Remote Login"
    systemsetup -setremotelogin off
    
    echo "Disabling Remote Management"
    /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop

    echo "Disabling Remote Apple Events"
    systemsetup -setremoteappleevents off
    
    echo "Disabling Bonjour advertisement service"
    defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true
    
    log_success "Remote access services disabled"
    return 0
}

check_sharing() {
    echo "Disabling Internet sharing"
    defaults write /Library/Preferences/SystemConfiguration/com.apple.nat NAT -dict Enabled -int 0
    
    echo "Disabling Bluetooth sharing"
    defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false
    
    echo "Disabling DVD sharing"
    launchctl disable system/com.apple.ODSAgent 2>/dev/null
    launchctl bootout system/com.apple.ODSAgent 2>/dev/null
    
    echo "Disabling File sharing"
    launchctl disable system/com.apple.smbd 2>/dev/null
    launchctl bootout system/com.apple.smbd 2>/dev/null
    
    echo "Disabling Printer sharing"
    cupsctl --no-share-printers
    
    echo "Disabling screen sharing"
    launchctl disable system/com.apple.screensharing 2>/dev/null
    launchctl bootout system/com.apple.screensharing 2>/dev/null
    
    log_success "Sharing services disabled"
    return 0
}

check_airdrop() {
    echo "Disabling Airdrop"
    defaults write com.apple.NetworkBrowser DisableAirDrop -bool true
    log_success "AirDrop disabled"
    return 0
}

check_wireless() {
    echo "Bluetooth hardening"
    echo "Disabling Bluetooth"
    defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -bool false
    
    echo "Setting Bluetooth status in navbar"
    defaults write com.apple.controlcenter "NSStatusItem Visible BlueTooth" -bool true
    
    echo "Setting WiFi Status in navbar"
    defaults write com.apple.controlcenter "NSStatusItem Visible WiFi" -bool true
    
    echo "Disabling wake on network"
    pmset -a womp 0
    
    log_success "Wireless settings configured"
    return 0
}

check_additional() {
    echo "Locking screen when screensaver initiates"
    defaults -currentHost write com.apple.screensaver askForPassword -int 1
    defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0
    
    echo "Setting screen saver to 10 minutes"
    defaults -currentHost write com.apple.screensaver idleTime -int 600
    
    echo "Enabling secure keyboard"
    defaults write -app Terminal SecureKeyboardEntry -bool true
    
    log_success "Additional hardening settings applied"
    return 0
}

check_updates() {
    echo "Enabling auto update"
    defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
    
    echo "Setting updates to download automatically"
    defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
    
    echo "Enabling auto install for updates"
    defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
    
    echo "Ensuring Security responses and system files updates are enabled"
    defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
    defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
    
    echo "Checking for available updates..."
    softwareupdate -l
    
    echo "Installing all available updates..."
    softwareupdate -i -a
    update_result=$?
    
    if [ $update_result -eq 0 ]; then
        log_success "Software updates completed successfully"
    else
        log_error "Some updates may have failed to install"
    fi
    
    return 0
}

install_software() {
    echo "🚀 Starting installation process..."
    
    # Handle Homebrew installation as non-root user
    if [ "$EUID" -eq 0 ]; then
        # We're running as root, need to drop to the actual user for Homebrew
        echo "Dropping to non-root user for Homebrew operations..."
        
        # Get the actual user's name and home directory
        REAL_USER="${SUDO_USER}"
        REAL_USER_HOME=$(eval echo ~${SUDO_USER})
        
        if [ -z "$REAL_USER" ]; then
            log_error "Cannot determine the real user who invoked sudo. Cannot install Homebrew."
            echo "Please run this script without sudo for the Homebrew portion."
            echo "Would you like to continue with the rest of the script without Homebrew? (y/n)"
            read -r continue_without_brew
            if [[ "$continue_without_brew" != "y" ]]; then
                echo "Exiting as requested."
                exit 1
            else
                echo "Continuing without Homebrew..."
                return 1
            fi
        fi
        
        # Create a temporary script to run as the real user
        TEMP_SCRIPT=$(mktemp)
        
        # Write the Homebrew installation logic to the temporary script
        cat << 'EOT' > "$TEMP_SCRIPT"
#!/bin/bash
set -e

# Log functions
log_success() {
    echo "✅ SUCCESS: $1"
}

log_error() {
    echo "❌ ERROR: $1"
}

# Ensure XCode Command Line Tools are installed
echo "Checking for XCode Command Line Tools..."
if ! xcode-select -p &>/dev/null; then
    echo "XCode Command Line Tools not found. Installing..."
    xcode-select --install
    
    echo "Please wait for XCode Command Line Tools to finish installing"
    echo "Then press Enter to continue..."
    read -r
else
    echo "XCode Command Line Tools are already installed."
fi

# Check if Homebrew is already installed
if ! command -v brew &> /dev/null; then
    # Detect architecture
    architecture=$(uname -m)
    echo "Detected architecture: $architecture"
    
    # Install Homebrew
    echo "Installing Homebrew as normal user..."
    
    # Use a temporary file to capture output and errors
    BREW_LOG=$(mktemp)
    echo "Logging to $BREW_LOG"
    
    # Run the Homebrew installer
    if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" &> "$BREW_LOG"; then
        echo "==== Homebrew installation error ===="
        cat "$BREW_LOG"
        echo "====================================="
        log_error "Homebrew installation failed. See details above."
        
        # Clean up
        rm "$BREW_LOG"
        exit 1
    fi
    
    # Clean up
    rm "$BREW_LOG"
    
    # Add Homebrew to PATH for this session based on architecture
    if [ "$architecture" = "arm64" ] && [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile 2>/dev/null
        log_success "Homebrew installed and added to PATH (Apple Silicon)"
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile 2>/dev/null
        log_success "Homebrew installed and added to PATH (Intel)"
    else
        log_error "Homebrew installation appeared to succeed but executable not found in expected locations."
        echo "Trying to find brew manually..."
        BREW_PATH=$(find /usr/local /opt -name brew 2>/dev/null | head -n 1)
        
        if [ -n "$BREW_PATH" ]; then
            echo "Found brew at: $BREW_PATH"
            BREW_DIR=$(dirname "$BREW_PATH")
            eval "$($BREW_DIR/brew shellenv)"
            echo "eval \"$($BREW_DIR/brew shellenv)\"" >> ~/.zshrc
            echo "eval \"$($BREW_DIR/brew shellenv)\"" >> ~/.bash_profile 2>/dev/null
            log_success "Homebrew found and added to PATH"
        else
            echo "Could not find brew executable. You may need to install Homebrew manually."
            exit 1
        fi
    fi
else
    log_success "Homebrew is already installed"
fi

# Update Homebrew
echo "Updating Homebrew..."
if ! brew update; then
    log_error "Failed to update Homebrew, but continuing..."
fi

# Install tools
echo "Installing Firefox ESR..."
brew install --cask firefox@esr || echo "Firefox ESR installation failed"

echo "Installing Tor Browser..."
brew install --cask tor-browser || echo "Tor Browser installation failed"

echo "Installing Tor..."
brew install tor || echo "Tor installation failed"

echo "Installing KeepassXC..."
brew install --cask keepassxc || echo "KeepassXC installation failed"

echo "Installing Private Internet Access VPN..."
brew install --cask private-internet-access || echo "PIA VPN installation failed"

echo "Homebrew installation and software setup complete"
EOT
        
        # Make the script executable
        chmod +x "$TEMP_SCRIPT"
        
        # Run the script as the real user
        echo "Running Homebrew installation as user $REAL_USER..."
        su - "$REAL_USER" -c "$TEMP_SCRIPT" || {
            log_error "Homebrew installation failed when running as $REAL_USER"
            echo "Would you like to continue with the rest of the script without Homebrew? (y/n)"
            read -r continue_without_brew
            if [[ "$continue_without_brew" != "y" ]]; then
                echo "Exiting as requested."
                rm "$TEMP_SCRIPT"
                exit 1
            fi
        }
        
        # Clean up
        rm "$TEMP_SCRIPT"
        return 0
        
    else
        # We're already running as a non-root user, proceed with normal Homebrew installation
        # Check if Homebrew is already installed
        if ! command -v brew &> /dev/null; then
            echo "Installing Homebrew..."
            
            # Ensure XCode Command Line Tools are installed (required for Homebrew)
            echo "Checking for XCode Command Line Tools..."
            if ! xcode-select -p &>/dev/null; then
                echo "XCode Command Line Tools not found. Installing..."
                # This will prompt the user to install the command line tools
                xcode-select --install
                
                echo "Please wait for XCode Command Line Tools to finish installing"
                echo "Then press Enter to continue..."
                read -r
            else
                echo "XCode Command Line Tools are already installed."
            fi
            
            # Detect the CPU architecture
            architecture=$(uname -m)
            echo "Detected architecture: $architecture"
            
            # Install Homebrew with enhanced error handling
            echo "Installing Homebrew..."
            
            # Use a temporary file to capture output and errors
            BREW_LOG=$(mktemp)
            echo "Logging to $BREW_LOG"
            
            # Run the Homebrew installer
            if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" &> "$BREW_LOG"; then
                echo "==== Homebrew installation error ===="
                cat "$BREW_LOG"
                echo "====================================="
                log_error "Homebrew installation failed. See details above."
                
                # Check for common issues
                if grep -q "Command Line Tools" "$BREW_LOG"; then
                    echo "It seems XCode Command Line Tools are required."
                    echo "Please run 'xcode-select --install' and try again after it completes."
                fi
                
                # Clean up
                rm "$BREW_LOG"
                
                # Ask user if they want to continue without Homebrew
                echo "Would you like to continue with the rest of the script without Homebrew? (y/n)"
                read -r continue_without_brew
                if [[ "$continue_without_brew" != "y" ]]; then
                    echo "Exiting as requested."
                    exit 1
                else
                    echo "Continuing without Homebrew..."
                    return 1
                fi
            fi
            
            # Clean up
            rm "$BREW_LOG"
            
            # Add Homebrew to PATH for this session based on architecture
            if [ "$architecture" = "arm64" ] && [ -f /opt/homebrew/bin/brew ]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
                # Also add to bash_profile for good measure
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile 2>/dev/null
                log_success "Homebrew installed and added to PATH (Apple Silicon)"
            elif [ -f /usr/local/bin/brew ]; then
                eval "$(/usr/local/bin/brew shellenv)"
                echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zshrc
                # Also add to bash_profile for good measure
                echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.bash_profile 2>/dev/null
                log_success "Homebrew installed and added to PATH (Intel)"
            else
                log_error "Homebrew installation appeared to succeed but executable not found in expected locations."
                echo "Trying to find brew manually..."
                BREW_PATH=$(find /usr/local /opt -name brew 2>/dev/null | head -n 1)
                
                if [ -n "$BREW_PATH" ]; then
                    echo "Found brew at: $BREW_PATH"
                    BREW_DIR=$(dirname "$BREW_PATH")
                    eval "$($BREW_DIR/brew shellenv)"
                    echo "eval \"$($BREW_DIR/brew shellenv)\"" >> ~/.zshrc
                    echo "eval \"$($BREW_DIR/brew shellenv)\"" >> ~/.bash_profile 2>/dev/null
                    log_success "Homebrew found and added to PATH"
                else
                    echo "Could not find brew executable. You may need to install Homebrew manually."
                    
                    # Ask user if they want to continue without Homebrew
                    echo "Would you like to continue with the rest of the script without Homebrew? (y/n)"
                    read -r continue_without_brew
                    if [[ "$continue_without_brew" != "y" ]]; then
                        echo "Exiting as requested."
                        exit 1
                    else
                        echo "Continuing without Homebrew..."
                        return 1
                    fi
                fi
            fi
            
            # Give Homebrew a moment to initialize
            sleep 2
            
            # Update Homebrew
            echo "Updating Homebrew..."
            if ! brew update; then
                log_error "Failed to update Homebrew, but continuing..."
            fi
        else
            log_success "Homebrew is already installed"
            
            # Update Homebrew
            echo "Updating Homebrew..."
            if ! brew update; then
                log_error "Failed to update Homebrew, but continuing..."
            fi
        fi
        
        # Only attempt to install software if Homebrew is available
        if command -v brew &> /dev/null; then
            # Install Firefox ESR
            echo "Installing Firefox ESR..."
            if ! brew install --cask firefox@esr; then
                log_error "Firefox ESR installation failed"
                echo "You may need to install Firefox ESR manually from: https://www.mozilla.org/en-US/firefox/enterprise/"
            else
                log_success "Firefox ESR installed"
            fi
            
            # Install Tor Browser and tor
            echo "Installing Tor Browser..."
            if ! brew install --cask tor-browser; then
                log_error "Tor Browser installation failed"
                echo "You may need to install Tor Browser manually from: https://www.torproject.org/download/"
            else
                log_success "Tor Browser installed"
            fi
            
            echo "Installing Tor..."
            if ! brew install tor; then
                log_error "Tor installation failed"
                echo "You can try installing Tor manually if needed"
            else
                log_success "Tor installed"
            fi
            
            # Install KeepassXC
            echo "Installing KeepassXC..."
            if ! brew install --cask keepassxc; then
                log_error "KeepassXC installation failed"
                echo "You may need to install KeepassXC manually from: https://keepassxc.org/download/"
            else
                log_success "KeepassXC installed"
            fi
            
            # Install PIA VPN
            echo "Installing Private Internet Access VPN..."
            if ! brew install --cask private-internet-access; then
                log_error "PIA VPN installation failed" 
                echo "You may need to install PIA VPN manually from: https://www.privateinternetaccess.com/download/"
            else
                log_success "PIA VPN installed"
            fi
        else
            log_error "Homebrew is not available. Software installation skipped."
            echo "You may need to install the following software manually:"
            echo "- Firefox ESR: https://www.mozilla.org/en-US/firefox/enterprise/"
            echo "- Tor Browser: https://www.torproject.org/download/"
            echo "- KeepassXC: https://keepassxc.org/download/"
            echo "- Private Internet Access VPN: https://www.privateinternetaccess.com/download/"
        fi
    fi
    
    log_success "Software installation completed"
    return 0
    

    
    log_success "Software installation completed"
    return 0
}

# Main function to orchestrate all operations
# Display turtle ASCII art
display_turtle_art() {
    cat << "EOF"
                  __
         .,-;-;-,. /'_\
       _/_/_/_|_\_\) /
     '-<_><_><_><_>=/\
       `/_/====/_/-'\_\
        ""     ""    ""
    
     🐢 🐢 🐢 🐢 🐢 🐢 🐢 🐢 🐢
EOF
}

main() {
    clear
    display_turtle_art
    echo "=========================================================="
    echo "  🔒 MacOS Hardening Script - Turtle.sh 🐢"
    echo "  Starting security hardening process..."
    echo "=========================================================="
    
    # Check privileges - can operate with or without sudo initially
    check_privileges
    
    # Check macOS version
    check_macos_version
    
    # Create an array to track functions that need a reboot
    declare -a reboot_required_functions
    
    # Run all functions and track which ones need a reboot
    echo "Installing security software..."
    install_software
    
    echo "Configuring firewall..."
    check_firewall
    
    echo "Enhancing privacy settings..."
    check_privacy
    
    echo "Setting up FileVault encryption..."
    check_filevault
    if [ $? -eq 0 ]; then
        reboot_required_functions+=("FileVault")
    fi
    
    echo "Configuring Gatekeeper..."
    check_gatekeeper
    
    echo "Securing user accounts..."
    check_accounts
    
    echo "Disabling remote access services..."
    check_access
    
    echo "Disabling sharing services..."
    check_sharing
    
    echo "Disabling AirDrop..."
    check_airdrop
    
    echo "Configuring wireless settings..."
    check_wireless
    
    echo "Applying additional hardening settings..."
    check_additional
    
    echo "Configuring system updates..."
    check_updates
    if [ $? -eq 0 ]; then
        reboot_required_functions+=("System Updates")
    fi
    
    # Final status report
    echo "=========================================================="
    echo "  🎉 MacOS Hardening Complete!"
    echo "=========================================================="
    
    # Check if a reboot is needed
    if [ ${#reboot_required_functions[@]} -gt 0 ]; then
        echo "The following changes require a system restart:"
        for func in "${reboot_required_functions[@]}"; do
            echo " - $func"
        done
        
        echo "Your system will restart in 60 seconds. Press Ctrl+C to cancel."
        echo "To apply all changes, please save your work before the restart."
        sleep 60
        
        # Reboot the system
        echo "Rebooting system now..."
        shutdown -r now
    else
        echo "All changes have been applied successfully. No reboot required."
        echo "However, a reboot is recommended to ensure all changes take effect."
    fi
}

# Run the main function
main
