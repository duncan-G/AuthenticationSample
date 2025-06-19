#!/bin/bash

#########################################
# Print Utilities Script
# Shared color variables and print functions
#########################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    local title="$1"
    echo -e "${WHITE}"
    echo "================================================="
    echo "   $title"
    echo "================================================="
    echo -e "${NC}"
}

# Export functions and variables so they can be used by other scripts
export RED GREEN YELLOW CYAN WHITE NC
export -f print_info print_success print_warning print_error print_header 