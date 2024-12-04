#!/bin/bash

echo "Version 0.5"

# *** 
# This works, note the "smart" in the second line
#
# sudo apt-get install -y python3-pip python3-docker gcc lm-sensors wireless-tools
# sudo pip install setuptools glances[action,batinfo,browser,cpuinfo,docker,export,folders,gpu,graph,ip,raid,snmp,web,smart]
# sudo /usr/local/bin/glances --enable-plugin smart
# modified source from here: curl -L https://bit.ly/glances | /bin/bashgl  
# *** 

# Define the service file path
SERVICE_FILE="/etc/systemd/system/glances.service"

# doco
# smart https://glances.readthedocs.io/en/latest/aoa/smart.html

# API samples
# doco/swagger http://192.168.9.4:61208/docs#/
# http://192.168.9.4:61208/api/4/sensors
# http://192.168.9.4:61208/api/4/smart

# useful:
# glances -V --enable-plugin smart

# smartctl -i /dev/sda
# https://github.com/nicolargo/glances/issues/2525
# curl -q http://localhost:61208/api/3/smart

# sudo systemctl stop glances.service
# sudo rm /etc/systemd/system/glances.service
# sudo systemctl daemon-reload
# sudo systemctl list-units --type=service | grep glances
# sudo journalctl --vacuum-files=1 --unit=glances.service

# container https://github.com/nicolargo/glances/issues/2916

echo "Installing smartmontools"
if dpkg -l | grep -q "^ii  smartmontools"; then
    echo "smartmontools is already installed."
else
    echo "smartmontools is not installed. Installing now..."
    sudo apt update && sudo apt install -y smartmontools
    if [ $? -eq 0 ]; then
        echo "smartmontools installed successfully."
    else
        echo "Failed to install smartmontools. Exiting."
        exit 1
    fi
fi


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
ExecStart=sudo /usr/local/bin/glances -w --enable-plugin smart
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

# if sudo netstat -tuln | grep 61208 ; then
#     echo "Glances is running"
# else
#     echo "Glances is NOT running or not listening on port $PORT."
# fi

echo "Setup complete"
echo "Useful:"
echo "  sudo netstat -tuln | grep 61208"
echo "  sudo journalctl -u glances.service"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl restart glances.service"

