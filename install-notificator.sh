#!/bin/bash

# Path to the notify-dmesg.sh script
SCRIPT_PATH="$HOME/notify-dmesg.sh"

# Check if the script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: $SCRIPT_PATH does not exist."
    exit 1
fi

# Add the script to crontab to run every minute
(crontab -l 2>/dev/null; echo "* * * * * $SCRIPT_PATH") | crontab -

echo "notify-dmesg.sh has been added to crontab to run every minute."