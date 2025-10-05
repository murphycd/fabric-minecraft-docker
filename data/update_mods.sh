#!/bin/bash

# ==============================================================================
# Mod Downloader for Prism Launcher Index
#
# Use the Prism Launcher to create/update the .index subdirectory. This script
# will read .toml files from .index and download the corresponding mod files.
# ==============================================================================

sync_mods() {
    # --- Configuration ---
    # The script is located adjacent to the 'mods' directory.
    local SCRIPT_DIR
    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    
    local MODS_DIR="$SCRIPT_DIR/mods"
    local INDEX_DIR="$SCRIPT_DIR/mods/.index"
    
    # Map hash format names to the system commands used for checksums.
    declare -A HASH_COMMANDS=(
        ["sha512"]="sha512sum"
        ["sha256"]="sha256sum"
        ["sha1"]="sha1sum"
        ["md5"]="md5sum"
    )
    
    # --- Status Tracking ---
    # 0 = Success, 1 = Failure
    local SYNC_STATUS=0
    local OVERWRITE_MODIFIED_FILES="false"

    # --- Colors for output ---
    local COLOR_GREEN='\033[0;32m'
    local COLOR_RED='\033[0;31m'
    local COLOR_YELLOW='\033[0;33m'
    local COLOR_CYAN='\033[0;36m'
    local COLOR_RESET='\033[0m'

    # --- Main Logic ---

    # Check for dependencies
    if ! command -v curl &>/dev/null; then
        echo -e "${COLOR_RED}ERROR: Required command 'curl' is not installed. Please install it to continue.${COLOR_RESET}"
        return 1
    fi

    # Ensure the target mods directory exists
    mkdir -p "$MODS_DIR"

    if [[ ! -d "$INDEX_DIR" ]]; then
        echo -e "${COLOR_YELLOW}[INFO] Index directory not found. Assuming no mods are required.${COLOR_RESET}"
        return 0
    fi
    
    local toml_files
    mapfile -t toml_files < <(find "$INDEX_DIR" -maxdepth 1 -type f -name "*.toml" 2>/dev/null)

    if [[ ${#toml_files[@]} -eq 0 ]]; then
        echo -e "${COLOR_YELLOW}[INFO] Index directory is empty. Assuming no mods are required.${COLOR_RESET}"
        return 0
    fi

    echo -e "${COLOR_CYAN}Starting mod synchronization...${COLOR_RESET}"
    echo "  Index Source: $INDEX_DIR"
    echo "  Mod Target:   $MODS_DIR"
    echo "--------------------------------------------------"

    for toml_file in "${toml_files[@]}"; do
        # --- TOML Parsing ---
        local mod_name="" filename="" url="" expected_hash="" hash_format="" mode=""
        local cf_file_id=""
        local current_section="root"

        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
            if [[ -z "$line" || "$line" =~ ^# ]]; then continue; fi

            if [[ "$line" =~ ^\[(.+)\] ]]; then
                current_section="${BASH_REMATCH[1]}"; continue
            fi

            local key value
            key=$(echo "$line" | cut -d'=' -f1 | sed 's/[ \t]*$//')
            value=$(echo "$line" | cut -d'=' -f2- | sed -e 's/^[ \t]*//' -e "s/^['\"]//" -e "s/['\"]$//")

            case "$current_section" in
                "root")
                    if [[ "$key" == "name" ]]; then mod_name="$value"; fi
                    if [[ "$key" == "filename" ]]; then filename="$value"; fi
                    ;;
                "download")
                    if [[ "$key" == "url" ]]; then url="$value"; fi
                    if [[ "$key" == "hash" ]]; then expected_hash="$value"; fi
                    if [[ "$key" == "hash-format" ]]; then hash_format="$value"; fi
                    if [[ "$key" == "mode" ]]; then mode="$value"; fi
                    ;;
                "update.curseforge")
                    if [[ "$key" == "file-id" ]]; then cf_file_id=$(echo "$value" | tr -d ' '); fi
                    ;;
            esac
        done < "$toml_file"

        # --- TOML Validation ---
        if [[ -z "$mod_name" ]]; then mod_name="$filename"; fi
        if [[ -z "$filename" ]] || [[ -z "$expected_hash" ]] || [[ -z "$hash_format" ]]; then
            echo -e "${COLOR_YELLOW}[WARN]  Skipping invalid/incomplete .toml file: $(basename "$toml_file")${COLOR_RESET}"
            continue
        fi

        # --- Checksum Command Validation ---
        local checksum_cmd=${HASH_COMMANDS[$hash_format]}
        if [[ -z "$checksum_cmd" ]]; then
            echo -e "${COLOR_YELLOW}[WARN]  Unsupported hash format '$hash_format' for $mod_name. Skipping.${COLOR_RESET}"
            continue
        fi
        if ! command -v "$checksum_cmd" &> /dev/null; then
            echo -e "${COLOR_RED}[FATAL] Required hash utility '$checksum_cmd' not found. Please install 'coreutils'.${COLOR_RESET}"
            return 1
        fi

        # --- Download and Verification ---
        local target_file="$MODS_DIR/$filename"
        if [[ -f "$target_file" ]]; then
            local local_hash
            local_hash=$($checksum_cmd "$target_file" | awk '{print $1}')

            if [[ "$local_hash" == "$expected_hash" ]]; then
                # File is present and correct
                echo -e "${COLOR_GREEN}[OK]    $mod_name already up-to-date and verified.${COLOR_RESET}"
                continue
            else
                # File is present but modified
                echo -e "${COLOR_YELLOW}[WARN]  $mod_name has been modified.${COLOR_RESET}"
                if [[ "$OVERWRITE_MODIFIED_FILES" == "true" ]]; then
                    echo -e "${COLOR_CYAN}[INFO]  Overwriting modified file as per configuration.${COLOR_RESET}"
                else
                    echo -e "${COLOR_CYAN}[INFO]  Skipping download to preserve local changes.${COLOR_RESET}"
                    continue
                fi
            fi
        fi

        if [[ "$mode" == "metadata:curseforge" ]]; then
            if [[ -z "$cf_file_id" ]]; then
                echo -e "${COLOR_YELLOW}[WARN]  Missing 'file-id' for CurseForge mod $mod_name. Skipping.${COLOR_RESET}"
                continue
            fi
            # Construct the direct CurseForge URL
            local slug_one="${cf_file_id:0:4}"
            local slug_two="${cf_file_id: -3}"
            local slug_two_stripped; slug_two_stripped=$((10#$slug_two)) # Safely strip leading zeros
            
            url="https://mediafilez.forgecdn.net/files/${slug_one}/${slug_two_stripped}/${filename}"
            echo -e "${COLOR_CYAN}[INFO]  Constructed CurseForge URL for $mod_name${COLOR_RESET}"
        elif [[ -z "$url" ]]; then
            echo -e "${COLOR_YELLOW}[WARN]  No URL found for $mod_name (mode: '$mode'). Skipping.${COLOR_RESET}"
            continue
        fi

        echo -e "${COLOR_CYAN}[GET]   Downloading: $mod_name...${COLOR_RESET}"
        local temp_file; temp_file=$(mktemp)
        
        local http_status
        http_status=$(curl -L --max-redirs 5 --connect-timeout 10 --retry 3 --retry-delay 2 \
            -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8" \
            -H "Accept-Language: en-US,en;q=0.9" \
            -H "Connection: keep-alive" \
            -w "%{http_code}" -o "$temp_file" "$url")

        if [[ "$http_status" =~ ^2..$ ]]; then
            local downloaded_hash; downloaded_hash=$($checksum_cmd "$temp_file" | awk '{print $1}')
            if [[ "$downloaded_hash" == "$expected_hash" ]]; then
                echo -e "${COLOR_GREEN}[OK]    Download successful and verified.${COLOR_RESET}"
                mv "$temp_file" "$target_file"
            else
                echo -e "${COLOR_RED}[ERROR] Checksum failed after download for $mod_name! Deleting corrupt file.${COLOR_RESET}"
                rm "$temp_file"; SYNC_STATUS=1
            fi
        else
            echo -e "${COLOR_RED}[ERROR] Failed to download $mod_name (HTTP $http_status).${COLOR_RESET}"
            rm "$temp_file"; SYNC_STATUS=1
        fi
    done

    echo "--------------------------------------------------"
    if [[ "$SYNC_STATUS" -eq 0 ]]; then
        echo -e "${COLOR_GREEN}Synchronization complete. All mods are up-to-date.${COLOR_RESET}"
    else
        echo -e "${COLOR_RED}Synchronization finished with errors. Some mods may be missing.${COLOR_RESET}"
    fi
    return $SYNC_STATUS
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    sync_mods "$@"
    exit $?
fi
