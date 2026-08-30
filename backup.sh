#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o physical

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
  rclone
  nice
  ionice
  flock
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

check_required_vars || exit 1
check_required_cmds || exit 1

lock_file="${HOME}/backup.lock"
log_file="${HOME}/backup.log"

# Always log to a file so unattended (cron/systemd) runs leave a record;
# also mirror to the terminal when run interactively.
if [[ -t 1 ]]; then
  exec > >(tee -a "${log_file}") 2>&1
else
  exec >> "${log_file}" 2>&1
fi

backup(){

  echo "Starting backup process..."

  nice -n 19 ionice -c3 rclone copy /home/ BackBlaze:Debian-Home/home/ \
    --progress \
    --stats 5s \
    --stats-one-line \
    --fast-list \
    --transfers 2 \
    --buffer-size 8M \
    --b2-upload-cutoff 200M \
    --b2-chunk-size 96M \
    --skip-links \
    --exclude jacobd/sources/ \
    --exclude jacobd/cppcheck-donate-cpu-workfolder/ \
    --exclude jacobd/.cache/ \
    --exclude jacobd/.local/share/keyrings/ \
    --exclude jacobd/.dbus \
    --exclude jacobd/.Xauthority \
    --exclude jacobd/.mozilla/ \
    --exclude jacobd/.cargo/ \
    --exclude jacobd/.gnupg/ \
    --exclude jacobd/.ssh/ \
    --exclude jacobd/.git-credentials \
    --exclude jacobd/venvs/ \
    --exclude jacobd/.rustup/ \
    --exclude jacobd/.vscode/ \
    --exclude jacobd/.config/ \
    --exclude jacobd/backup.lock \
    --exclude jacobd/backup.log \
    --exclude "*.env" \
    --exclude jacobd/.claude/.credentials.json \
    --exclude jacobd/.claude/ide/ \
    --exclude "jacobd/.claude/sessions/*.key"

  echo "Backup process completed."

  return 0
}

# Acquire an exclusive, non-blocking lock on file descriptor 9. Unlike a
# noclobber marker file, this lock is released automatically by the kernel
# when the process exits for any reason -- including SIGKILL, an OOM-kill,
# or a crash -- so it can never be left stale. The lock file itself is not
# removed; it simply persists on disk as the lock target.
exec 9>"${lock_file}"
if ! flock -n 9; then
  echo "Another instance is running or lock already held: ${lock_file}" >&2
  exit 1
fi
echo "Lock acquired: ${lock_file}"

backup
