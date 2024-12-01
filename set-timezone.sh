#!/bin/bash

# Set the timezone to Melbourne
TIMEZONE="Australia/Melbourne"

echo "Setting timezone to $TIMEZONE..."
sudo timedatectl set-timezone "$TIMEZONE"

# Enable and start systemd-timesyncd (if not already running)
echo "Ensuring systemd-timesyncd is active..."
sudo systemctl enable systemd-timesyncd --now

# Force time synchronisation
echo "Forcing time synchronisation from NTP..."
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd

# Verify the changes
echo "Timezone set to:"
timedatectl | grep "Time zone"

echo "Current system time:"
timedatectl | grep "Local time"
