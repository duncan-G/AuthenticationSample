#!/bin/bash

# ------------------------------------------------------------------------------
# Root Convenience Script: install.sh
# ------------------------------------------------------------------------------
# Purpose:
#   This script is a simple entry point for installing dependencies for the
#   development environment. It delegates execution to the main script located at:
#     Scripts/development/install.sh
#
# Usage:
#   ./install.sh [options]
#   (All arguments are passed through to the underlying script.)
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/Scripts/development/install.sh" "$@"
