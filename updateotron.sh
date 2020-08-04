#!/usr/bin/env bash

# updateotron
# This script automates several update tasks.

# TODO
#
# Turn this into a dashboard
#
# Keep working on rbv_reg regex in the sanitize() function.
#
# Seperate out -d and -f -n check logic into a function
#
# Try and refactor the sanitize() function logic to be less nesty

set -o errexit
set -o nounset
set -o pipefail

# Here we define our directories

git_dir="${HOME}/sources/compile"
lock_file_dir="/tmp"
rbenv_dir="${HOME}/.rbenv"
ruby_build_dir="${HOME}/.rbenv/plugins/ruby-build"
ruby_projects_dir="${HOME}/code/ruby"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null 2>&1 && pwd)"

# Variables used throughout

gem_file='/Gemfile'
lock_file='/updateotron.lock'
rbv_file='/.ruby-version'
git_check='/.git'
rbv_reg="([0-9]{1,2})\.([0-9]{1,2})\.([0-9]{1,2})(-([A-Za-z0-9]{1,10}))?"

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
# projects doesn't contain one. If this file does not exist or is not valid
# and fails to be parsed we'll error out.
#
# Exit 5 - Missing commands or broken $PATH.
# We expect certain commands to exist else it is probably not worth the
# error handling and we just exit. Check out the commands_array in startup()
# to see which commands it expects. Command marked mandatory will error.
# We print the $PATH in case it's a misconfigure there too.
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
# Exit 8 - Bash version is less than 4.3. We use associative arrays, and also
# 'declare -g' which is probably unsupported earlier than 4.2 We picked 4.3
# minumum because we also use mapfile, which had bugs prior to 4.3. If for some
# reason this isn't bash it might return a version of 0.0. Double check you are
# running the script directly and not using 'sh scriptname' or something.
#
# Exit 9 - We have a general logic error. The error will hopefully capture
# the function and variable contents that caused it. Most commonly this is
# a variable set to an unexpected value, or something we can't parse.
#
# Exit 10 - We run the 'rbenv versions' command to check which versions are
# available. If this command doesn't work or returns nothing that matches our
# regex then we error out. Check if rbenv is on your path and whether it's
# being invoked correctly.


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
    printf "We tried here: %s%s\n" "${lock_file_dir%/}" "${lock_file}"
  else
    printf "[MSG]: Removing lock file.\n"
    rm "${lock_file_dir%/}${lock_file}"
  fi

  printf "\n"
  printf "Exit code is: %s\n" "${exit_status}"

  return 0;
}

trap cleanup ERR EXIT SIGHUP SIGINT SIGTERM

# We handle logic errors from throughout the script here. We expect two
# arguments when this gets called. 1 is the contents of the variable that
# triggered the error. 2 is the name of the variable. A number (i.e 1 or 2)
# indicates it's an argument to a function.

logic_error(){

  if [[ "${#}" -ne 2 ]]; then
    printf "[ERROR 7]: We expected 2 arguments to this function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  printf "We caught a logic error.\n"
  printf "Usually this is caused by a variable having an unexpected value.\n"
  printf "The variable in question is: %s and its value was: %s\n" \
      "${2}" "${1}"

  if [[ -n "${BASH_LINENO[0]}" ]] && [[ -n "${FUNCNAME[1]}" ]]; then
    printf "We were in the %s() function at around line %s\n" \
      "${FUNCNAME[1]}" "${BASH_LINENO[0]}"
  fi

  exit 9

  return 0;
}

# This takes an argument (string from variable) and cleans it.
# We unset the output variable 'cleaned_var' as we check if it is empty before
# using.

input_clean(){

  local tmp_clean_1
  local tmp_clean_2

  unset cleaned_var

  if [[ "${#}" -ne 1 ]]; then
    printf "[ERROR 7]: We expected 1 argument to the input_clean() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  tmp_clean_1="${1,,}" &&
    tmp_clean_2="${tmp_clean_1//[^0-9a-z\.\-]/}" &&
    cleaned_var="${tmp_clean_2}";

  return 0;
}

