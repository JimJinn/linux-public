#!/bin/bash
echo "Version 0.12"

# Check if the required parameters are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <device> <mountpoint>"
    echo "Example: $0 /dev/sdb1 /mnt/mydisk"
    exit 1
fi

DEVICE="$1"
MOUNTPOINT="$2"

# Function to unmount the device
unmount_device() {
    echo "Checking if $DEVICE is mounted..."
    if grep -qs '$DEVICE ' /proc/mounts;; then
        echo "$DEVICE is mounted. Attempting to unmount..."
        if sudo umount "$DEVICE"; then
            echo "$DEVICE successfully unmounted."
        else
            echo "Failed to unmount $DEVICE. Checking for processes using it..."
            lsof_output=$(sudo lsof | grep "$DEVICE")
            if [ -n "$lsof_output" ]; then
                echo "The following processes are using $DEVICE:"
                echo "$lsof_output"
                echo "Killing processes..."
                echo "$lsof_output" | awk '{print $2}' | xargs -r sudo kill -9
                echo "Retrying unmount..."
                if sudo umount "$DEVICE"; then
                    echo "$DEVICE successfully unmounted after killing processes."
                else
                    echo "Failed to unmount $DEVICE even after killing processes."
                    exit 1
                fi
            else
                echo "No processes are using $DEVICE, but unmount still failed."
                exit 1
            fi
        fi
    else
        echo "$DEVICE is not mounted."
    fi
}

# Function to perform a filesystem check
force_fsck() {
    echo "Forcing a filesystem check on $DEVICE..."
    if sudo fsck -f -y "$DEVICE"; then
        echo "Filesystem check completed successfully."
    else
        echo "Filesystem check encountered errors. Please check the logs."
        exit 1
    fi
}

# Function to mount the device to the specified mount point
mount_device() {
    echo "Checking if mount point $MOUNTPOINT exists..."
    if [ ! -d "$MOUNTPOINT" ]; then
        echo "Mount point $MOUNTPOINT does not exist. Creating it..."
        sudo mkdir -p "$MOUNTPOINT"
    else
        echo "Mount point $MOUNTPOINT already exists."
    fi

    echo "Attempting to mount $DEVICE to $MOUNTPOINT..."
    if sudo mount "$DEVICE" "$MOUNTPOINT"; then
        echo "$DEVICE successfully mounted at $MOUNTPOINT."
    else
        echo "Failed to mount $DEVICE."
        exit 1
    fi
}

# Execute the functions
unmount_device
force_fsck
mount_device

echo "Operation completed for $DEVICE and mounted at $MOUNTPOINT."
