#!/usr/bin/env bash

# updateotron
# This script automates several update tasks.

# TODO
#
# Keep working on rbv_reg regex in the sanitize() function.
#
# Refactor variable names to be consistent i.e ruby_dir, git_dir, git_array
#
# Check for implied variables i.e for xxxvar in such_array and manually set
# them at the start of the function to catch cases where no matches are
# found from top to bottom of checks.[? Maybe]
#
# Where we are checking for an argument to a function i.e eq - 0 explicitly
# write cases for other values if received (negative numbers or higher)
#
# Set some of the dirs to empty folders (ruby, git etc) to test edge cases
#
# Re-write exit code comments

set -o errexit
set -o nounset
set -o pipefail

# Check for Bash 4.2+. We set zero if BASH_VERSINFO does not exist due
# to really old bash versions not providing it by default.

bash_err=0

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  bash_err=1
elif [[ "${BASH_VERSINFO[0]:-0}" -eq 4 ]]; then

  if [[ "${BASH_VERSINFO[1]:-0}" -lt 2 ]]; then
      bash_err=1
  fi
fi

if [[ "${bash_err}" -eq 1  ]]; then
  printf "We target Bash version 4.2+ due to the use of associatve arrays.\n"
  printf "We also use 'declare -g' which may not be supported in < 4.2.\n"
  printf "Your current Bash version is: %s\n" "${BASH_VERSION}"
  exit 8
fi

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

# Varibles used throughout

gem_file='/Gemfile'
lock_file='/updateotron.lock'
rbv_file='/.ruby-version'
git_check='/.git'

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
# file does not exist or is not valid and fails to be parsed we'll error out.
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
#
# Exit 8 - Bash version is less than 4.2.
#
# Exit 9 - Logic errors in general.

# Putting this here to trap it quickly

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
  unset BUNDLE_GEMFILE
  unset RBENV_VERSION

  if [[ ! -f "${lock_file_dir}${lock_file}" ]]; then
    printf "[WARNING]: Lock file does not exist and was not deleted.\n"
    printf "We tried here: %s%s\n" "${lock_file_dir%/}" \
      "${lock_file}"
  else
    printf "[MSG]: Removing lock file.\n"
    rm "${lock_file_dir%/}${lock_file}"
  fi

  printf "\n"
  printf "Exit code is: %s\n" "${exit_status}"
}

trap cleanup ERR EXIT SIGHUP SIGINT SIGTERM

# This sanitize function is trying to parse the .ruby-version file and
# make sure we have a sane string to set. It gets called from within the
# startup() and update() functions and passed with two mandatory arguments.
# $1 is full path including filename. $2 is either a 0 or 1. 0 indicates
# it's a call to attempt to set a default ruby version so must succeed or
# error out. 1 is a call that could fail and fall back to a default version.

