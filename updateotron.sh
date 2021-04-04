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

# Common errors to handle:
#
# Git:
#   remote: Repository not found.
#   fatal: repository '[repo name'] not found
#
# Ruby:
#   rbenv: version `3.0.0 (set by [/path/to/.ruby-version] )' is not installed
#   (set by RBENV_VERSION environment variable)
#
#   Warning: the running version of Bundler (2.1.4) is older than the version that
#   created the lockfile (2.2.3). We suggest you to upgrade to the version that
#   created the lockfile by running `gem install bundler:2.2.3`.
#
#   Your Ruby version is 2.5.5, but your Gemfile specified >= 2.6.0

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

  local exit_status=""

  # This needs to be first so it captures the exit status from the cmd
  # that triggered the trap.

  exit_status="${?}"

  # Unset trap to prevent loops or double calling the cleanup() function.

  trap '' ERR EXIT SIGHUP SIGINT SIGTERM

    if ! rm "${lock_file_dir%/}${lock_file}"; then
      if [[ "${debug}" == 1 ]]; then
        printf "[WARNING]: There was an error removing the lock file.\n"
        printf "We tried to remove this file: %s%s\n" "${lock_file_dir%/}" \
         "${lock_file}"
        printf "We'll continue to attempt to exit.\n"
      fi
    fi

  if [[ "${debug}" == 1 ]]; then
    printf "Exit code is: %s\n" "${exit_status}"
  fi

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

  local tmp_clean_1=""
  local tmp_clean_2=""

  declare -g cleaned_var=""

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

  if [[ "${#}" -ne 2 ]]; then
    printf "[ERROR 7]: We expected 2 arguments to the sanitize() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  local rbv_line=""
  local reg_matches=0
  local such_versions=""
  local tmp_ruby_version=""

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

  for such_versions in "${r_env_versions[@]}"; do

    if [[ "${tmp_ruby_version}" == "${such_versions}" ]]; then

      case "${2}" in
        0)
          def_ruby_version="${tmp_ruby_version}" &&
            reg_matches=1;
          printf "\n"
          printf "Setting default Ruby version: %s\n" "${def_ruby_version}"
          ;;
        1)
          ruby_array+=(["${1}"]="${tmp_ruby_version}") &&
            reg_matches=1;
          ;;
        *)
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
      0)
        printf "[ERROR 4]: No valid %s file found.\n" "${rbv_file}"
        exit 4
        ;;
      1)
        printf "We'll remove it from the update list to be safe.\n"
        del_ruby_update+=("${1}")
        ;;
      *)
        logic_error "${2}" '2'
        ;;
    esac

  elif [[ "${reg_matches}" -ne 1 ]]; then
    logic_error "${reg_matches}" 'reg_matches'
  fi

  return 0;
}

rb_env_setup(){

  if [[ "${#}" -ne 1 ]]; then
    printf "[ERROR 7]: We expected 1 argument to the rb_env_setup() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  local poss_versions=""
  local r_versions=()

  declare -g r_set_ver=""
  declare -g r_env_versions=()

  case "${1,,}" in
      rbenv)
            mapfile -t r_versions < <(rbenv versions)
            r_set_ver="RBENV_VERSION"
            r_get_cur_ver="rbenv version"
            ;;
        rvm)
            printf "RVM support not yet implemented"
            exit 10
            ;;
          *)
            printf "Unknown or unsupported ruby version manager\n"
            printf "We got: %s\n" "${1}"
            printf "See usage information below:\n"
            printf "\n"
            print_help
            ;;
  esac

  set +o nounset

   for poss_versions in "${r_versions[@]}"; do

    cleaned_var=""

    if [[ "${poss_versions}" =~ ${rbv_reg} ]]; then
      input_clean "${BASH_REMATCH[0]}"

      if [[ -n "${cleaned_var}" ]]; then
        r_env_versions+=("${cleaned_var}");
      else
        logic_error 'unset' 'cleaned_var'
      fi
    fi
   done

  set -o nounset

  # If we couldn't get any sensible versions we'll error.

  if [[ "${#r_versions[@]}" -lt 1 ]]; then
      printf "We couldn't get any valid Ruby versions from the env manager.\n"
      exit 10
  fi

  return 0;
}

