#!/bin/bash

echo "Version 0.1"

sudo apt remove --purge -y glances
sudo apt autoremove -y
sudo apt clean
pip3 uninstall glances
rm -rf ~/.config/glances

echo "things to check:" 
echo "   /usr/local/bin/glances"