# This sanitize function is trying to parse the .ruby-version file and
# make sure we have a sane string to set. It gets called from within the
# startup() and update() functions and passed with two mandatory arguments.
# $1 is full path. $2 is either a 0 or 1. 0 indicates it's a call to attempt to
# set a default ruby version so must succeed or error out. 1 is a call that
# could fail and in that case we remove the ruby project from the update array.

sanitize(){

  local rbv_line
  local reg_matches
  local such_versions
  local tmp_ruby_version

  if [[ "${#}" -ne 2 ]]; then
    printf "[ERROR 7]: We expected 2 arguments to the sanitize() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  reg_matches=0

  # || [[ -n $rbv_line ]] prevents the last line from being ignored if it
  # doesn't end with a \n (since read returns a non-zero exit code when it
  # encounters EOF).

  while read -r -t 3 rbv_line || [[ -n "${rbv_line}" ]]; do

    # This looks a bit jank but it avoids external applications like grep,
    # sed and awk. Basically we lowercase any alpha characters and trim anything
    # we don't need.

    if [[ "${rbv_line}" =~ ${rbv_reg} ]]; then
      input_clean "${BASH_REMATCH[0]}"

      if [[ -n "${cleaned_var}" ]]; then
        tmp_ruby_version="${cleaned_var}"
      else
        logic_error 'unset' 'cleaned_var'
      fi

      # We compare and contrast with the avaliable verisons rbenv knows about

      for such_versions in ${rbenv_versions[*]}; do

        if [[ "${tmp_ruby_version}" == "${such_versions}" ]]; then

          if [[ "${2}" -eq 1 ]]; then
            ruby_array+=(["${1}"]="${tmp_ruby_version}") &&
              reg_matches=1;
            break
          elif [[ "${2}" -eq 0 ]]; then
            def_ruby_version="${tmp_ruby_version}" &&
              reg_matches=1;
            printf "\n"
            printf "Setting default Ruby version: %s\n" "${def_ruby_version}"
            break
          else
            logic_error "${2}" '2'
          fi
        fi
      done
      break
    fi
  done < "${1%/}${rbv_file}"

  # If we didn't find any matches to the regex we check if we are trying to
  # set a default ruby version, using the file in the same dir the script is
  # executed from. If that fails we need to error out, otherwise we can just
  # remove that particular ruby project directory from the update array.

  if [[ "${reg_matches}" -eq 0 ]]; then

     printf "We couldn't parse %s%s.\n" "${1%/}" "${rbv_file}"

    if [[ "${2}" -eq 0 ]]; then
      printf "[ERROR 4]: No valid %s file found.\n" "${rbv_file}"
      exit 4
    elif [[ "${2}" -eq 1 ]]; then
      printf "We'll remove it from the update list to be safe.\n"
      del_ruby_update+=("${1}")
    else
      logic_error "${2}" '2'
    fi
  fi

  return 0;
}

