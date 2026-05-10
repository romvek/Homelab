#!/bin/bash

# --- DEPENDENCY CHECK ---
install_dependencies() {
    export PATH=$PATH:/usr/games

    local missing_tools=()
    for tool in lolcat figlet bc; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [ ${#missing_tools[@]} -gt 0 ]; then
        sudo apt-get update -qq
        sudo apt-get install -y -qq "${missing_tools[@]}" > /dev/null 2>&1
    fi
}

install_dependencies

# Color Variables
GREEN='\e[1;32m'

# --- UI FUNCTIONS ---

print_static_header() {
clear
cat << "EOF" | lolcat

                                _
                   __      __  | |
  _ __ ___  _ __ __\ \    / /__| | __
 | '__/ _ \| '_ ` _ \ \  / / _ \ |/ /
 | | | (_) | | | | | \ \/ /  __/   <
 |_|  \___/|_| |_| |_|\  / \___|_|\_\
                     | \/  /\  | |
      _   _ _ __   __| |  /  \ | |_ ___ _ __
     | | | | '_ \ / _` | / /\ \| __/ _ \ '__|
     | |_| | |_) | (_| |/ ____ \ ||  __/ |
      \__,_| .__/ \__,_/_/    \_\__\___|_|
           | |
           |_|

EOF
echo "-----------------------------------------------------------------------" | lolcat
echo "                       SYSTEM MAINTENANCE MODE                         " | lolcat
echo "-----------------------------------------------------------------------" | lolcat
echo ""
}

progress_bar() {
    local duration=$1
    local label=$2
    local width=30

    echo -ne "[RUNNING] $label "

    for ((i=0; i<=width; i++)); do
        local per=$((i * 100 / width))
        local progress=$((i * width / width))
        local remaining=$((width - i))

        printf -v bar "%${progress}s"
        printf -v space "%${remaining}s"

        # Only the bar and percentage are wrapped in the GREEN variable
        echo -ne "\r[RUNNING] $label ${GREEN}[${bar// /#}${space// /-}] ${per}%${NC}"
        sleep "$(bc -l <<< "$duration/$width")"
    done
    # Replace the running line with a completed checkmark
    echo -ne "\r\e[K[  DONE   ] $label                                \n"
    sleep 1
}

# --- START OF UPDATE PROCESS ---

print_static_header

# Step 1: Update
progress_bar 2 "Refreshing Package Repositories"
sudo apt-get update -qq > /dev/null 2>&1

# Step 2: Upgrade
progress_bar 5 "Deploying System-Wide Upgrades"
sudo apt-get dist-upgrade -y -qq > /dev/null 2>&1

# Step 3: Clean
progress_bar 3 "Clearing Residual Data Buffers"
sudo apt-get autoremove -y -qq > /dev/null 2>&1
sudo apt-get autoclean -qq > /dev/null 2>&1

# Final Step
echo ""
echo "-----------------------------------------------------------------------" | lolcat
figlet "Job's Done!" | lolcat
echo "All optimization tasks completed successfully." | lolcat
echo ""