parse_ruby_update(){

  local response=""
  local response2=""
  local error_msg=""
  local error2=""
  local red=""
  local std=""
  local line=""

  no_colors=0

  for err_value in "${!err_cmd_list[@]}"; do
    if [[ "${err_value}" == 'tput' ]]; then
      no_colors=1
    fi
  done

  set +o errexit

  if ! response=$(bundle update 2>&1); then
    error_msg="There was an error attempting to update this Ruby project:"
    if [[ "${no_colors}" -eq 0 ]]; then
      red=$(tput setaf 1)
      std=$(tput sgr0)
      error2="${red}${error_msg}${std}"
      printf "%s\n" "${error2}"
      printf "%s\n" "${response}"
    else
      printf "%s\n" "${error_msg}"
      printf "%s\n" "${response}"
    fi
  elif [[ "${no_colors}" -eq 0 ]]; then
    IFS=$'\n'
    green=$(tput setaf 2)
    std=$(tput sgr0)
    for line in ${response}; do
        response2=""
        if [[ "${line,,}" =~ ^(installing) ]]; then
          response2="${green}${line}${std}"
          printf "%s\n" "${response2}"
        else
          printf "%s\n" "${line}"
        fi
    done
  else
    printf "%s\n" "${response}"
  fi

  set -o errexit
  unset IFS

  return 0;
}

parse_response(){

  if [[ "${#}" -ne 1 ]]; then
    printf "[ERROR 7]: We expected 1 argument to the parse_response()\
            function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 7
  fi

  local error_msg=""
  local error2=""
  local response=""
  local response1=""
  local response2=""
  local green=""
  local std=""
  local red=""
  local line=""
  local no_colors=0

  green=$(tput setaf 2)
  std=$(tput sgr0)
  red=$(tput setaf 1)

  # Check for tput and skip the color stuff if not found

  for err_value in "${!err_cmd_list[@]}"; do
    if [[ "${err_value}" == 'tput' ]]; then
      no_colors=1
    fi
  done

  set +o errexit

  if ! response=$(export GIT_TERMINAL_PROMPT=0 && git -C "${1}" pull 2>&1); then
    error_msg="There was an error updating this git repository:"
    if [[ "${no_colors}" -eq 0 ]]; then
      error2="${red}${error_msg}${std}"
      printf "%s\n" "${error2}"
      printf "%s\n" "${response}"
    else
      printf "%s\n" "${error_msg}"
      printf "%s\n" "${response}"
    fi

  # TO-DO: Could make the regex only match after the | char to avoid some
  # processing. Can't do this with lookbehind I don't think? So need to split
  # string again ...

  elif [[ "${no_colors}" -eq 0 ]]; then
    if [[ "${response}" =~ (\+|\-) ]]; then
      #if [[ "${response}" =~ (?<=|)(\+|\-) ]]; then
      IFS=$'\n'
      for line in ${response}; do
        response1=""
        response2=""
        if [[ "${line}" =~ (\|) ]]; then
          #if [[ "${line}" =~ (?<=|)(\+|\-) ]]; then
          response1="${line%%\|*}"
          response2="${line##*\|}"
          response2="${response2//[\+]/${green}\+${std}}"
          response2="${response2//[\-]/${red}\-${std}}"
          printf "%s" "${response1}|"
          printf "%s\n" "${response2}"
        elif [[ "${line}" =~ (\(\+\)|\(\-\)) ]]; then
          response1="${line//[\+]/${green}\+${std}}"
          response1="${response1//[\-]/${red}\-${std}}"
          printf "%s\n" "${response1}"
        else printf "%s\n" "${line}"
        fi
      done
    else
      printf "%s\n" "${response}"
    fi
  else
    printf "%s\n" "${response}"
  fi

  unset IFS
  set -o errexit

  return 0;
}

