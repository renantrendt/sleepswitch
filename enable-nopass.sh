#!/bin/bash
#
# One-time setup for SleepSwitch.
#
# Installs a tightly-scoped passwordless sudoers rule so the app can toggle
# `pmset disablesleep` without asking for your password every time. The rule
# permits ONLY these two exact commands to run as root without a password:
#
#     /usr/bin/pmset -a disablesleep 0
#     /usr/bin/pmset -a disablesleep 1
#
# Nothing else. It is validated with `visudo` before install, so a syntax
# error can never lock you out of sudo.
#
# Run once:   sudo ./enable-nopass.sh
# Undo with:  sudo ./disable-nopass.sh
#
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo:  sudo ./enable-nopass.sh"
  exit 1
fi

USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -z "${USER_NAME}" ] || [ "${USER_NAME}" = "root" ]; then
  echo "Could not determine your (non-root) username; aborting."
  exit 1
fi

DEST="/etc/sudoers.d/sleepswitch"
RULE="${USER_NAME} ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT
printf '%s\n' "${RULE}" > "${TMP}"

# Validate the generated rule in isolation before touching the system.
if ! visudo -cf "${TMP}" >/dev/null 2>&1; then
  echo "Generated rule failed validation; aborting (no changes made)."
  exit 1
fi

install -m 0440 -o root -g wheel "${TMP}" "${DEST}"

# Full-config sanity check (covers /etc/sudoers + everything in sudoers.d).
if visudo -c >/dev/null 2>&1; then
  echo "Installed: ${DEST}"
  echo "  ${RULE}"
  echo
  echo "Done — SleepSwitch will now switch instantly, no password."
else
  echo "sudoers validation failed after install; rolling back."
  rm -f "${DEST}"
  exit 1
fi
