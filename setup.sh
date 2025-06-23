#!/bin/bash

# ------------------------------------------------------------------------------
# Root Convenience Script: setup.sh
# ------------------------------------------------------------------------------
# Purpose:
#   This script is a simple entry point for setting up the development environment.
#   It delegates execution to the main script located at:
#     Scripts/development/setup.sh
#
# Usage:
#   ./setup.sh [options]
#   (All arguments are passed through to the underlying script.)
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/Scripts/development/setup.sh" "$@"
