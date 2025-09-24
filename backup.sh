#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o physical

lock_file="${HOME}/backup.lock"

# Required environment variables
required_vars=(
  HOME
)

check_required_vars() {
  local v missing=0
  for v in "${required_vars[@]}"; do
    if [[ -z "${!v:-}" ]]; then
      echo "Error: Required variable '$v' is unset or empty" >&2
      missing=1
    fi
  done
  (( missing == 0 )) || return 1
}

# External commands your backup may need (extend this list as required)
required_cmds=(
  # rsync
  # tar
)

check_required_cmds() {
  local c missing=0
  for c in "${required_cmds[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      echo "Error: Required command '$c' not found in PATH" >&2
      missing=1
    fi
  done
  (( missing == 0 )) || return 1
}

backup(){

  echo "Starting backup process..."

  # Placeholder for actual backup commands
  # e.g., rsync, tar, etc.

  echo "Backup process completed."

  return 0
}

create_lock_file(){
  # Attempt atomic-ish lock using noclobber
  if ( set -o noclobber; : > "${lock_file}" ) 2>/dev/null; then
    echo "Lock acquired: ${lock_file}"
  else
    echo "Another instance is running or lock already exists: ${lock_file}" >&2
    exit 1
  fi
}

cleanup(){
  local exit_status=$?
  trap - ERR EXIT SIGHUP SIGINT SIGTERM
  if [[ -f "${lock_file}" ]]; then
    if rm -f -- "${lock_file}"; then
      echo "Lock file removed: ${lock_file}"
    else
      echo "Warning: failed to remove lock file: ${lock_file}" >&2
    fi
  fi
  exit "$exit_status"
}

trap cleanup ERR EXIT SIGHUP SIGINT SIGTERM

create_lock_file
check_required_vars || exit 1
check_required_cmds || exit 1

backup
