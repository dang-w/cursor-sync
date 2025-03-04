#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Function to display usage information
usage() {
    echo "Usage: $0 <gist_url>"
    echo "Example: $0 https://gist.github.com/yourusername/abcd1234efgh5678ijkl"
    echo ""
    echo "Note: This script assumes you have already created a GitHub Gist with your Cursor settings."
    echo "If you haven't created a Gist yet, please do so before running this script."
    exit 1
}

# Check if gist URL is provided
if [ $# -ne 1 ]; then
    usage
fi

GIST_URL="$1"

# Extract gist ID from URL
GIST_ID=$(echo "$GIST_URL" | grep -oE '[^/]+$')

if [ -z "$GIST_ID" ]; then
    echo "Error: Invalid Gist URL. Please provide a valid GitHub Gist URL."
    usage
fi

echo "Setting up Cursor Settings Sync..."

# Create cursor-settings directory
mkdir -p ~/cursor-settings

# Clone the gist
echo "Cloning Gist repository..."
git clone "$GIST_URL" ~/cursor-settings

if [ $? -ne 0 ]; then
    echo "Error: Failed to clone Gist repository. Please check the URL and your Git configuration."
    exit 1
fi

# Make the script executable
chmod +x "$SCRIPT_DIR/cursor-sync.sh"

# Create the .last_hash file with the current hash to prevent immediate sync prompts
echo "Creating initial hash file..."
(cd ~/cursor-settings && git rev-parse HEAD > .last_hash)

# Set up automatic startup based on OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "Setting up LaunchAgent for macOS..."

    # Copy the plist file
    cp "$SCRIPT_DIR/com.user.cursorsync.plist" ~/Library/LaunchAgents/

    # Update the path in the plist file
    sed -i '' "s|/path/to/cursor-sync.sh|$SCRIPT_DIR/cursor-sync.sh|g" ~/Library/LaunchAgents/com.user.cursorsync.plist

    # Load the LaunchAgent
    launchctl load ~/Library/LaunchAgents/com.user.cursorsync.plist

    echo "LaunchAgent installed. Cursor Settings Sync will start automatically on login."
else
    # Windows (when running in Git Bash)
    echo "For Windows, please follow these steps to set up automatic startup:"
    echo "1. Edit the cursor-sync-startup.bat file to update the paths:"
    echo "   $SCRIPT_DIR/cursor-sync-startup.bat"
    echo "2. Press Win+R, type 'shell:startup' and press Enter"
    echo "3. Copy the edited .bat file to the startup folder"

    # Update the startup batch file to include the skip-initial-checks flag
    sed -i "s|cursor-sync.sh|cursor-sync.sh --skip-initial-checks|g" "$SCRIPT_DIR/cursor-sync-startup.bat"
fi

# Run the script for initial setup with the skip-initial-checks flag
echo "Running initial setup..."
"$SCRIPT_DIR/cursor-sync.sh" --skip-initial-checks &

echo "Setup complete! Cursor Settings Sync is now running in the background."
echo "You can check the log file at ~/cursor-settings/sync.log"