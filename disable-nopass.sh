#!/bin/bash
#
# Undo the SleepSwitch passwordless rule installed by enable-nopass.sh.
# After this, the app falls back to asking for your password again.
#
# Run:  sudo ./disable-nopass.sh
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo:  sudo ./disable-nopass.sh"
  exit 1
fi

DEST="/etc/sudoers.d/sleepswitch"
if [ -f "${DEST}" ]; then
  rm -f "${DEST}"
  echo "Removed ${DEST}. SleepSwitch will ask for your password again."
else
  echo "Nothing to remove (${DEST} not found)."
fi