sanitize(){

  local rbv_downcase
  local rbv_line
  local rbv_reg
  local reg_matches

  if [[ "${#}" -ne 2 ]]; then
    printf "[ERROR 7]: We expected 2 arguments to the sanitize() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  reg_matches=0
  rbv_reg="^([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})(-([A-Za-z0-9]{1,10}))?$"

  # || [[ -n $rbv_line ]] prevents the last line from being ignored if it
  # doesn't end with a \n (since read returns a non-zero exit code when it
  # encounters EOF).

  while read -r rbv_line || [[ -n "${rbv_line}" ]]; do

  # This looks a bit jank but it avoids external applications like grep,
  # sed, awk etc.

    if [[ "${rbv_line}" =~ ${rbv_reg} ]]; then
      reg_matches=1

      if [[ "${2}" -lt 2 ]]; then
        rbv_downcase="${BASH_REMATCH[0],,}"

        if [[ "${2}" -eq 1 ]]; then
          ruby_version="${rbv_downcase//[^0-9a-z\.\-]/}" &&
          ruby_array+=(["${1}"]="${ruby_version}")
        elif [[ "${2}" -eq 0 ]]; then
          def_ruby_version="${rbv_downcase//[^0-9a-z\.\-]/}"
          printf "\n"
          printf "Setting default Ruby version: %s\n" "${def_ruby_version}"
        fi
      fi
      break
    fi
  done < "${1%/}${rbv_file}"

  # If we didn't find any matches to the regex we check if we are trying to
  # use the 'default' .ruby-version file in the same dir as the script.
  # The assumption is that file should always exist and be valid, providing
  # a standardish system ruby version. We get this by checking for the
  # second argument to the santize() function. If it's 0 this is a call
  # using the 'default' .ruby-version and so if fails will error out.

  if [[ "${reg_matches}" -eq 0 ]]; then

    if [[ "${2}" -eq 0 ]]; then
      printf "We couldn't parse %s%s.\n" "${1%/}" "${rbv_file}"
      printf "[ERROR 4]: No valid %s file found.\n" "${rbv_file}"
      exit 4
    elif [[ "${2}" -eq 1 ]]; then
      printf "We couldn't parse %s%s.\n" "${1%/}" "${rbv_file}"
      printf "We'll remove it from the update list to be safe.\n"
      del_ruby_update+=("${1}")
    else
      printf "We couldn't parse %s%s.\n" "${1%/}" "${rbv_file}"
      printf "We'll attempt to set a default Ruby version.\n"
      sanitize "${script_dir}" 0
    fi
  fi
}

startup(){

  local all_dir
  local command_list
  local dir_list
  local err_cmd
  local err_dir

  declare -A command_list
  declare -gA err_cmd_list

  all_dir=(

    "${git_dir}"
    "${lock_file_dir}"
    "${rbenv_dir}"
    "${ruby_build_dir}"
    "${ruby_projects_dir}"
    "${script_dir}"
  )

  command_list=(

    [bundle]=mandatory
    [cabal]=optional
    [gem]=mandatory
    [git]=mandatory
    [rbenv]=mandatory
    [rustup]=optional
  )

  printf "Welcome to the update script.\n"
  printf "Doing some setup.\n"

  if [[ -f "${lock_file_dir}${lock_file}" ]]; then
    printf "[ERROR 3]: Lock file exists: %s%s\n" "${lock_file_dir%/}" \
      "${lock_file}"
    exit 3
  fi

  printf "[MSG]: Creating lock file."
  touch "${lock_file_dir%/}${lock_file}"

  if [[ ! -f "${script_dir%/}${rbv_file}" ]]; then
    printf "[ERROR 4]: No %s file exists at %s%s\n""${script_dir%/}" \
      "${rbv_file}"
    exit 4
  else
    sanitize "${script_dir}" 0
  fi

  printf "\n"
  printf "1. Checking if commonly used commands are OK.\n"

  err_cmd=0

  for cmd_test in "${!command_list[@]}"; do

    if ! command -v "${cmd_test}" > /dev/null 2>&1; then

      if [[ "${command_list["${cmd_test}"]}" == 'mandatory' ]]; then
        err_cmd_list+=(["${cmd_test}"]="${command_list["${cmd_test}"]}") &&
          err_cmd=1
      else
        err_cmd_list+=(["${cmd_test}"]="${command_list["${cmd_test}"]}")
        printf "Couldn't find %s. We will skip it.\n" "${cmd_test}"
      fi

    else
      printf "Looks like %s is ready.\n" "${cmd_test}"
    fi
  done

  if [[ "${err_cmd}" -eq 1 ]]; then
    printf "[ERROR 5]: The following cmds do not exist or path is broken:\n"
    printf "%s\n" "${!err_cmd_list[@]}"
    printf "\n"
    printf "The current PATH is:\n"
    printf "%s\n" "${PATH}"
    exit 5
  fi

  printf "\n"
  printf "2. Checking that directories exist.\n"

  err_dir=0

  for dir_list in "${all_dir[@]}"; do

    if [[ ! -d "${dir_list}" ]]; then
      err_dir_list+=("${dir_list}") &&
        err_dir=1
    else
      printf "%s OK\n" "${dir_list}"
    fi
  done

  if [[ "${err_dir}" -eq 1 ]]; then
    printf "[ERROR 6]: The following dirs do not exist or path is broken:"
    printf "%s\n" "${err_dir_list[@]}"
    exit 6
  fi

  printf "\n"
  printf "3. Checking which source directories are git repositories.\n"

  # Here we were using git -C rev-parse but trouble ensued if we tested
  # with no valid git dirs in the path. Typically we check for a .git dir
  # here and good enough.

  for many_dir in "${git_dir[@]}"/*/; do

    if [[ -d "${many_dir%/}${git_check}" ]]; then
      git_array+=("${many_dir}")
      printf "%s ready\n" "${many_dir}"
    fi
  done
}

ruby_curation(){

  local del_target
  local rb_i
  local ruby_dir_test

  declare -gA ruby_array

  printf "\n"
  printf "4. Checking for ruby projects that need a bundle.\n"

  for ruby_dir_test in "${ruby_projects_dir[@]}"/*/; do

    if [[ -f "${ruby_dir_test%/}${gem_file}" ]]; then

      if [[ -f "${ruby_dir_test%/}${rbv_file}" ]]; then
         printf "%s ready\n" "${ruby_dir_test}"
         sanitize "${ruby_dir_test}" 1
      else
        ruby_array+=(["${ruby_dir_test}"]="${def_ruby_version}")
         printf "%s ready\n" "${ruby_dir_test}"
      fi
    fi
  done

  for del_target in "${del_ruby_update[@]}"; do

    for rb_i in "${!ruby_array[@]}"; do

      if [[ "${rb_i}" == "${del_target}" ]]; then
        unset ruby_array["${rb_i}"]
        printf "%s removed.\n" "${rb_i}"
      fi
    done
  done
}

