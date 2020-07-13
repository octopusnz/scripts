#!/usr/bin/env bash
#
# updateotron
# This script automates several update tasks.

set -o errexit
set -o nounset
set -o pipefail
shopt -s dotglob
shopt -s nullglob

# Have to specify this in the script .bashrc not withstanding due to:
# 'If not running interactively, don't do anything' in there.

eval "$(rbenv init -)"

# Here you can define your directories

git_dir="${HOME}/sources/compile/"
lock_file_dir="/tmp/"
rbenv_dir="${HOME}/.rbenv/"
ruby_build_dir="${HOME}/.rbenv/plugins/ruby-build/"
ruby_projects_dir="${HOME}/ruby/"

# Some general arrays we will use later

all_dir=(
  "${git_dir}"
  "${lock_file_dir}"
  "${rbenv_dir}"
  "${ruby_build_dir}"
  "${ruby_projects_dir}"
)
command_array=(bundle cabal gem git rbenv rustup)
git_array=()
git_test=("${git_dir}"*/)
ruby_array=()
ruby_test=("${ruby_projects_dir}"*/)

# Error handling variables and arrays

err_cmd=0
err_cmd_list=()
err_dir=0
err_dir_list=()

# The following exit codes are specified.
# When adding new ones take into account:
# http://www.tldp.org/LDP/abs/html/exitcodes.html
#
# Exit 0 - Success.
# Exit 1 - Reserved for system.
# Exit 2 - Reserved for system.
# Exit 3 - Lock file exists.
#   We create a file called updateotron.lock in the lock_file_dir variable
#   and checks for its existence to prevent the script running multiple
#   times.
# Exit 4 - Missing .ruby-version file
#   We expect a .ruby-version file to in the same directory that it is
#   executed from. This is used as a fallback if one of the ruby projects
#   doesn't contain one, so at least we have a version to use.
# Exit 5 - Missing commands or broken $PATH.
#   We expect certain commands to exist else it is probably not worth the
#   error handling and we just exit. Check out the commands_array variable
#   at the top of the script to see which commands it expects.
#   We print the $PATH in case it's a misconfigure there too.
# Exit 6 - Missing directories or maybe a typo in configuration.
#   We expect the directories you've specified at the top and in all_dir()
#   to exist.

# Putting this here to trap it quickly

cleanup(){

  # Put this first so it captures the exit status from the previous cmd.

  exit_status="${?}"

  # Unset trap to prevent loops or double calling.

  trap '' EXIT SIGHUP SIGINT SIGTERM

  echo ""
  echo "5. Cleaning up and exiting."

  echo "[MSG]: Unsetting exported variables."
  unset BUNDLE_GEMFILE
  unset RBENV_VERSION

  if [[ ! -f "${lock_file_dir}"updateotron.lock ]]; then
    echo "[WARNING]: Lock file does not exist and was not deleted."
    echo "It should have been here: ${lock_file_dir}updateotron.lock."
  else
    echo "[MSG]: Removing lock file."
    rm "${lock_file_dir}"updateotron.lock
  fi

  echo ""
  echo "Exit code is: ${exit_status}"
}

trap cleanup EXIT SIGHUP SIGINT SIGTERM

startup(){
  echo "Welcome to the update script."
  echo "Doing some setup."

  if [[ -f "${lock_file_dir}"updateotron.lock ]]; then
    echo "[ERROR 3]: Lock file exists: ${lock_file_dir}updateotron.lock."
    exit 3
  fi

  echo "[MSG]: Creating lock file."
  touch "${lock_file_dir}"updateotron.lock

  if [[ ! -f "${PWD}"/.ruby-version ]]; then
    echo "[ERROR 4]: No .ruby-version file exists at ${PWD}/.ruby-version"
    exit 4
  fi

  echo "1. Checking if commonly used commands are OK."

  for such_commands in "${command_array[@]}"; do
    if  ! command -v "${such_commands}" > /dev/null 2>&1; then
      ((err_cmd="${err_cmd}"+1)) && err_cmd_list+=("${such_commands}")
    else
      echo "Looks like ${such_commands} is ready."
    fi
  done

  if [[ "${err_cmd}" -gt 0 ]]; then
    echo "[ERROR 5]: The following commands do not exist or path is broken."
    echo "${err_cmd_list[*]}"
    echo ""
    echo "The current PATH is:"
    echo "${PATH}"
    exit 5
  fi

  echo ""
  echo "2. Checking that directories exist."

  for dir in "${all_dir[@]}"; do
    if [[ ! -d "${dir}" ]]; then
      ((err_dir="${err_dir}"+1)) && err_dir_list+=("${dir}")
    else
      echo "${dir} OK"
    fi
  done

  if [[ "${err_dir}" -gt 0 ]]; then
    echo "[ERROR 6]: The following directories do not exist or path is broken."
    echo "${err_dir_list[*]}"
    exit 6
  fi

  echo ""
  echo "3. Checking which source directories are git repositories."

  for many_dir in "${git_test[@]}"; do
    git -C "${many_dir}" rev-parse > /dev/null 2>&1 &&
      git_array+=("${many_dir}") &&
      echo "${many_dir} ready"
  done

  echo ""
  echo "4. Checking for ruby projects that need a bundle."

  for ruby_dir in "${ruby_test[@]}"; do
    find "${ruby_dir}" -name "Gemfile.lock" > /dev/null 2>&1 &&
      ruby_array+=("${ruby_dir}") &&
      echo "${ruby_dir} ready"
  done
}

updates(){
  echo ""
  echo "5. Let us try some updates."

  echo "Updating rbenv"
  git -C "${rbenv_dir}" rev-parse > /dev/null 2>&1 &&
    git -C "${rbenv_dir}" pull

  echo "Updating ruby-build"
  git -C "${ruby_build_dir}" rev-parse > /dev/null 2>&1 &&
    git -C "${ruby_build_dir}" pull

  for dir_test in "${git_array[@]}"; do
    echo "Updating ${dir_test}"
    git -C "${dir_test}" pull
  done

  for ruby_folders in "${ruby_array[@]}"; do

    if [[ -f "${ruby_folders}"/.ruby-version ]]; then
      ruby_version="$(<"${ruby_folders}"/.ruby-version)"
    else
      ruby_version="$(<"${PWD}"/.ruby-version)"
    fi

    echo ""
    echo "Updating ${ruby_folders}" &&
      export BUNDLE_GEMFILE="${ruby_folders}"/Gemfile &&
      export RBENV_VERSION="${ruby_version}" &&
      bundle update
  done

  echo ""
  echo "Updating Rust and Cargo."
  rustup update

  echo ""
  echo "Updating Cabal packages."
  cabal update

  echo ""
  echo "Updating Ruby Gems"
  gem update --system
}

startup
updates
