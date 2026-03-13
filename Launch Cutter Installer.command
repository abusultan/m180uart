#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="/Users/pulldozer/Documents/cutter uart/yousefcutterUart"
PYTHON_SCRIPT="$PROJECT_ROOT/scripts/mac_force_cutter_launcher.py"

cd "$PROJECT_ROOT"

clear
echo "Running cutter launcher installer..."
echo

python3 "$PYTHON_SCRIPT"
status=$?

echo
if [[ $status -eq 0 ]]; then
  echo "Finished successfully."
else
  echo "Finished with errors. Exit code: $status"
fi
echo
read "?Press Enter to close..."
