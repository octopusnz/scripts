#!/usr/bin/env bash

# updateotron
# This script automates several update tasks.

# TODO
#
# Consider moving the sanitize function to part of the startup and
# so we remove ruby projects from the update array if there is a badly
# formatted .ruby-version file. If there is no file it should be safe(er)
# to use the default.
#
# Keep working on rbv_reg regex in the sanitize() function.
#
# Try to get the downcase and param expansion in sanitize() function
# combined into one.
#
# Consider checking for the .ruby-version in the home dir and the same order
# that ruby itself checks for those files to determine default version.
# Maybe start with if one exists in same dir as script and go from there.
# Is this just duplicating what rbenv/ruby itself is doing tho?
#
# Do we need to eval rbenv ... ? What a time to be alive.
#

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
ruby_projects_dir="${HOME}/code/ruby"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

# Some arrays we will use later

all_dir=(

  "${git_dir}"
  "${lock_file_dir}"
  "${rbenv_dir}"
  "${ruby_build_dir}"
  "${ruby_projects_dir}"
  "${script_dir}"
)

mandatory_commands=(bundle gem git rbenv)
optional_commands=(cabal rustup)

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
# Exit 7 - We call a function sanitize() in three places.
# From the startup() function to check for a default .ruby-version file in
# the same folder that the script is being run from. And then again against
# each ruby project folder to see whether we need to export the version
# before bundle update is run. Finally we call it once more to make sure we
# have a resonable version set before trying to update RubyGems. sanitize()
# always expects 1 argument which is the full path (incl filename) to the
# .ruby-version file. If this isn't passed we error out.

# Putting this here to trap it quickly

cleanup(){

  # This needs to be first so it captures the exit status from the cmd
  # that triggered the trap.

  exit_status="${?}"

  # Unset trap to prevent loops or double calling the cleanup() function.

  trap '' ERR EXIT SIGHUP SIGINT SIGTERM

  printf "\n"
  printf "5. Cleaning up and exiting.\n"

  printf "[MSG]: Unsetting exported variables.\n"
  unset BUNDLE_GEMFILE
  unset RBENV_VERSION

  if [[ ! -f "${lock_file_dir}"/updateotron.lock ]]; then
    printf "[WARNING]: Lock file does not exist and was not deleted.\n"
    printf "We tried here: %s/updateotron.lock.\n" "${lock_file_dir}"
  else
    printf "[MSG]: Removing lock file.\n"
    rm "${lock_file_dir}"/updateotron.lock
  fi

  printf "\n"
  printf "Exit code is: %s\n" "${exit_status}"
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

  if [[ "${#}" -ne 2 ]]; then
    printf "[ERROR 7]: We expected 2 arguments to the sanitize() function.\n"
    printf "But we got %s instead.\n" "${#}"
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
        ((reg_matches="${reg_matches}"+1))
      printf "\n"
      printf "Setting Ruby version: %s\n" "${ruby_version}"
      break
    fi
  done < "${1}"

  # If we didn't find any matches to the regex we check if we are trying to
  # use the 'default' .ruby-version file in the same dir as the script.
  # The assumption is that that should always exist and be valid, providing
  # a standardish system ruby version. We get this by checking for the
  # second argument to the santize() function. If it's 0 this is a call
  # using the 'default' .ruby-version, and if 1 not.

  if [[ "${reg_matches}" -lt 1 ]]; then

    if [[ "${2}" -eq 0 ]]; then
      printf "We couldn't parse %s.\n" "${1}"
      printf "[ERROR 4]: No valid .ruby-version file found.\n"
      exit 4
    else
      printf "We couldn't parse %s.\n" "${1}"
      printf "Will try and get a default now.\n"
      sanitize "${script_dir}"/.ruby-version 0
    fi
  fi
}

