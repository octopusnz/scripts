#!/usr/bin/env bash

# updateotron
# This script automates several update tasks.

set -o errexit
set -o nounset
set -o pipefail

# Have to specify this in the script .bashrc not withstanding due to:
# 'If not running interactively, don't do anything' in there.

eval "$(rbenv init -)"

# Here we define our directories

git_dir="${HOME}/sources/compile"
lock_file_dir="/tmp"
rbenv_dir="${HOME}/.rbenv"
ruby_build_dir="${HOME}/.rbenv/plugins/ruby-build"
ruby_projects_dir="${HOME}/ruby"

# Some arrays we will use later

all_dir=(

  "${git_dir}"
  "${lock_file_dir}"
  "${rbenv_dir}"
  "${ruby_build_dir}"
  "${ruby_projects_dir}"
)

command_array=(

  bundle
  cabal
  gem
  git
  rbenv
  rustup
)

# The following exit codes are specified.
# When adding new ones take into account:
# http://www.tldp.org/LDP/abs/html/exitcodes.html
#
# Exit 0 - Success.
# Exit 1 - Reserved for system.
# Exit 2 - Reserved for system.

# Exit 3 - Lock file exists.
# We create a file called updateotron.lock in the $lock_file_dir variable
# directory and check for its existence to prevent the script running
# multiple times. We're not too precious about it on cleanup. If it doesn't
# exist we just warn and continue to exit.

# Exit 4 - Missing .ruby-version file
# We expect a .ruby-version file to be in the same directory that the
# script is executed from. This is used as a fallback if one of the ruby
# projects doesn't contain one, at least we have a version to use.

# Exit 5 - Missing commands or broken $PATH.
# We expect certain commands to exist else it is probably not worth the
# error handling and we just exit. Check out the commands_array variable
# at the top of the script to see which commands it expects. We print the
# $PATH in case it's a misconfigure there too.

# Exit 6 - Missing directories or maybe a typo in configuration.
# We expect the directories specified at the beginning of this file and in
# $all_dir() array to exist.

# Exit 7 - Error parsing and applying regex to a .ruby-version file.
# We check for a .ruby-version file in each of the ruby project dirs.
# It gets passed as a variable $ruby_version and used by Bundler to update
# each Ruby project. We do some basic regex sanitation on the file to try and
# prevent injecting some bad data into that environment variable.

# Putting this here to trap it quickly

cleanup(){

  # This needs to be first so it captures the exit status from the cmd
  # that triggered the trap.

  exit_status="${?}"

  # Unset trap to prevent loops or double calling the cleanup() function.

  trap '' ERR EXIT SIGHUP SIGINT SIGTERM

  echo ""
  echo "5. Cleaning up and exiting."

  echo "[MSG]: Unsetting exported variables."
  unset BUNDLE_GEMFILE
  unset RBENV_VERSION

  if [[ ! -f "${lock_file_dir}"/updateotron.lock ]]; then
    echo "[WARNING]: Lock file does not exist and was not deleted."
    echo "It should have been here: ${lock_file_dir}/updateotron.lock."
  else
    echo "[MSG]: Removing lock file."
    rm "${lock_file_dir}"/updateotron.lock
  fi

  echo ""
  echo "Exit code is: ${exit_status}"
}

trap cleanup ERR EXIT SIGHUP SIGINT SIGTERM

# TODO
#
# Need to expand regex to include list of Ruby releases here:
# https://www.ruby-lang.org/en/downloads/releases/
# Namely add x.x.x-words style to regex. Will then need to update sanitize
# logic as well.
#
# Have to continue to catch sanitize scenarios.
# An example issue is a .ruby-version file like so:
# 2.0.0
# 2.1.1
# This will currently smash the numbers together like:
# '2.0.02.1.1' and make that the ruby version.

sanitize(){

rb_reg="^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$"

if grep -Ex "${rb_reg}" "${1}/.ruby-version" > /dev/null 2>&1; then
  sanitize_tmp="$(<"${1}"/.ruby-version)" &&
    ruby_version="${sanitize_tmp//[^0-9\.]/}" &&
    echo "Setting Ruby Version: ${ruby_version}"
else
  echo "There was an error trying to sanitize a .ruby-version file"
  echo "The file was: ${1}/.ruby-version"
  exit 7
fi
}

startup(){

  echo "Welcome to the update script."
  echo "Doing some setup."

  if [[ -f "${lock_file_dir}"/updateotron.lock ]]; then
    echo "[ERROR 3]: Lock file exists: ${lock_file_dir}/updateotron.lock."
    exit 3
  fi

  echo "[MSG]: Creating lock file."
  touch "${lock_file_dir}"/updateotron.lock

  if [[ ! -f "${PWD}"/.ruby-version ]]; then
    echo "[ERROR 4]: No .ruby-version file exists at ${PWD}/.ruby-version"
    exit 4
  else
    sanitize "${PWD}"
  fi

  echo "1. Checking if commonly used commands are OK."

  err_cmd_count=0

  for command_list in "${command_array[@]}"; do
    if  ! command -v "${command_list}" > /dev/null 2>&1; then
      ((err_cmd_count="${err_cmd_count}"+1)) &&
        err_cmd_list+=("${command_list}")
    else
      echo "Looks like ${command_list} is ready."
    fi
  done

  if [[ "${err_cmd_count}" -gt 0 ]]; then
    echo "[ERROR 5]: The following commands do not exist or path is broken:"
    echo "${err_cmd_list[*]}"
    echo ""
    echo "The current PATH is:"
    echo "${PATH}"
    exit 5
  fi

  echo ""
  echo "2. Checking that directories exist."

  err_dir_count=0

  for dir_list in "${all_dir[@]}"; do
    if [[ ! -d "${dir_list}" ]]; then
      ((err_dir_count="${err_dir_count}"+1)) && err_dir_list+=("${dir_list}")
    else
      echo "${dir_list} OK"
    fi
  done

  if [[ "${err_dir_count}" -gt 0 ]]; then
    echo "[ERROR 6]: The following directories do not exist or path is broken:"
    echo "${err_dir_list[*]}"
    exit 6
  fi

  echo ""
  echo "3. Checking which source directories are git repositories."

  for many_dir in "${git_dir[@]}"/*/; do
    git -C "${many_dir}" rev-parse > /dev/null 2>&1 &&
      git_array+=("${many_dir}") &&
      echo "${many_dir} ready"
  done

  echo ""
  echo "4. Checking for ruby projects that need a bundle."

  for ruby_dir in "${ruby_projects_dir[@]}"/*/; do
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

  for rb_dir in "${ruby_array[@]}"; do

    if [[ -f "${rb_dir}"/.ruby-version ]]; then
      sanitize "${rb_dir}"
    else
      echo "Using default ruby version: ${ruby_version}"
    fi

    echo ""
    echo "Updating ${rb_dir}"
    export BUNDLE_GEMFILE="${rb_dir}"/Gemfile &&
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
