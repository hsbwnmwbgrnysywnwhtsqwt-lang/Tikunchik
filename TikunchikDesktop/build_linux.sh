#!/bin/bash
set -e

echo "Installing system dependencies..."
echo "Run: sudo apt install xdotool xclip libenchant-2-dev"
echo ""

echo "Installing Python dependencies..."
pip3 install -r requirements.txt
pip3 install pyinstaller pyenchant

echo "Building tikunchik..."
pyinstaller --onefile --name tikunchik tikunchik.py

echo ""
echo "Done! Find tikunchik in dist/"