startup(){

  printf "Welcome to the update script.\n"
  printf "Doing some setup.\n"

  if [[ -f "${lock_file_dir}"/updateotron.lock ]]; then
    printf "[ERROR 3]: Lock file exists: %s/updateotron.lock.\n" \
      "${lock_file_dir}"
    exit 3
  fi

  printf "[MSG]: Creating lock file."
  touch "${lock_file_dir}"/updateotron.lock

  if [[ ! -f "${script_dir}"/.ruby-version ]]; then
    printf "[ERROR 4]: No .ruby-version file exists at %s /.ruby-version\n"  "{script_dir}"
    exit 4
  else
    sanitize "${script_dir}"/.ruby-version 0
  fi

  printf "1. Checking if commonly used commands are OK.\n"

  err_cmd_count=0
  err_cmd_list=()

  for m_command_list in "${mandatory_commands[@]}"; do

    if ! command -v "${m_command_list}" > /dev/null 2>&1; then
      ((err_cmd_count="${err_cmd_count}"+1))
      err_cmd_list+=("${m_command_list}")
    else
      printf "Looks like %s is ready.\n" "${m_command_list}"
    fi
  done

  if [[ "${err_cmd_count}" -gt 0 ]]; then
    printf "[ERROR 5]: The following cmds do not exist or path is broken:\n"
    printf "%s\n" "${err_cmd_list[*]}"
    printf "\n"
    printf "The current PATH is:\n"
    printf "%s\n" "${PATH}"
    exit 5
  fi

  for o_command_list in "${optional_commands[@]}"; do

    if ! command -v "${o_command_list}" > /dev/null 2>&1; then
      err_cmd_list+=("${o_command_list}")
      printf "Couldn't find %s. We will skip it.\n" "${o_command_list}"
    else
      printf "Looks like %s is ready.\n" "${o_command_list}"
    fi
  done

  printf "\n"
  printf "2. Checking that directories exist.\n"

  err_dir_count=0

  for dir_list in "${all_dir[@]}"; do

    if [[ ! -d "${dir_list}" ]]; then
      ((err_dir_count="${err_dir_count}"+1))
      err_dir_list+=("${dir_list}")
    else
      printf "%s OK\n" "${dir_list}"
    fi
  done

  if [[ "${err_dir_count}" -gt 0 ]]; then
    printf "[ERROR 6]: The following dirs do not exist or path is broken:"
    printf "%s\n" "${err_dir_list[*]}"
    exit 6
  fi

  printf "\n"
  printf "3. Checking which source directories are git repositories.\n"

  for many_dir in "${git_dir[@]}"/*; do
    git -C "${many_dir}" rev-parse > /dev/null 2>&1 &&
      git_array+=("${many_dir}") && printf "%s ready\n" "${many_dir}"
  done

  printf "\n"
  printf "4. Checking for ruby projects that need a bundle.\n"

  for ruby_dir in "${ruby_projects_dir[@]}"/*; do

    if [[ -f "${ruby_dir}"/Gemfile.lock ]]; then
      ruby_array+=("${ruby_dir}") &&
        printf "%s ready\n" "${ruby_dir}"
    fi
  done
}

updates(){

  printf "\n"
  printf "5. Let us try some updates.\n"

  printf "Updating rbenv\n"
  git -C "${rbenv_dir}" rev-parse > /dev/null 2>&1 &&
    git -C "${rbenv_dir}" pull

  printf "Updating ruby-build\n"
  git -C "${ruby_build_dir}" rev-parse > /dev/null 2>&1 &&
    git -C "${ruby_build_dir}" pull

  for dir_test in "${git_array[@]}"; do
    printf "Updating %s\n" "${dir_test}"
    git -C "${dir_test}" pull
  done

  for rb_dir in "${ruby_array[@]}"; do

    if [[ -f "${rb_dir}"/.ruby-version ]]; then
      sanitize "${rb_dir}"/.ruby-version 1
    else
      printf "Using default Ruby version: %s\n" "${ruby_version}"
    fi

    printf "Updating %s\n" "${rb_dir}"
    export BUNDLE_GEMFILE="${rb_dir}"/Gemfile &&
      export RBENV_VERSION="${ruby_version}" &&
      bundle update
  done

  # Rust and Cabal are optional so we skip them if not found or not in
  # $PATH.

  if [[ "${err_cmd_list[*]}" =~ rustup ]]; then
    printf "\n"
    printf "Skipping Rust updates.\n"
  else
    printf "\n"
    printf "Updating Rust and Cargo.\n"
    rustup update
  fi

  if [[ "${err_cmd_list[*]}" =~ cabal ]]; then
    printf "\n"
    printf "Skipping Cabal updates.\n"
  else
    printf "\n"
    printf "Updating Cabal packages.\n"
    cabal update
  fi

  # We re-set the ruby version once more in case an earlier update to a ruby
  # project folder left us on a different version

  sanitize "${script_dir}"/.ruby-version 0
  printf "Updating Ruby Gems.\n"
  export RBENV_VERSION="${ruby_version}" &&
    gem update --system
}

startup
updates
exit 0
