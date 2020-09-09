#!/usr/bin/env bash
#******************************************************************************#
#                             updateotron.sh                                   #
#                         written by Jacob Doherty                             #
#                               July 2020                                      #
#                                                                              #
#                           Requires Bash v4.3+                                #
#               See updateotron.txt for documentation and license              #
#                  Source: https://github.com/octopusnz/scripts                #
#                                                                              #
#                       Automates your update tasks.                           #
#******************************************************************************#

# TO-DO: [1]: Pretty dashboard
# TO-DO: [2]: Review rbv_reg regex
# TO-DO: [3]: Support for other ruby env managers (RVM)
# TO-DO: [4]: Go support
# TO-DO: [5]: Should default ruby version get derived from env and not file?

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

cleanup(){

  local exit_status

  # This needs to be first so it captures the exit status from the cmd
  # that triggered the trap.

  exit_status=""
  exit_status="${?}"

  # Unset trap to prevent loops or double calling the cleanup() function.

  trap '' ERR EXIT SIGHUP SIGINT SIGTERM

  printf "\n"
  printf "5. Cleaning up and exiting.\n"

  if ! rm "${lock_file_dir%/}${lock_file}"; then
    printf "[WARNING]: There was an error and we're not sure what happened.\n"
    printf "We tried to remove this file here: %s%s\n" "${lock_file_dir%/}" \
      "${lock_file}"
    printf "We'll continue to attempt to exit.\n"
  else
    printf "Removing lock file\n"
  fi

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
      "${2}" "${1}";

  set +o nounset

  if [[ -n "${BASH_LINENO[0]}" ]] && [[ -n "${FUNCNAME[1]}" ]]; then
    printf "We were in the %s() function at around line %s\n" \
      "${FUNCNAME[1]}" "${BASH_LINENO[0]}";
  fi

  set -o nounset

  exit 9

  return 0;
}

# This takes an argument (string from variable) and cleans it.
# We unset the output variable 'cleaned_var' as we check if it is empty before
# using.