parse_cabal_version(){

  local response
  local digit1
  local digit2

  cabal_version=0

  response=$(cabal --version)

  if [[ "${response,,}" =~ ([0-9]+)\.([0-9]+) ]]; then
    if [[ "${#BASH_REMATCH[@]}" -gt 2 ]]; then
      digit1="${BASH_REMATCH[1]//[^0-9]/}"
      digit2="${BASH_REMATCH[2]//[^0-9]/}"
      if [[ "${digit1}" -gt 2 ]]; then
        cabal_version=1
      elif [[ "${digit1}" -eq 2 && "${digit2}" -gt 3 ]]; then
        cabal_version=1
      else
        cabal_version=0
      fi
    else
      echo "We got a version response from cabal --version but we couldn't parse it"
    fi
  else
    echo "Could not parse cabal version. We will skip cabal updates"
  fi

  return 0;

}

# printf -- stops the printf command from processing the "-" options as params

print_help(){

  printf "Usage: updateotron [ruby version manager]\n"
  printf "\n"
  printf "For example: updateotron rbenv\n"
  printf "Currently rbenv is the only supported option.\n"
  printf "If no ruby version manager is specified the default is rbenv.\n"
  printf "\n"
  printf "Other options are:\n"
  printf -- "-d    Enable debug mode\n"
  printf -- "-h    Prints this help information and exits.\n"
  printf -- "-l    Prints license information and exits.\n"
  printf "\n"
  printf "See the updateotron.txt file for additional documentation.\n"
  printf "The latest version is available from: "
  printf "https://github.com/octopusnz/scripts\n"

  exit 0;
}

print_license(){

  printf "\n"
  printf "Copyright 2020 Jacob Doherty\n"
  printf "\n"
  printf "Permission is hereby granted, free of charge, to any person \n"
  printf "obtaining a copy of this software and associated documentation \n"
  printf "files (the \"Software\"), to deal in the Software without \n"
  printf "restriction, including without limitation the rights to use, copy, \n"
  printf "modify, merge, publish, distribute, sublicense, and/or sell copies \n"
  printf "of the Software, and to permit persons to whom the Software is \n"
  printf "furnished to do so, subject to the following conditions:\n"
  printf "\n"
  printf "The above copyright notice and this permission notice shall be \n"
  printf "included in all copies or substantial portions of the Software.\n"
  printf "\n"
  printf "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, \n"
  printf "EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF \n"
  printf "MERCHANTABILITY,FITNESS FOR A PARTICULAR PURPOSE AND \n"
  printf "NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT  \n"
  printf "HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, \n"
  printf "WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, \n"
  printf "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER \n"
  printf "DEALINGS IN THE SOFTWARE.\n"

  exit 0;
}

startup(){

  local all_dir=()
  local bash_err=0
  local cmd_test=""
  local dir_list=""
  local err_cmd=0
  local err_dir=0
  local many_dir=""

  declare -g debug=0
  declare -A command_list=()
  declare -gA err_cmd_list=()

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
    [ruby]=mandatory
    [tput]=optional
  )

  if [[ -f "${lock_file_dir%/}${lock_file}" ]]; then
    printf "[ERROR 3]: Lock file exists: %s%s\n" "${lock_file_dir%/}"\
      "${lock_file}";
    exit 3
  fi

  # Create lockfile
  printf "" >> "${lock_file_dir%/}${lock_file}"

  # Check for Bash 4.3+. We set zero if BASH_VERSINFO does not exist due
  # to really old bash versions not providing it by default.

  case "${BASH_VERSINFO[0]:-0}" in

    [0-3])
          bash_err=1
          ;;
        4)
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

  # Check how many command line args were specified when launching the script.
  # We only expect 0 or 1.

  if [[ "${#@}" == 2 ]]; then

    if [[ "${1}" =~ ^(-d|--debug|debug)$ ]]; then
      debug=1
      rb_env_setup "${2}"
    else
      printf "We got more command line options than we expected.\n"
      printf "See below for usage:\n"
      print_help
    fi

  elif [[ "${#@}" -eq 1 ]]; then
    if [[ "${1}" =~ ^(-h|--help|help)$ ]]; then
      print_help
    elif [[ "${1}" =~ ^(-l|--license|license)$ ]]; then
      print_license
    elif [[ "${1}" =~ ^(-d|--debug|debug)$ ]]; then
      debug=1
      rb_env_setup rbenv
    else
      rb_env_setup "${1}"
    fi

  elif [[ "${#@}" -eq 0 ]]; then
    rb_env_setup rbenv

  else
    printf "We got more command line options than we expected.\n"
    printf "See below for usage:\n"
    print_help
  fi

  printf "\n"
  printf "1. Checking if commonly used commands are OK.\n"

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

  printf "\n"
  printf "2. Checking that directories exist.\n"

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

    if [[ -e "${many_dir%/}${git_check}" ]]; then
      git -C "${many_dir}" rev-parse --git-dir > /dev/null 2>&1 &&
      git_array+=("${many_dir}") &&
      printf "%s ready\n" "${many_dir}";
    fi
  done

  return 0;
}

