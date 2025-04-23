#!/bin/bash

# macOS Security Hardening Script
# This script implements various security hardening measures for macOS
# Must be run as root

# Check if script is running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try 'sudo $0'"
    exit 1
fi

# Simple echo function for section headers (more compatible with direct curl execution)
print_section() {
    echo
    echo "==== $1 ===="
    echo
}

print_section "User Account Security"
# Disable Guest user
echo "Disabling Guest account..."
dscl . -delete /Users/Guest AuthenticationAuthority 2>/dev/null
defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool NO

# Disable root account
echo "Securing root account..."
dscl . delete /Users/root AuthenticationAuthority 2>/dev/null
dscl . -create /Users/root Password '*'
dscl . -create /Users/root UserShell /usr/bin/false

# Disable auto login
echo "Disabling auto login..."
defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null

print_section "Remote Access Security"
# Disable SSH
echo "Disabling SSH..."
systemsetup -setremotelogin off

# Disable Apple Remote Desktop
echo "Disabling Apple Remote Desktop..."
/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -stop

print_section "Screen Saver & Login Security"
# Require password immediately after screen saver begins
echo "Configuring screen saver password requirements..."
defaults -currentHost write com.apple.screensaver askForPassword -int 1
defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0

# Set screen saver to start after 5 minutes of idle time
echo "Setting screen saver timeout to 5 minutes..."
defaults -currentHost write com.apple.screensaver idleTime -int 300

# Show full name rather than username on login screen
echo "Configuring login window to show full name..."
defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true

# Disable SSH (again, for redundancy)
systemsetup -setremotelogin off

print_section "Firewall Configuration"
# Enable firewall
echo "Enabling and configuring firewall..."
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned off
/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsignedapp off
/usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

print_section "System Integrity Protection"
# Enable System Integrity Protection
echo "Enabling System Integrity Protection..."
csrutil enable

print_section "Application Security"
# Enable Gatekeeper
echo "Enabling Gatekeeper..."
spctl --master-enable

# Disable remote Apple events
echo "Disabling remote Apple events..."
systemsetup -setremoteappleevents off

# Disable Bonjour multicast advertisements
echo "Disabling Bonjour multicast advertisements..."
defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true

print_section "Software Update Configuration"
# Enable automatic security updates
echo "Configuring automatic software updates..."
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true

print_section "Terminal Security"
# Enable secure keyboard entry in Terminal
echo "Enabling secure keyboard entry in Terminal..."
defaults write -app Terminal SecureKeyboardEntry -bool true

# Configure Terminal to close on exit
echo "Configuring Terminal to close on exit..."
defaults write com.apple.Terminal shellExitAction -int 1

print_section "Desktop and Dock Security"
# Disable hot corners
echo "Disabling hot corners..."
defaults write com.apple.dock wvous-tl-corner -int 0
defaults write com.apple.dock wvous-tr-corner -int 0  
defaults write com.apple.dock wvous-bl-corner -int 0  
defaults write com.apple.dock wvous-br-corner -int 0

# Restart the Dock to apply changes
echo "Restarting Dock..."
killall Dock

print_section "History and Privacy"
# Disable command history
echo "Disabling command history..."
echo "HISTSIZE=0" >> ~/.bash_profile
echo "HISTFILESIZE=0" >> ~/.zshrc

print_section "Networking Security"
# Disable NAT
echo "Disabling NAT..."
defaults write /Library/Preferences/SystemConfiguration/com.apple.nat NAT -dict Enabled -int 0

# Disable Bluetooth
echo "Disabling Bluetooth..."
defaults -currentHost write com.apple.Bluetooth PrefKeyServicesEnabled -bool false

print_section "Service Disabling"
# Disable various services
echo "Disabling unnecessary services..."
# Disable Apple Directory Service
launchctl disable system/com.apple.ODSAgent 2>/dev/null
launchctl bootout system/com.apple.ODSAgent 2>/dev/null

# Disable SMB file sharing
launchctl disable system/com.apple.smbd 2>/dev/null
launchctl bootout system/com.apple.smbd 2>/dev/null

# Disable printer sharing
echo "Disabling printer sharing..."
cupsctl --no-share-printers

# Disable screen sharing
echo "Disabling screen sharing..."
launchctl disable system/com.apple.screensharing 2>/dev/null
launchctl bootout system/com.apple.screensharing 2>/dev/null

print_section "Additional Security Settings"
# Disable Bluetooth controller
echo "Disabling Bluetooth controller..."
defaults write /Library/Preferences/com.apple.Bluetooth ControllerPowerState -bool false 

# Show Bluetooth and WiFi in menu bar for easy monitoring
echo "Configuring control center visibility..."
defaults write com.apple.controlcenter "NSStatusItem Visible BlueTooth" -bool true 
defaults write com.apple.controlcenter "NSStatusItem Visible WiFi" -bool true 

# Disable AirDrop
echo "Disabling AirDrop..."
defaults write com.apple.NetworkBrowser DisableAirDrop -bool true 

# Disable wake on network access
echo "Disabling wake on network access..."
pmset -a womp 0 

print_section "Privacy Settings"
# Disable diagnostic data submission
echo "Disabling diagnostic data submission..."
defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmit -bool false
defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmitVersion -int 0

# Safari privacy settings
echo "Configuring Safari privacy settings..."
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true

# Disable mDNS advertisements (again, in a different way)
echo "Disabling mDNS advertisements (additional method)..."
defaults write /System/Library/LaunchDaemons/com.apple.mDNSResponder.plist ProgramArguments -array-add "-NoMulticastAdvertisements"

echo
echo "==== Security hardening complete ===="
echo "Note: Some settings may require a restart to take full effect."
echo "It's recommended to restart your Mac now."
