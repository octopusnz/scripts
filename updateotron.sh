#!/usr/bin/env bash

# updateotron
# This script automates several update tasks.

set -o errexit
set -o nounset
set -o pipefail
shopt -s dotglob
shopt -s nullglob

# Here you can define your directories

git_dir="${HOME}/sources/compile/"
lock_file_dir="/tmp/"
rbenv_dir="${HOME}/.rbenv/"
ruby_build_dir="${HOME}/.rbenv/plugins/ruby-build/"
ruby_projects_dir="${HOME}/ruby/"

# Some arrays we will use later

all_dir=("${git_dir}" "${lock_file_dir}" "${rbenv_dir}" "${ruby_build_dir}"
"${ruby_projects_dir}")
git_test=("${git_dir}"*/)
git_array=()
ruby_test=("${ruby_projects_dir}"*/)
ruby_array=()

# Putting this here to trap it quickly

cleanup(){
  echo ""
  echo "5. Cleaning up and exiting."

  if [[ ! -f "${lock_file_dir}"/updateotron.lock ]]; then
    echo "[ERROR 4]: Lock file does not exist."
    exit 4
  else
    echo "[MSG]: Removing lock file."
    rm "${lock_file_dir}"/updateotron.lock
  fi

  echo "[MSG]: Unsetting variables".
  unset git_dir lock_file_dir rbenv_dir ruby_build_dir ruby_projects_dir
  unset all_dir git_test git_array ruby_test ruby_array many_dir ruby_dir
  unset ruby_folders BUNDLE_GEMFILE

  return 0
}

trap cleanup ERR EXIT SIGINT SIGTERM

# The following exit codes are specified.
# When adding new ones take into account:
# http://www.tldp.org/LDP/abs/html/exitcodes.html
#
# Exit 0 - Success.
# Exit 1 - Reserved for system.
# Exit 2 - Reserved for system.
# Exit 3 - Lock file exists.
#	The script creates a file called updateotron.lock and checks for its
# existence to prevent the script running multiple times.
# Exit 4 - Lock file does not exist.
# At the end of the script when running cleanup we check for the lock
#	file before running rm. Where did it go?

startup(){
  echo "Welcome to the update script."
  echo "Doing some setup."

  if [[ -f "${lock_file_dir}"/updateotron.lock ]]; then
    echo "[ERROR 3]: Lock file exists."
    exit 3
  fi

  echo "[MSG]: Creating lock file."
  touch "${lock_file_dir}"/updateotron.lock
  echo ""
  echo "1. Checking that directories exist."

  for dir in "${all_dir[@]}"; do
    if [[ ! -d "${dir}" ]]; then
      echo "[WARNING]: Directory ${dir} does not exist."
    else
      echo "${dir} OK"
    fi;
  done

  echo ""
  echo "2. Checking which source directories are git repositories."

  for many_dir in "${git_test[@]}"; do
    git -C "${many_dir}" rev-parse > /dev/null 2>&1 &&
    git_array+=("${many_dir}") && echo "${many_dir} ready"
  done

  echo ""
  echo "3. Checking for ruby projects that need a bundle."

  for ruby_dir in "${ruby_test[@]}"; do
    find "${ruby_dir}" -name "Gemfile.lock" > /dev/null 2>&1 &&
    ruby_array+=("${ruby_dir}") && echo "${ruby_dir} ready"
  done

  return 0
}

updates(){
  echo ""
  echo "4. Let's try some updates."

  echo "Updating rbenv"
  git -C "${rbenv_dir}" rev-parse > /dev/null 2>&1 &&
  git --git-dir=/"${rbenv_dir}"/.git/ pull

  echo "Updating ruby-build"
  git -C "${ruby_build_dir}" rev-parse > /dev/null 2>&1 &&
  git --git-dir=/"${ruby_build_dir}"/.git/ pull

  for dir_test in "${git_array[@]}"; do
    echo "Updating ${dir_test}"
    git --git-dir=/"${dir_test}"/.git/ pull
  done

  for ruby_folders in "${ruby_array[@]}"; do
    echo ""
    echo "Updating ${ruby_folders}" &&
    export BUNDLE_GEMFILE="${ruby_folders}"/Gemfile && bundle update
  done

  echo ""
  echo "Updating Rust and Cargo"
  rustup update

  echo ""
  echo "Updating Cabal packages"
  cabal update

  return 0
}

startup
updates

exit 0