ruby_curation(){

  local del_target=""
  local rb_i=""
  local ruby_dir_test=""

  declare -gA ruby_array=()

  system_ruby=0

  # Try and set a default version to use
  printf "\n"
  printf "Attempting to set default Ruby version.\n"

  if [[ ! -f "${script_dir%/}${rbv_file}" ]]; then
    def_ruby_version=$(${r_get_cur_ver})
    printf "\n"
    printf "Setting default Ruby version: %s\n" "${def_ruby_version}"

    if [[ "${def_ruby_version}" == "system" ]]; then
      system_ruby=1
      printf "System Ruby version has been set as default.\n"
      printf "We'll skip updating RubyGems to avoid trampling your settings.\n"
    fi
  else
    sanitize "${script_dir}" 0
  fi

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

  local cabal_err=0
  local err_value
  local git_updates=""
  local rust_err=0
  local update_params=""

  printf "\n"
  printf "5. Let us try some updates.\n"

  if [[ -e "${rbenv_dir%/}${git_check}" ]]; then
    git -C "${rbenv_dir}" rev-parse --git-dir > /dev/null 2>&1 &&
    printf "Updating rbenv\n" &&
    parse_response "${rbenv_dir}"
  fi

  if [[ -e "${ruby_build_dir%/}${git_check}" ]]; then
    git -C "${ruby_build_dir}" rev-parse --git-dir > /dev/null 2>&1 &&
    printf "Updating ruby-build\n" &&
    parse_response "${ruby_build_dir}"
  fi

  for git_updates in "${git_array[@]}"; do
    printf "Updating %s\n" "${git_updates}"
    parse_response "${git_updates}"
  done

  for update_params in "${!ruby_array[@]}"; do
    printf "Updating %s\n" "${update_params}"
    parse_response "${update_params}"
    export BUNDLE_GEMFILE="${update_params%/}${gem_file}" &&
    export "${r_set_ver}"="${ruby_array["${update_params}"]}" &&
    parse_ruby_update;
  done

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
    parse_cabal_version
    printf "\n"
    printf "Updating Cabal packages.\n"
    if [[ "${cabal_version}" -eq 0 ]]; then
      cabal update
    else
      cabal new-update
    fi
  fi

  # We re-set the ruby version once more in case an earlier update to a ruby
  # project folder left us on another version.

  if [[ "${system_ruby}" -eq 0 ]]; then
    printf "Updating RubyGems.\n"
    printf "Setting default Ruby version: %s\n" "${def_ruby_version}"
    printf "Attempting RubyGems update on this version:\n"
    export "${r_set_ver}"="${def_ruby_version}" &&
    gem update --system;
  else
    if [[ "${#r_env_versions}" -gt 0 ]]; then
      max_ver=0
      max_count=0
      for such_ver in "${r_env_versions[@]}"; do
        [[ ${such_ver} > ${max_ver} ]] &&
          max_ver="${such_ver}" &&
          max_count=$((max_count+1))
      done
      if [[ "${max_count}" -gt 0 ]]; then
        printf "Selecting the highest Ruby version: %s\n" "${max_ver}"
        printf "Attempting RubyGems update on this version:\n"
        export "${r_set_ver}"="${max_ver}" &&
        gem update --system;
      else
        printf "Couldn't parse a valid ruby version\n"
        printf "Skipping RubyGems update\n"
      fi
    else
      printf "Skipping RubyGems update\n"
    fi
  fi

  return 0;
}

startup "${@}"
ruby_curation
updates
exit 0