startup(){

  local all_dir
  local bash_err
  local cmd_test
  local command_list
  local dir_list
  local err_cmd
  local err_dir
  local many_dir

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

  # When adding commands to this list you can do it in the format of
  # [command name]=type. Type must be either optional or mandatory.
  # Mandatory commands that error will exit the script. Optional will be
  # manually checked later on in the update() function. You'll need to update
  # logic there too.

  command_list=(

    [bundle]=mandatory
    [cabal]=optional
    [gem]=mandatory
    [git]=mandatory
    [rbenv]=mandatory
    [rustup]=optional
  )

  # Check for Bash 4.3+. We set zero if BASH_VERSINFO does not exist due
  # to really old bash versions not providing it by default.

  bash_err=0

  if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    bash_err=1
  elif [[ "${BASH_VERSINFO[0]}" -eq 4 ]]; then

    if [[ "${BASH_VERSINFO[1]:-0}" -lt 3 ]]; then
      bash_err=1
    fi
  fi

  if [[ "${bash_err}" -eq 1 ]]; then
    printf "We target Bash version 4.3+ due to the use of associative arrays.\n"
    printf "There were some bugs in mapfile which were fixed in 4.3 too.\n"
    printf "Your current Bash version is: %s\n" "${BASH_VERSION}"
    exit 8
  elif [[ "${bash_err}" -ne 0 ]]; then
    logic_error "${bash_err}" 'bash_err'
  fi

  printf "Welcome to the update script.\n"
  printf "Doing some setup.\n"

  # We use -n here just to double check variable exists and is not empty to
  # prevent false-positive evaluation to true.

  if [[ -n "${lock_file_dir}" ]] && [[ -n "${lock_file}" ]] &&
      [[ -f "${lock_file_dir}${lock_file}" ]]; then
    printf "[ERROR 3]: Lock file exists: %s%s\n" "${lock_file_dir%/}" \
      "${lock_file}"
    exit 3
  fi

  printf "[MSG]: Creating lock file.\n"
  printf "" >> "${lock_file_dir%/}${lock_file}"

  printf "\n"
  printf "1. Checking if commonly used commands are OK.\n"

  err_cmd=0

  for cmd_test in "${!command_list[@]}"; do

    if ! command -v "${cmd_test}" > /dev/null 2>&1; then

      if [[ "${command_list["${cmd_test}"]}" == 'mandatory' ]]; then
        err_cmd_list+=(["${cmd_test}"]="${command_list["${cmd_test}"]}") &&
          err_cmd=1;
      elif [[ "${command_list["${cmd_test}"]}" == 'optional' ]]; then
        err_cmd_list+=(["${cmd_test}"]="${command_list["${cmd_test}"]}")
        printf "Couldn't find %s. We will skip it.\n" "${cmd_test}"
      else
        logic_error "${command_list["${cmd_test}"]}" 'command_list[cmd_test]'
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
  elif [[ "${err_cmd}" -ne 0 ]]; then
    logic_error "${err_cmd}" 'err_cmd'
  fi

  if [[ -n "${script_dir}" ]] && [[ -n "${rbv_file}" ]] &&
    [[ ! -f "${script_dir%/}${rbv_file}" ]]; then
      printf "[ERROR 4]: No %s file exists at %s%s\n""${script_dir%/}" \
        "${rbv_file}"
    exit 4
  fi

  printf "\n"
  printf "2. Checking that directories exist.\n"

  err_dir=0

  for dir_list in "${all_dir[@]}"; do

    if [[ ! -d "${dir_list}" ]]; then
        err_dir_list+=("${dir_list}") &&
          err_dir=1;
    else
      printf "%s OK\n" "${dir_list}"
    fi
  done

  if [[ "${err_dir}" -eq 1 ]]; then
    printf "[ERROR 6]: The following dirs do not exist or path is broken:"
    printf "%s\n" "${err_dir_list[@]}"
    exit 6
  elif [[ "${err_dir}" -ne 0 ]]; then
    logic_error "${err_dir}" 'err_dir'
  fi

  printf "\n"
  printf "3. Checking which source directories are git repositories.\n"

  # Here we do a basic check for a .git dir before invoking git rev-parse.
  # This is just in case we have many dirs to check that might chew up resources
  # checking each one with an external application.

  for many_dir in "${git_dir[@]}"/*/; do

    if [[ -n "${many_dir}" ]] && [[ -n "${git_check}" ]] &&
      [[ -d "${many_dir%/}${git_check}" ]]; then
        git -C "${many_dir}" rev-parse --git-dir > /dev/null 2>&1 &&
          git_array+=("${many_dir}") &&
          printf "%s ready\n" "${many_dir}";
    fi
  done

  return 0;
}

ruby_curation(){

  local del_target
  local poss_versions
  local rb_i
  local rbenv_map
  local ruby_dir_test

  declare -gA ruby_array

 # We get the list of versions current installed/available via rbenv.
 # We'll use this to check what's possible to set a version to later on.

  rbenv_versions=()

  mapfile -t rbenv_map < <(rbenv versions)

   for poss_versions in "${rbenv_map[@]}"; do

    if [[ "${poss_versions}" =~ ${rbv_reg} ]]; then
      input_clean "${BASH_REMATCH[0]}"

      if [[ -n "${cleaned_var}" ]]; then
        rbenv_versions+=("${cleaned_var}");
      else
        logic_error 'unset' 'cleaned_var'
      fi
    fi
  done

  # If we couldn't get any sensible versions out of rbenv we'll error.

  if [[ "${#rbenv_versions[@]}" -lt 1 ]]; then
      printf "We couldn't get any valid Ruby versions from rbenv.\n"
      printf "Check the output of rbenv versions and the PATH.\n"
      exit 10
  fi

  # Try and set a default version to use

  sanitize "${script_dir}" 0

  printf "\n"
  printf "4. Checking for ruby projects that need a bundle.\n"

  for ruby_dir_test in "${ruby_projects_dir[@]}"/*/; do

    if [[ -n "${ruby_dir_test}" ]] && [[ -n "${gem_file}" ]] &&
      [[ -f "${ruby_dir_test%/}${gem_file}" ]]; then

      if [[ -n "${ruby_dir_test}" ]] && [[ -n "${rbv_file}" ]] &&
        [[ -f "${ruby_dir_test%/}${rbv_file}" ]]; then
          printf "%s ready\n" "${ruby_dir_test}"
          sanitize "${ruby_dir_test}" 1
      else
        ruby_array+=(["${ruby_dir_test}"]="${def_ruby_version}")
         printf "%s ready\n" "${ruby_dir_test}"
      fi
    fi
  done

  # Remove the dir from the update array if it was marked for deletion by the
  # sanitize() function.

  for del_target in "${del_ruby_update[@]}"; do

    for rb_i in "${!ruby_array[@]}"; do

      if [[ "${rb_i}" == "${del_target}" ]]; then
          unset ruby_array["${rb_i}"] &&
          printf "%s removed.\n" "${rb_i}";
      fi
    done
  done

  return 0;
}

