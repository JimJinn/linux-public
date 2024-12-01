#!/bin/bash
echo "Version 0.1"

# Check if the user provided a device
if [ -z "$1" ]; then
    echo "Usage: $0 <device> (e.g., /dev/sdb1)"
    exit 1
fi

DEVICE="$1"

# Function to unmount the device
unmount_device() {
    echo "Attempting to unmount $DEVICE..."
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

# Execute the functions
unmount_device
force_fsck

echo "Operation completed for $DEVICE."
