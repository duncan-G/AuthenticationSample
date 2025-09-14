#!/bin/bash

# ------------------------------------------------------------------------------
# Root Convenience Script: restart.sh
# ------------------------------------------------------------------------------
# Purpose:
#   This script is a simple entry point for restarting a microservice.
#   It delegates execution to the main script located at:
#     scripts/development/restart_microservice.sh
#
# Usage:
#   ./restart.sh [options]
#   (All arguments are passed through to the underlying script.)
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/scripts/development/restart_microservice.sh" "$@"
