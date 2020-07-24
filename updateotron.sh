#!/usr/bin/env bash

# updateotron
# This script automates several update tasks.

# TODO
#
# Need to expand regex to include list of Ruby releases here:
# https://www.ruby-lang.org/en/downloads/releases/
# Namely add x.x.x-words style to regex. Will then need to update sanitize
# logic as well.
#
# Consider moving the sanitize funtion to part of the startup and
# so we remove ruby projects from the update array if there is a badly
# formatted .ruby-version file. If there is no file it should be safe(er)
# to use the default.
#
# Consider checking for commands and just marking them as inactive somehow
# so they're not run but proceeding with the rest of the script. Rather than
# erroring out if one command is missing/fails.

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
#
# Exit 3 - Lock file exists.
# We create a file called updateotron.lock in the $lock_file_dir variable
# directory and check for its existence to prevent the script running
# multiple times. We're not too precious about it on cleanup. If it doesn't
# exist we just warn and continue to exit.
#
# Exit 4 - Missing .ruby-version file
# We expect a .ruby-version file to be in the same directory that the
# script is executed from. This is used as a fallback if one of the ruby
# projects doesn't contain one, at least we have a version to use. If this
# file does not exist or itsn't valid and fails to be parsed we'll error out.
#
# Exit 5 - Missing commands or broken $PATH.
# We expect certain commands to exist else it is probably not worth the
# error handling and we just exit. Check out the commands_array variable
# at the top of the script to see which commands it expects. We print the
# $PATH in case it's a misconfigure there too.
#
# Exit 6 - Missing directories or maybe a typo in configuration.
# We expect the directories specified at the beginning of this file and in
# $all_dir() array to exist.
#
# Exit 7 - We call a function named sanitize() in two places.
# From the startup() function to check for a default .ruby-version file in
# the same folder that the script is being run from. And then again against
# each ruby project folder to see whether we need to export the version
# before bundle update is run. This function always expects 2 arguments. So
# we do a basic check for those arguments and error out if not found.

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

# This sanitize function is trying to parse the .ruby-version file and
# make sure we have a sane string to set. Part of the reason it's reading
# line-line is so we can use the BASH_REMATCH array to easily capture the
# first succesful string. It also avoids using grep, sed, awk etc.
# For example this prevents against a file containing two valid version
# numbers on different lines. i.e '1.0.0' and '2.0.0' risk becoming
# '1.0.02.0.0' if we just strip whitespace and non-digits plus '.s'.

sanitize(){

  if [[ "${#}" -ne 1 ]]; then
    echo "[ERROR 7]: We expected 1 argument to the sanitize() function."
    echo "But we got ${#} instead."
    exit 7
  fi

  rbv_reg="^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})(-([A-Za-z]{1,10}))?$"
  reg_matches=0

  # || [[ -n $rbv_line ]] prevents the last line from being ignored if it
  # doesn't end with a \n (since read returns a non-zero exit code when it
  # encounters EOF).

  while read -r rbv_line || [[ -n "$rbv_line" ]]; do

  # This looks a bit jank. Basically we're trying to convert to lower case
  # the contents of the BASH_REMATCH array then re-use it to strip
  # everything but digits, lower case letters, '.s' and '-'s.

    if [[ "${rbv_line}" =~ ${rbv_reg} ]]; then
      rbv_downcase="${BASH_REMATCH[0],,}" &&
        ruby_version="${rbv_downcase//[^0-9a-z\.\-]/}" &&
        ((reg_matches="${reg_matches}"+1)) &&
        echo "" &&
        echo "Setting Ruby version: ${ruby_version}" &&
        break
    fi
  done < "${1}"

  # If we didn't find any matches to the regex we check if the ruby_version
  # variable already exists (i.e a default version has been set). If so we
  # are OK, if not we need to error out as we won't have a version.

  if [[ "${reg_matches}" -lt 1 ]]; then

    if [[ -v ruby_version ]]; then
      echo "We couldn't parse ${1} and set a valid Ruby version."
      echo "Using default: ${ruby_version}"
    else
      echo "We couldn't parse ${1} and set a default Ruby version."
      echo "[ERROR 4]: No valid .ruby-version file found."
      exit 4
    fi
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
    sanitize "${PWD}"/.ruby-version
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
    echo "[ERROR 6]: The following dirs do not exist or path is broken:"
    echo "${err_dir_list[*]}"
    exit 6
  fi

  echo ""
  echo "3. Checking which source directories are git repositories."

  for many_dir in "${git_dir[@]}"/*; do
    git -C "${many_dir}" rev-parse > /dev/null 2>&1 &&
      git_array+=("${many_dir}") &&
      echo "${many_dir} ready"
  done

  echo ""
  echo "4. Checking for ruby projects that need a bundle."

  for ruby_dir in "${ruby_projects_dir[@]}"/*; do

    if [[ -f "${ruby_dir}"/Gemfile.lock ]]; then
      ruby_array+=("${ruby_dir}") &&
        echo "${ruby_dir} ready"
    fi
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
      sanitize "${rb_dir}"/.ruby-version
    else
      echo "Using default ruby version: ${ruby_version}"
    fi

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
