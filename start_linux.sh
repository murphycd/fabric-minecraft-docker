#!/bin/bash

# ============================================================================
#                 Minecraft Server Startup Script
# ============================================================================
# This script prepares and launches a Fabric Minecraft server. It handles
# configuration, mod/datapack updates, and JAR downloads automatically.
# ============================================================================

set -e

# Change directory to the script's location to ensure paths are correct
cd "$(dirname "$0")"

# The server's operational files (mods, configs, worlds) are in a 'data' subdirectory.
DATA_DIR="./data"

# If the data directory doesn't exist, create it.
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

# ============================================================================
# Helper function to set a property in a file
# ============================================================================
set_property() {
    local key="$1"
    local value="$2"
    local file="$3"
    local escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')

    if ! grep -q "^\s*${key}=" "$file" 2>/dev/null; then
        # Key does not exist, append it.
        echo "${key}=${escaped_value}" >> "$file"
    else
        # Key exists, update it.
        sed -i "s/^\s*${key}=.*/${key}=${escaped_value}/" "$file"
    fi
}


# ============================================================================
# Configuration
# ============================================================================
JAR_NAME="fabric-server-mc.1.21.6-loader.0.17.2-launcher.1.1.0.jar"
JAVA_ARGS="-Xmx4G"
FABRIC_URL="https://meta.fabricmc.net/v2/versions/loader/1.21.6/0.17.2/1.1.0/server/jar"
synchronize_mods="true"
include_from_datapacks_folder="true"
datapacks_folder="datapacks"


# ============================================================================
# 1. Ensure server.properties exists and is configured
# ============================================================================
properties_file="server.properties"
if [[ ! -f "$properties_file" && -f "default-server.properties" ]]; then
    echo "server.properties not found. Copying from default-server.properties."
    cp default-server.properties "$properties_file"
elif [[ ! -f "$properties_file" ]]; then
    echo "WARNING: server.properties and default-server.properties not found. A new one will be generated."
    # Create the file so we can set properties in it
    touch "$properties_file"
fi

# Set the server port from the environment variable
# Defaults to 25565 if MC_PORT is not set.
set_property "server-port" "${MC_PORT:-25565}" "$properties_file"


# ============================================================================
# 2. Append Datapacks to server.properties
# ============================================================================
if [ -f "$properties_file" ]; then
    # Read the current value. Default to an empty string if not set.
    current_packs_value=""
    if grep -q "^\s*initial-enabled-packs=" "$properties_file"; then
        current_packs_value=$(grep "^\s*initial-enabled-packs=" "$properties_file" | cut -d'=' -f2-)
    fi

    # Start with the current value. We will append to this.
    appended_packs_value="$current_packs_value"

    if [[ "$include_from_datapacks_folder" == "true" && -d "$datapacks_folder" ]]; then
        for f in "$datapacks_folder"/*; do
            if [[ -f "$f" || -d "$f" ]]; then
                pack_name=$(basename "$f")
                pack_entry="file/$pack_name"

                # Check if the pack is already in the comma-separated list.
                # The comma-padding prevents partial matches (e.g., "pack" matching "superpack").
                if ! [[ ",$appended_packs_value," == *",$pack_entry,"* ]]; then
                    # Append the new pack if it's not found.
                    if [[ -z "$appended_packs_value" ]]; then
                        appended_packs_value="$pack_entry"
                    else
                        appended_packs_value="$appended_packs_value,$pack_entry"
                    fi
                fi
            fi
        done
    fi

    # Only write to the file if the final list is different from the original.
    if [[ "$appended_packs_value" != "$current_packs_value" ]]; then
        echo "Datapack configuration has changed. Updating server.properties..."
        set_property "initial-enabled-packs" "$appended_packs_value" "$properties_file"
        echo "Datapack configuration updated."
    else
        echo "Datapack configuration is already up to date."
    fi
    echo ""
fi


# ============================================================================
# 3. Synchronize Mods
# ============================================================================
MODS_UPDATE_SCRIPT="./update_mods.sh"

if [[ "$synchronize_mods" == "true" ]]; then
    echo "Synchronizing mods..."
    if [ -f "$MODS_UPDATE_SCRIPT" ]; then
        # Execute the update script directly from the current 'data' directory.
        "$MODS_UPDATE_SCRIPT"
        if [ $? -ne 0 ]; then
            echo "ERROR: Mod synchronization failed. Aborting server launch."
            exit 1
        fi
        echo "Mods are up to date."
    else
        echo "WARNING: Mod update script not found at '$MODS_UPDATE_SCRIPT'. Skipping mod update."
    fi
fi


# ============================================================================
# 4. Check for Server Jar
# ============================================================================
if [[ ! -f "$JAR_NAME" ]]; then
    echo "Server JAR not found. Downloading from Fabric..."
    curl -o "$JAR_NAME" -L "$FABRIC_URL"
fi


# ============================================================================
# 5. EULA Agreement
# ============================================================================
echo "Ensuring EULA is accepted..."
echo "eula=true" > eula.txt


# ============================================================================
# 6. Start Server
# ============================================================================
echo "Starting Minecraft server..."
echo "--------------------------------------------------"

# Execute the server in the foreground.
# The server will take over the console, allowing direct command input.
# Ctrl+C will be handled gracefully by the server process itself.
java $JAVA_ARGS -jar "$JAR_NAME" nogui

echo "--------------------------------------------------"
echo "Server process has stopped. Script finished."
