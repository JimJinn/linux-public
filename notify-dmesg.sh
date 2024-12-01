#!/bin/bash
# wget -O - https://raw.githubusercontent.com/JimJinn/Linux-public/refs/heads/main/notify-dmesg.sh | bash
echo "Version 0.1"

# Config file path
CONFIG_FILE="/etc/notificator/notificator.conf"

# Check if the config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

# Source the config file to read MQTT_SERVER_IP and NOTIFY_TOPIC
source "$CONFIG_FILE"

# Validate the configuration variables
if [[ -z "$MQTT_SERVER_IP" || -z "$NOTIFY_TOPIC" ]]; then
    echo "Error: MQTT_SERVER_IP or NOTIFY_TOPIC is not defined in $CONFIG_FILE."
    exit 1
fi

# File to track already sent errors
SENT_ERRORS_FILE="/tmp/sent_errors.log"

# Initialize the sent errors file if it doesn't exist
if [ ! -f "$SENT_ERRORS_FILE" ]; then
    touch "$SENT_ERRORS_FILE"
fi

# Extract unique errors from dmesg
sudo dmesg | grep -iE "error|fail|critical" | while read -r line; do
    # Check if the error has already been sent
    if ! grep -Fxq "$line" "$SENT_ERRORS_FILE"; then
        # Publish the error to the MQTT topic
        hostname=$(hostname)
        message="[$hostname] $line"
        mosquitto_pub -h "$MQTT_SERVER_IP" -t "$NOTIFY_TOPIC" -m "$message"
        
        # Log the error as sent
        echo "$line" >> "$SENT_ERRORS_FILE"
    fi
done
