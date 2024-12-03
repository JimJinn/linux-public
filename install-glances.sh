#!/bin/bash

echo "Version 0.1"

# Define the service file path
SERVICE_FILE="/etc/systemd/system/glances.service"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root or with sudo."
    exit 1
fi

# Check if the service file already exists
if [ -f "$SERVICE_FILE" ]; then
    echo "Service file already exists: $SERVICE_FILE"
    echo "Skipping creation. Modify manually if needed."
else
    # Create the service file
    echo "Creating Glances service file..."
    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Glances
After=network.target

[Service]
ExecStart=/usr/local/bin/glances -w
Restart=on-abort
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    if [ $? -eq 0 ]; then
        echo "Service file created successfully: $SERVICE_FILE"
    else
        echo "Failed to create the service file."
        exit 1
    fi
fi

# Reload systemd daemon to recognise the new service
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable the service to start on boot
echo "Enabling Glances service..."
systemctl enable glances.service

# The respons should be Created symlink /etc/systemd/system/multi-user.target.wants/glances.service → /etc/systemd/system/glances.service.

if [ $? -eq 0 ]; then
    echo "Glances service enabled successfully."
else
    echo "Failed to enable the Glances service."
    exit 1
fi

sudo systemctl start glances.service

sleep 1

if sudo netstat -tuln | grep 61208 ; then
    echo "Glances is running"
else
    echo "Glances is NOT running or not listening on port $PORT."
    exit 1
fi

echo "Setup complete"
echo "Useful:"
echo "  sudo netstat -tuln | grep 61208"
echo "  sudo journalctl -u glances.service"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl restart glances.service"

