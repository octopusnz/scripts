#!/usr/bin/env bash

# aggregate
# This script gives you a consolidated view of your C code.

set -o errexit
set -o nounset
set -o pipefail

file_ext="c"
include_string="#include <"
lock_file_dir="/tmp"
lock_file='/aggregate.lock'

cleanup(){

  local exit_status

  # This needs to be first so it captures the exit status from the cmd
  # that triggered the trap.

  exit_status="${?}"

  # Unset trap to prevent loops or double calling the cleanup() function.

  trap '' ERR EXIT SIGHUP SIGINT SIGTERM

  printf "\n"
  printf "5. Cleaning up and exiting.\n"

  printf "[MSG]: Unsetting exported variables.\n"

  if ! rm "${lock_file_dir%/}${lock_file}"; then
    printf "[WARNING]: There was an error and we're not sure what happened.\n"
    printf "We tried to remove this file here: %s%s\n" "${lock_file_dir%/}" \
      "${lock_file}"
    printf "We'll continue to attempt to exit.\n"
  fi

  printf "Exit code is: %s\n" "${exit_status}"

  return 0;
}

trap cleanup ERR EXIT SIGHUP SIGINT SIGTERM

hunt_for_c(){

  printf "[MSG]: Creating lock file.\n"
  printf "" >> "${lock_file_dir%/}${lock_file}"

  # TO_DO try an replicate the sed with bash!
  mapfile -t tmp_locations < <(cpp-10.2 -v -x c < /dev/null 2>&1 | \
    sed -nE 's/^ ([^ ]+)$/\1/p')

  # Even though cpp does this check for non-existent dirs, we'll do it again.
  # Because we trust no one.

  header_locations=()

  for such_locations in "${tmp_locations[@]}"; do

    if [[ -d "${such_locations}" ]]; then
      header_locations+=("${such_locations}")
    fi
  done

  # TO DO Check if header_locations is empty above

  #Let's find some files.
  mapfile -t my_codes < <(find . -type f -regex ".*\.${file_ext}")

  #Now let's get a list of header files
  mapfile -t grep_array < <(grep "${include_string}" "${my_codes[@]}")

  echo "${grep_array[@]}"



  return 0;
}

hunt_for_c
exit 0


