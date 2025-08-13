#!/bin/bash

#########################################
# Prompt Utilities Script
# Shared functions for user interaction and input handling
#########################################

# Source shared utilities
UTILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UTILS_SCRIPT_DIR/print-utils.sh"

# Function to prompt user for input
prompt_user() {
    local prompt="${1:-Enter value}"
    local var_name="${2:-user_input}"
    local default_value="${3:-}"
    
    if [ -n "$default_value" ]; then
        read -p "$(echo -e ${WHITE}$prompt ${NC}[${default_value}]: )" input
        if [ -z "$input" ]; then
            input="$default_value"
        fi
    else
        read -p "$(echo -e ${WHITE}$prompt: ${NC})" input
        while [ -z "$input" ]; do
            print_warning "This field is required!"
            read -p "$(echo -e ${WHITE}$prompt: ${NC})" input
        done
    fi
    
    eval "$var_name='$input'"
}

# Function to prompt user for optional input (allows empty)
prompt_user_optional() {
    local prompt="${1:-Enter value (optional)}"
    local var_name="${2:-user_input}"
    local default_value="${3:-}"

    if [ -n "$default_value" ]; then
        read -p "$(echo -e ${WHITE}$prompt ${NC}[${default_value}]: )" input
        if [ -z "$input" ]; then
            input="$default_value"
        fi
    else
        read -p "$(echo -e ${WHITE}$prompt: ${NC})" input
        # Allow empty without repeated prompting
    fi

    eval "$var_name='$input'"
}

# Function to prompt for confirmation
prompt_confirmation() {
    local prompt="$1"
    local default_value="${2:-N}"
    
    read -p "$(echo -e ${YELLOW}$prompt ${NC}[$default_value]: )" confirm
    if [ -z "$confirm" ]; then
        confirm="$default_value"
    fi
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        return 0  # true
    else
        return 1  # false
    fi
}

# Function to prompt for required confirmation (like typing DELETE)
prompt_required_confirmation() {
    local prompt="$1"
    local required_value="$2"
    local description="$3"
    
    echo
    print_warning "$description"
    echo
    read -p "$(echo -e ${RED}$prompt: ${NC})" confirm
    if [[ "$confirm" != "$required_value" ]]; then
        print_info "Confirmation cancelled. You must type '$required_value' to confirm."
        return 1
    fi
    return 0
}

# Function to prompt for selection from a list
prompt_selection() {
    local prompt="$1"
    local var_name="$2"
    local options=("${@:3}")
    local num_options="${#options[@]}"
    
    echo
    print_info "$prompt"
    echo
    
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[i]}"
    done
    echo
    
    while true; do
        read -p "${WHITE}Enter your choice (1-${num_options}): ${NC}" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$num_options" ]; then
            eval "$var_name='${options[$((choice-1))]}'"
            return 0
        else
            print_warning "Please enter a number between 1 and $num_options"
        fi
    done
}

# Export functions so they can be used by other scripts
export -f prompt_user prompt_user_optional prompt_confirmation prompt_required_confirmation prompt_selection 