updates(){

  local err_value
  local git_dir_test
  local rust_err
  local cabal_err
  local update_dirs

  printf "\n"
  printf "5. Let us try some updates.\n"

  if [[ -d "${rbenv_dir}${git_check}" ]]; then
    printf "Updating rbenv\n"
    git -C "${rbenv_dir}" pull
  fi

  if [[ -d "${ruby_build_dir}${git_check}" ]]; then
    printf "Updating ruby-build\n"
    git -C "${ruby_build_dir}" pull
  fi

  for git_dir_test in "${git_array[@]}"; do
    printf "Updating %s\n" "${git_dir_test}"
    git -C "${git_dir_test}" pull
  done

  for update_dirs in "${!ruby_array[@]}"; do
    printf "Updating %s\n" "${update_dirs}"
    export BUNDLE_GEMFILE="${update_dirs%/}${gem_file}" &&
      export RBENV_VERSION="${ruby_array["${update_dirs}"]}" &&
      bundle update
  done

  # Rust and Cabal are optional so we skip them if not found or not in $PATH.

  rust_err=0
  cabal_err=0

  for err_value in "${!err_cmd_list[@]}"; do

    if [[ "${err_value}" == 'rustup' ]]; then
      rust_err=1
    elif [[ "${err_value}" == 'cabal' ]]; then
      cabal_err=1
    else
      printf "\n"
      printf "LOGIC ERROR: YOU SHOULDNT BE HERE. From update()"
    fi
  done

  if [[ "${rust_err}" -eq 1 ]]; then
    printf "\n"
    printf "Skipping Rust updates.\n"
  else
    printf "\n"
    printf "Updating Rust and Cargo.\n"
    rustup update
  fi

  if [[ "${cabal_err}" -eq 1 ]]; then
    printf "\n"
    printf "Skipping Cabal updates.\n"
  else
    printf "\n"
    printf "Updating Cabal packages.\n"
    cabal update
  fi

  # We re-set the ruby version once more in case an earlier update to a ruby
  # project folder left us on another version.

  printf "Updating Ruby Gems.\n"
  printf "Setting default Ruby version: %s\n" "${def_ruby_version}"
  export RBENV_VERSION="${def_ruby_version}" &&
    gem update --system
}

startup
ruby_curation
updates
exit 0
