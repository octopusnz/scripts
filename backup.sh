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
  stat
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
log_max_bytes=$(( 1024 * 1024 ))

# Safety net for sync: abort if a run would delete more remote files than
# this, e.g. if a directory went missing or an exclude was too broad.
# Override for a one-off run with BACKUP_MAX_DELETE=<n> (-1 for no limit).
max_delete="${BACKUP_MAX_DELETE:-500}"

# Set BACKUP_DELETE_EXCLUDED=1 for a one-off run that also removes files
# from B2 that match an exclude (e.g. build output uploaded before it was
# excluded). Combine with BACKUP_MAX_DELETE if the cleanup is large.
rclone_cleanup_opts=()
if [[ "${BACKUP_DELETE_EXCLUDED:-0}" == 1 ]]; then
  rclone_cleanup_opts=(--delete-excluded)
fi

log() {
  echo "$(date '+%F %T') $*"
}

# Keep one previous log once the current one exceeds log_max_bytes.
if [[ -f "${log_file}" ]] && (( $(stat -c '%s' "${log_file}") > log_max_bytes )); then
  mv -f "${log_file}" "${log_file}.1"
fi

# Always log to a file so unattended (cron/systemd) runs leave a record;
# also mirror to the terminal when run interactively. Live progress is only
# shown on a terminal; unattended runs log each transfer and periodic stats.
if [[ -t 1 ]]; then
  exec > >(tee -a "${log_file}") 2>&1
  rclone_output_opts=(--progress --stats 5s --stats-one-line)
else
  exec >> "${log_file}" 2>&1
  rclone_output_opts=(-v --stats 10m --stats-one-line)
fi

backup(){

  log "Starting backup process..."

  # sync mirrors deletions to B2. Deleted files are hidden on B2 rather than
  # removed, so retention of old versions is governed by the bucket's
  # lifecycle rules.
  nice -n 19 ionice -c3 rclone sync /home/ BackBlaze:Debian-Home/home/ \
    "${rclone_output_opts[@]}" \
    "${rclone_cleanup_opts[@]}" \
    --max-delete "${max_delete}" \
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
    --exclude jacobd/.dbus/ \
    --exclude jacobd/.Xauthority \
    --exclude jacobd/.ICEauthority \
    --exclude jacobd/.pki/ \
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
    --exclude "jacobd/backup.log*" \
    --exclude "jacobd/.vboxclient-*.pid" \
    --exclude "jacobd/.xsession-errors*" \
    --exclude jacobd/.sudo_as_admin_successful \
    --exclude jacobd/.wget-hsts \
    --exclude "jacobd/.bash_history-*.tmp" \
    --exclude "*.env" \
    --exclude jacobd/.claude/.credentials.json \
    --exclude jacobd/.claude/ide/ \
    --exclude "jacobd/.claude/sessions/*.key" \
    --exclude-if-present CACHEDIR.TAG \
    --exclude jacobd/code/c/purple/build/

  log "Backup process completed."

  return 0
}

# Acquire an exclusive, non-blocking lock on file descriptor 9. The lock is
# released automatically by the kernel when the process exits for any reason
# -- including SIGKILL, an OOM-kill, or a crash -- so it can never be stale.
#
# The lock file is removed on exit while the lock is still held. Because
# another instance may have opened the old file just before it was unlinked,
# after locking we confirm the file we hold is still the one at the path
# (same device:inode); if not, we reopen and try again.
while :; do
  exec 9>"${lock_file}"
  if ! flock -n 9; then
    echo "Another instance is running or lock already held: ${lock_file}" >&2
    exit 1
  fi
  if [[ "$(stat -L -c '%d:%i' /dev/fd/9)" == \
        "$(stat -c '%d:%i' "${lock_file}" 2>/dev/null)" ]]; then
    break
  fi
  exec 9>&-
done
on_exit() {
  local rc=$?
  rm -f "${lock_file}"
  if (( rc != 0 )); then
    log "Backup FAILED (exit ${rc})"
  fi
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
log "Lock acquired: ${lock_file}"

backup