updates(){

  local cabal_err
  local err_value
  local git_updates
  local rust_err
  local update_params

  printf "\n"
  printf "5. Let us try some updates.\n"

  if [[ -n "${rbenv_dir}" ]] && [[ -n "${git_check}" ]] &&
    [[ -d "${rbenv_dir}${git_check}" ]]; then
      git -C "${rbenv_dir}" rev-parse --git-dir > /dev/null 2>&1 &&
        printf "Updating rbenv\n" &&
        git -C "${rbenv_dir}" pull;
  fi

  if [[ -n "${ruby_build_dir}" ]] && [[ -n "${git_check}" ]] &&
    [[ -d "${ruby_build_dir}${git_check}" ]]; then
      git -C "${ruby_build_dir}" rev-parse --git-dir > /dev/null 2>&1 &&
        printf "Updating ruby-build\n" &&
        git -C "${ruby_build_dir}" pull;
  fi

  for git_updates in "${git_array[@]}"; do
    printf "Updating %s\n" "${git_updates}"
    git -C "${git_updates}" pull
  done

  for update_params in "${!ruby_array[@]}"; do
    printf "Updating %s\n" "${update_params}"
    export BUNDLE_GEMFILE="${update_params%/}${gem_file}" &&
      export RBENV_VERSION="${ruby_array["${update_params}"]}" &&
      bundle update;
  done

  # Rust and Cabal are optional so we skip them if not found or not in $PATH.

  rust_err=0
  cabal_err=0

  # Could check these in each update attempt, but we wanted to only do the for
  # loop once. You need to update these with expected values if you add another
  # command to the command list in startup(). We are very explicit right here.

  for err_value in "${!err_cmd_list[@]}"; do

    if [[ "${err_value}" == 'rustup' ]]; then
      rust_err=1
    elif [[ "${err_value}" == 'cabal' ]]; then
      cabal_err=1
    else
      logic_error "${err_value}" 'err_value'
    fi
  done

  if [[ "${rust_err}" -eq 1 ]]; then
    printf "\n"
    printf "Skipping Rust updates.\n"
  elif [[ "${rust_err}" -ne 0 ]]; then
    logic_error "${rust_err}" rust_err
  else
    printf "\n"
    printf "Updating Rust and Cargo.\n"
    rustup update
  fi

  if [[ "${cabal_err}" -eq 1 ]]; then
    printf "\n"
    printf "Skipping Cabal updates.\n"
  elif [[ "${cabal_err}" -ne 0 ]]; then
    logic_error "${cabal_err}" 'cabal_err'
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
    gem update --system;

  return 0;
}

startup
ruby_curation
updates
exit 0
