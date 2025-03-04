#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Configuration
SYNC_INTERVAL=1200  # Check every 20 minutes (1200 seconds)
GIST_DIR="$HOME/cursor-settings"
LOG_FILE="$GIST_DIR/sync.log"
LAST_HASH_FILE="$GIST_DIR/.last_hash"
SETTINGS_PATHS=()
OS_TYPE=""

# Detect OS and set appropriate paths
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    OS_TYPE="macOS"
    SETTINGS_PATHS=(
        "$HOME/Library/Application Support/Cursor/User/settings.json"
        "$HOME/Library/Application Support/Cursor/User/keybindings.json"
    )
    GIST_SETTINGS_PATHS=(
        "$GIST_DIR/settings.json"
        "$GIST_DIR/keybindings.json"
    )
    CURSOR_BIN="/Applications/Cursor.app/Contents/MacOS/Cursor"
else
    # Windows (when running in Git Bash or similar)
    OS_TYPE="Windows"
    SETTINGS_PATHS=(
        "$APPDATA/Cursor/User/@settings.json"
        "$APPDATA/Cursor/User/keybindings.json"
    )
    GIST_SETTINGS_PATHS=(
        "$GIST_DIR/settings.json"
        "$GIST_DIR/keybindings.json"
    )
    CURSOR_BIN="$LOCALAPPDATA/Programs/Cursor/Cursor.exe"
fi

# Function to log messages
log_message() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $1" >> "$LOG_FILE"
    echo "[$timestamp] $1"
}

# Function to check if Cursor is running
is_cursor_running() {
    if [[ "$OS_TYPE" == "macOS" ]]; then
        pgrep -q "Cursor"
        return $?
    else
        tasklist 2>NUL | findstr /I "Cursor.exe" >NUL
        return $?
    fi
}

# Function to get current git hash
get_current_hash() {
    (cd "$GIST_DIR" && git rev-parse HEAD)
}

# Function to check for local changes
check_local_changes() {
    local has_changes=false

    for i in "${!SETTINGS_PATHS[@]}"; do
        if ! cmp -s "${SETTINGS_PATHS[$i]}" "${GIST_SETTINGS_PATHS[$i]}"; then
            log_message "Changes detected in ${SETTINGS_PATHS[$i]}"
            has_changes=true
        fi
    done

    echo "$has_changes"
}

# Function to check for remote changes
check_remote_changes() {
    (cd "$GIST_DIR" && git fetch -q)

    local current_hash=$(get_current_hash)
    local remote_hash=$(cd "$GIST_DIR" && git rev-parse origin/master 2>/dev/null || git rev-parse origin/main 2>/dev/null)

    if [[ "$current_hash" != "$remote_hash" ]]; then
        return 0  # Changes detected
    else
        return 1  # No changes
    fi
}