input_clean(){

  local tmp_clean_1
  local tmp_clean_2

  tmp_clean_1=""
  tmp_clean_2=""
  cleaned_var=""

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

file_dir_check(){

  if [[ "${#}" -lt 1 ]]; then
    printf "[ERROR 7]: We expected at least 1 argument to the dir_checker()\n"
    printf "function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  local tests

  tests=""
  check_failure=0

  set +o nounset

  for tests in "${@}"; do

    if [[ -n "${tests}" ]]; then

      if [[ -d "${tests}" ]] || [[ -f "${tests}" ]]; then
        check_failure=0
      else
        check_failure=1
        break
      fi

    else
      check_failure=1
      break
    fi
  done

  set -o nounset

  return 0;
}

# This sanitize function is trying to parse the .ruby-version file and
# make sure we have a sane string to set. It gets called from within the
# startup() and update() functions and passed with two mandatory arguments.
# $1 is full path. $2 is either a 0 or 1. 0 indicates it's a call to attempt to
# set a default ruby version so must succeed or error out. 1 is a call that
# could fail and in that case we remove the ruby project from the update array.

sanitize(){

  if [[ "${#}" -ne 2 ]]; then
    printf "[ERROR 7]: We expected 2 arguments to the sanitize() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  local rbv_line
  local reg_matches
  local such_versions
  local tmp_ruby_version

  tmp_ruby_version=""
  such_versions=""
  rbv_line=""
  reg_matches=0


  # || [[ -n $rbv_line ]] prevents the last line from being ignored if it
  # doesn't end with a \n (since read returns a non-zero exit code when it
  # encounters EOF).

  set +o nounset

  while read -r -t 3 rbv_line || [[ -n "${rbv_line}" ]]; do

    if [[ "${rbv_line}" =~ ${rbv_reg} ]]; then
      input_clean "${BASH_REMATCH[0]}"

      if [[ -n "${cleaned_var}" ]]; then
        tmp_ruby_version="${cleaned_var}"
      else
        logic_error 'unset' 'cleaned_var'
      fi
      break
    fi
  done < "${1%/}${rbv_file}"

  set -o nounset

  # We compare and contrast with the available verisons rbenv knows about

  for such_versions in "${rbenv_versions[@]}"; do

    if [[ "${tmp_ruby_version}" == "${such_versions}" ]]; then

      case "${2}" in
        [0])
          def_ruby_version="${tmp_ruby_version}" &&
            reg_matches=1;
          printf "\n"
          printf "Setting default Ruby version: %s\n" "${def_ruby_version}"
          ;;
        [1])
          ruby_array+=(["${1}"]="${tmp_ruby_version}") &&
            reg_matches=1;
          ;;
        [*])
          logic_error "${2}" '2'
          ;;
      esac
      break
    fi
  done

  # If we didn't find any matches to the regex we check if we are trying to
  # set a default ruby version, using the file in the same dir the script is
  # executed from. If that fails we need to error out, otherwise we can just
  # remove that particular ruby project directory from the update array.

  if [[ "${reg_matches}" -eq 0 ]]; then
    printf "We couldn't parse %s%s.\n" "${1%/}" "${rbv_file}"

    case "${2}" in
      [0])
        printf "[ERROR 4]: No valid %s file found.\n" "${rbv_file}"
        exit 4
        ;;
      [1])
        printf "We'll remove it from the update list to be safe.\n"
        del_ruby_update+=("${1}")
        ;;
      [*])
        logic_error "${2}" '2'
        ;;
    esac

  elif [[ "${reg_matches}" -ne 1 ]]; then
    logic_error "${reg_matches}" 'reg_matches'
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

  case "${BASH_VERSINFO[0]:-0}" in

    [0-3])
        bash_err=1
        ;;
      [4])
        if [[ "${BASH_VERSINFO[1]:-0}" -lt 3 ]]; then
          bash_err=1
        fi
        ;;
  esac

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

  file_dir_check "${lock_file_dir%/}${lock_file}"

  if [[ "${check_failure}" -eq 0 ]]; then
    printf "[ERROR 3]: Lock file exists: %s%s\n" "${lock_file_dir%/}" \
      "${lock_file}";
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

  file_dir_check "${script_dir%/}${rbv_file}"

  if [[ "${check_failure}" -ne 0 ]]; then
      printf "[ERROR 4]: No %s file exists at %s%s\n" "${rbv_file}" \
       "${script_dir%/}" "${rbv_file}";
    exit 4
  fi

  printf "\n"
  printf "2. Checking that directories exist.\n"

  err_dir=0

  for dir_list in "${all_dir[@]}"; do
    file_dir_check "${dir_list}"

    if [[ "${check_failure}" -ne 0 ]]; then
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
    file_dir_check "${many_dir%/}${git_check}"

    if [[ "${check_failure}" -eq 0 ]]; then
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

  set +o nounset

   for poss_versions in "${rbenv_map[@]}"; do

    cleaned_var=""

    if [[ "${poss_versions}" =~ ${rbv_reg} ]]; then
      input_clean "${BASH_REMATCH[0]}"

      if [[ -n "${cleaned_var}" ]]; then
        rbenv_versions+=("${cleaned_var}");
      else
        logic_error 'unset' 'cleaned_var'
      fi
    fi
   done

  set -o nounset

  # If we couldn't get any sensible versions out of rbenv we'll error.

  if [[ "${#rbenv_versions[@]}" -lt 1 ]]; then
      printf "We couldn't get any valid Ruby versions from rbenv.\n"
      printf "Check the output of rbenv versions and the PATH.\n"
      exit 10
  fi

  # Try and set a default version to use
  printf "\n"
  printf "Attempting to set default Ruby version.\n"
  sanitize "${script_dir}" 0

  printf "\n"
  printf "4. Checking for ruby projects that need a bundle.\n"

  for ruby_dir_test in "${ruby_projects_dir[@]}"/*/; do
    file_dir_check "${ruby_dir_test%/}${gem_file}"

    if [[ "${check_failure}" -eq 0 ]]; then
    file_dir_check "${ruby_dir_test%/}${rbv_file}"

      if [[ "${check_failure}" -eq 0 ]]; then
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

  file_dir_check "${rbenv_dir%/}${git_check}"

  if [[ "${check_failure}" -eq 0 ]]; then
    git -C "${rbenv_dir}" rev-parse --git-dir > /dev/null 2>&1 &&
      printf "Updating rbenv\n" &&
      git -C "${rbenv_dir}" pull;
  fi

  file_dir_check "${ruby_build_dir%/}${git_check}"

  if [[ "${check_failure}" -eq 0 ]]; then
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