# Function to handle merge conflicts
handle_conflicts() {
    if (cd "$GIST_DIR" && git status | grep -q "both modified"); then
        log_message "Merge conflicts detected!"
        show_notification "Cursor Settings Sync" "Merge conflicts detected. Manual resolution required."

        # Create backup of conflicted files
        mkdir -p "$GIST_DIR/conflicts_backup"
        cp "$GIST_DIR"/*_BACKUP_* "$GIST_DIR/conflicts_backup/" 2>/dev/null

        # Use local version by default
        (cd "$GIST_DIR" && git checkout --ours .)
        (cd "$GIST_DIR" && git add .)
        (cd "$GIST_DIR" && git commit -m "Auto-resolved conflicts by keeping local version")

        log_message "Conflicts auto-resolved by keeping local version. Backups in $GIST_DIR/conflicts_backup/"
    fi
}

# Function to sync extensions
sync_extensions() {
    if ! is_cursor_running; then
        log_message "Syncing extensions..."

        # Install missing extensions
        if [[ -f "$GIST_DIR/extensions.txt" ]]; then
            while IFS= read -r ext; do
                if ! "$CURSOR_BIN" --list-extensions | grep -q "$ext"; then
                    log_message "Installing extension: $ext"
                    "$CURSOR_BIN" --install-extension "$ext"
                fi
            done < "$GIST_DIR/extensions.txt"
        fi
    else
        log_message "Cursor is running. Skipping extension sync."
    fi
}

# Function to push changes
push_changes() {
    log_message "Pushing changes to remote..."

    # Copy current settings to gist directory
    for i in "${!SETTINGS_PATHS[@]}"; do
        cp "${SETTINGS_PATHS[$i]}" "${GIST_SETTINGS_PATHS[$i]}"
    done

    # Export extensions list if Cursor is not running
    if ! is_cursor_running; then
        if [[ -f "$CURSOR_BIN" ]]; then
            log_message "Exporting extensions list..."
            "$CURSOR_BIN" --list-extensions > "$GIST_DIR/extensions.txt" 2>/dev/null
        fi
    fi

    # Commit and push changes
    (cd "$GIST_DIR" && \
     git add . && \
     git commit -m "Auto-sync: Updated settings on $OS_TYPE at $(date)" && \
     git push)

    if [ $? -eq 0 ]; then
        log_message "Successfully pushed changes"
        echo "$(get_current_hash)" > "$LAST_HASH_FILE"
        return 0
    else
        log_message "Failed to push changes"
        return 1
    fi
}

# Function to pull changes
pull_changes() {
    log_message "Pulling changes from remote..."

    (cd "$GIST_DIR" && git pull)
    pull_result=$?

    # Handle any merge conflicts
    handle_conflicts

    if [ $pull_result -eq 0 ]; then
        log_message "Successfully pulled changes"
        echo "$(get_current_hash)" > "$LAST_HASH_FILE"

        # Sync extensions after successful pull
        sync_extensions

        return 0
    else
        log_message "Failed to pull changes"
        return 1
    fi
}

# Function to show desktop notification
show_notification() {
    local title="$1"
    local message="$2"

    if [[ "$OS_TYPE" == "macOS" ]]; then
        osascript -e "display notification \"$message\" with title \"$title\""
    else
        # For Windows, we'll use PowerShell
        powershell -command "New-BurntToastNotification -Text '$title', '$message'" 2>/dev/null || \
        powershell -command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); [System.Windows.Forms.MessageBox]::Show('$message', '$title')" 2>/dev/null
    fi
}

# Function to prompt user for action
prompt_user() {
    local action="$1"
    local response

    if [[ "$action" == "push" ]]; then
        show_notification "Cursor Settings Sync" "Local changes detected. Sync to GitHub?"

        # Use AppleScript dialog on macOS, PowerShell on Windows
        if [[ "$OS_TYPE" == "macOS" ]]; then
            response=$(osascript -e 'display dialog "Local Cursor settings have changed. Push to GitHub?" buttons {"Cancel", "Push"} default button "Push"' -e 'set response to button returned of result' 2>/dev/null)

            if [[ "$response" == "Push" ]]; then
                push_changes
            else
                log_message "User declined to push changes"
            fi
        else
            # For Windows
            powershell -command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); \$result = [System.Windows.Forms.MessageBox]::Show('Local Cursor settings have changed. Push to GitHub?', 'Cursor Settings Sync', 'YesNo', 'Question'); if(\$result -eq 'Yes') { exit 0 } else { exit 1 }" 2>/dev/null

            if [ $? -eq 0 ]; then
                push_changes
            else
                log_message "User declined to push changes"
            fi
        fi
    elif [[ "$action" == "pull" ]]; then
        show_notification "Cursor Settings Sync" "Remote changes detected. Update local settings?"

        if [[ "$OS_TYPE" == "macOS" ]]; then
            response=$(osascript -e 'display dialog "Remote Cursor settings have changed. Pull from GitHub?" buttons {"Cancel", "Pull"} default button "Pull"' -e 'set response to button returned of result' 2>/dev/null)

            if [[ "$response" == "Pull" ]]; then
                pull_changes
            else
                log_message "User declined to pull changes"
            fi
        else
            # For Windows
            powershell -command "[System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); \$result = [System.Windows.Forms.MessageBox]::Show('Remote Cursor settings have changed. Pull from GitHub?', 'Cursor Settings Sync', 'YesNo', 'Question'); if(\$result -eq 'Yes') { exit 0 } else { exit 1 }" 2>/dev/null

            if [ $? -eq 0 ]; then
                pull_changes
            else
                log_message "User declined to pull changes"
            fi
        fi
    fi
}

# Function for initial setup
initial_setup() {
    log_message "Performing initial setup..."

    # Check if symlinks are properly set up
    for i in "${!SETTINGS_PATHS[@]}"; do
        if [ -f "${SETTINGS_PATHS[$i]}" ] && [ ! -L "${SETTINGS_PATHS[$i]}" ]; then
            log_message "Setting up symlink for ${SETTINGS_PATHS[$i]}"

            # Backup original file
            cp "${SETTINGS_PATHS[$i]}" "${SETTINGS_PATHS[$i]}.backup"

            # Copy to gist directory
            mkdir -p "$(dirname "${GIST_SETTINGS_PATHS[$i]}")"
            cp "${SETTINGS_PATHS[$i]}" "${GIST_SETTINGS_PATHS[$i]}"

            # Create symlink
            rm "${SETTINGS_PATHS[$i]}"
            ln -s "${GIST_SETTINGS_PATHS[$i]}" "${SETTINGS_PATHS[$i]}"

            log_message "Created symlink: ${SETTINGS_PATHS[$i]} -> ${GIST_SETTINGS_PATHS[$i]}"
        fi
    done

    # Export initial extensions list
    if ! is_cursor_running && [ -f "$CURSOR_BIN" ]; then
        log_message "Exporting initial extensions list..."
        "$CURSOR_BIN" --list-extensions > "$GIST_DIR/extensions.txt" 2>/dev/null
    fi

    # Initial commit if needed
    if [ -z "$(cd "$GIST_DIR" && git status --porcelain)" ]; then
        log_message "No changes to commit in initial setup"
    else
        log_message "Committing initial setup..."
        (cd "$GIST_DIR" && \
         git add . && \
         git commit -m "Initial setup on $OS_TYPE at $(date)" && \
         git push)
    fi
}

# Initialize
mkdir -p "$GIST_DIR"
touch "$LOG_FILE"

# Store initial hash if not exists
if [ ! -f "$LAST_HASH_FILE" ]; then
    echo "$(get_current_hash)" > "$LAST_HASH_FILE"
fi

log_message "Starting Cursor settings sync service on $OS_TYPE"
log_message "Monitoring: ${SETTINGS_PATHS[*]}"
log_message "Gist directory: $GIST_DIR"

# Perform initial setup
initial_setup

# Main loop
while true; do
    # Check for local changes
    local_changes=$(check_local_changes)

    if [[ "$local_changes" == "true" ]]; then
        prompt_user "push"
    fi

    # Check for remote changes
    if check_remote_changes; then
        prompt_user "pull"
    fi

    # Wait for next check
    sleep "$SYNC_INTERVAL"
done
