#!/usr/bin/env bash
#******************************************************************************#
#                             aggregate.sh                                     #
#                       written by Jacob Doherty                               #
#                             August 2020                                      #
#                                                                              #
#                           Requires Bash v4.3+                                #
#                 See aggregate.txt for documentation and license.             #
#                  Source: https://github.com/octopusnz/scripts                #
#                                                                              #
#              Tracks your development files and dependencies.                 #
#******************************************************************************#

# TO-DO: [7]: Search through header files for other includes!
# TO_DO: [8]: Create dual profect functionality i.e search bash script + c

set -o errexit
set -o nounset
set -o pipefail

compiler_string="CC="
file_ext="c"
lock_file="/aggregate.lock"
lock_file_dir="/tmp"
project_file="Makefile"

include_reg_sys="^\\s*#\\s*include\\s*+[<][^>]*[>]\\s*"
include_reg_usr="^\\s*#\\s*include\\s*+[\"][^\"]*[\"]\\s*"

cleanup(){

  local exit_status

  # This needs to be first so it captures the exit status from the cmd
  # that triggered the trap.

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

setup(){

  local bash_err

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
  fi

  printf "[MSG]: Creating lock file.\n"
  printf "" >> "${lock_file_dir%/}${lock_file}"

  return 0;
}

# Get all project dirs that contain the project file (i.e could be Makefile).
# This find search starts from the location of the script downwards.

get_project_dirs(){

  local such_projects

  full_projects=()

  mapfile -t full_projects < <(find . -type f -iregex ".*${project_file}")

  if [[ "${#full_projects[@]}" -lt 1 ]]; then
    printf "We didn't find any matching projects. Nothing to do.\n"
    exit 0
  fi

  all_projects=()

  for such_projects in "${full_projects[@]}"; do
    such_projects="${such_projects,,}" &&
    such_projects="${such_projects%/*}/" &&
    all_projects+=("${such_projects}");
  done

  return 0;
}

# Get all files and store in array against project based on file ext variable.

get_files(){

  local proj
  local tmp_proj
  declare -gA my_codes

  # TO-DO: [2]: If there are project dirs within dirs we get them all.

  for proj in "${all_projects[@]}"; do

    tmp_proj=()

    mapfile -t tmp_proj < <(find "${proj}" -type f -iregex ".*\.${file_ext}")

    if [[ "${#tmp_proj[@]}" -gt 0 ]]; then
      my_codes+=(["${proj}"]="${tmp_proj[@]}")
    fi
  done

  if [[ "${#my_codes[@]}" -lt 1 ]]; then
    printf "We didn't find any matching files. Nothing to do."
    exit 0
  fi

  return 0;
}

# Count lines in all project files and store them against project.

count_lines(){

  local countme
  local many_projects
  local such_projects
  local tmp_array

  declare -gA line_count

  for such_projects in "${!my_codes[@]}"; do

    countme=0

    IFS=' ' read -r -t 3 -a tmp_array <<< "${my_codes["${such_projects}"]}"

    for many_projects in "${tmp_array[@]}"; do
      countme=$((countme+$(wc -l < "${many_projects}")))

      if [[ "${countme}" -gt 0 ]]; then
        line_count+=(["${such_projects}"]="${countme}")
      fi
    done
  done

  return 0;
}

# We grep the project file (ie could be a makefile) for the string (i.e could be
# CC=) to get the specific compiler used in the project.

determine_compilers(){

  local projects
  local tmp_array

  declare -gA comp_array

  for projects in "${full_projects[@]}"; do

    tmp_array=()

    mapfile -t tmp_array < <(grep -h "${compiler_string}" "${projects}")

    if [[ "${#tmp_array[@]}" -gt 0 ]]; then
      projects="${projects%/*}/" &&
      comp_array+=(["${projects}"]="${tmp_array[@]#"${compiler_string}"*}");
    fi
  done

  return 0;
}

get_compiler_includes(){

  local projects
  local such_locations
  local tmp_array
  local tmp_array_2
  local tmp_var
  local tmp_var_2

  declare -gA compiler_includes

  for projects in "${comp_array[@]}"; do

    tmp_var=""
    tmp_var_2=""
    tmp_array=()
    tmp_array_2=()

    # TO-DO: [4]: Put the compiler command line variables into a string

    tmp_var="$("${projects}" -E -x c - -v < /dev/null 2>&1)" &&
    tmp_var="${tmp_var#*#include <...> search starts here:}" &&
    tmp_var="${tmp_var%End of search list.*}" &&
    tmp_var="${tmp_var// /}"

    #TO-DO [6]: Look at read-array command line args

    readarray -t tmp_array <<< "${tmp_var}"

    # Check if dir exists. This will also get rid of whitespace fields.

    for such_locations in "${tmp_array[@]}"; do
      if [[ -d "${such_locations}" ]]; then
        tmp_array_2+=("${such_locations}")
      fi
    done

    # Flatten back into a string

    tmp_var_2=${tmp_array_2[*]}

    # Store string in associative array using compiler value as key.

    compiler_includes+=(["${projects}"]="${tmp_var_2}")
  done

  return 0;
}

get_headers(){

  local such_projects
  local such_wisdom
  local tmp_array

  declare -gA usr_problem_headers
  declare -gA sys_problem_headers
  declare -gA sys_headers
  declare -gA usr_headers

  for such_projects in "${!my_codes[@]}"; do

    tmp_array=()

    # TO-DO: [3]: Get rid of this IFS usage.

    IFS=' ' read -r -t 3 -a tmp_array <<< "${my_codes["${such_projects}"]}"

    for such_wisdom in "${tmp_array[@]}"; do
      regex_headers "${such_wisdom}" "${such_projects}"
    done
  done

  return 0;
}

regex_headers(){

  local make_line

  while read -r -t 3 make_line || [[ -n "${make_line}" ]]; do

    if [[ "${make_line}" =~ ${include_reg_sys} ]]; then
      input_clean "${BASH_REMATCH[0]}" "${2}" 0

    elif [[ "${make_line}" =~ ${include_reg_usr} ]]; then
      input_clean "${BASH_REMATCH[0]}" "${2}" 1
    fi
  done < "${1}"

  return 0;
}

input_clean(){

  local tmp_clean_1
  local tmp_clean_2

  cleaned_string=""
  tmp_clean_1=""
  tmp_clean_2=""

  clean_regex="<(.*?)>|\"(.*?)\""

  tmp_clean_1="${1}"

  if [[ "${tmp_clean_1}" =~ ${clean_regex} ]]; then
    tmp_clean_2="${BASH_REMATCH[0]}" &&
    cleaned_string="${tmp_clean_2//[^0-9a-zA-Z\.\-\_]/}";

    if [[ "${3}" -eq 0 ]]; then
      find_prob_sys_headers "${cleaned_string}" "${2}"
    elif [[ "${3}" -eq 1 ]]; then
      find_prob_usr_headers "${cleaned_string}" "${2}"
    fi
  fi

  return 0;
}

# We take the list of headers found from the project files and look for them
# in the directories the compiler has in its include path.
# If we can't find the header we'll add it to a new array problem_headers.

find_prob_sys_headers(){

  local comp_lookup
  local head_lookup
  local such_dirs
  local success_counter

  # Go back through and get the compiler string from this array. Based on the
  # project folder which was passed into this function.

  comp_lookup=""
  comp_lookup="${comp_array["${2}"]}"

  # Need to build this array on the fly based on the string of dirs we
  # have in another array.

  head_lookup=()
  IFS=' ' read -r -t 3 -a head_lookup <<< "${compiler_includes[${comp_lookup}]}"

  success_counter=0

  for such_dirs in "${head_lookup[@]}"; do

    # TO-DO: [5]: Decide whether we want to count all successes

    if [[ -e "${such_dirs%/}/${1}" ]]; then
      success_counter=$((success_counter+1))
      break
    fi
  done

  if [[ "${success_counter}" -gt 0 ]]; then
    sys_headers+=(["${2}"]="${1}")
  else
    sys_problem_headers+=(["${2}"]="${1}")
  fi

  return 0;
}

find_prob_usr_headers(){

  # TO-DO [6]: Try and do this without find.
  # grep is tacked on because find will return 0 if search fails but did not
  # error. Need to generate a non-0 return to trigger else.

  if find "${2%/}" -name "${1}" -type f | grep . > /dev/null 2>&1; then
    usr_headers+=(["${2}"]="${1}")
  else
   usr_problem_headers+=(["${2}"]="${1}")
  fi

  return 0;
}

final_output(){

  local such_projects

  set +o nounset

  printf "Thanks for choosing aggregate.\n"
  printf "Gathering system information\n"
  printf "\n"
  printf "We found %s projects:\n" "${#all_projects[@]}"
  printf "%s\n" "${all_projects[@]}"
  printf "\n"
  printf "Let's look at those projects individually:"
  printf "\n"

  for proj in "${all_projects[@]}"; do

    printf "\n"
    printf "%s looks like an interesting project! \n" "${proj}"
    printf "It's using %s as a compiler.\n" "${comp_array[${proj}]}"
    printf "It has these %s files: %s\n" "${file_ext}" "${my_codes[${proj}]}"
    printf "Across those files you've written a total of %s lines of code\n" \
        "${line_count[${proj}]}"
    printf "\n"

    if [[ -n "${sys_headers[$proj]}" ]]; then
      printf "The following system header files were included: %s\n" \
        "${sys_headers[$proj]}"
    fi

    if [[ -n "${sys_problem_headers[$proj]}" ]]; then
      printf "We couldn't find the following system header files in the include "
      printf "path for the compiler:\n"
      printf "%s\n" "${sys_problem_headers[$proj]}"
    fi

    if [[ -n "${usr_headers[$proj]}" ]]; then
      printf "The following user header files were included: %s\n" \
        "${usr_headers[$proj]}"
    fi

    if [[ -n "${usr_problem_headers[$proj]}" ]]; then
      printf "We couldn't find the following user header files in the project "
      printf "directories:\n"
      printf "%s\n" "${usr_problem_headers[$proj]}"
    fi

  done

  set -o nounset

  return 0
}

setup
get_project_dirs
get_files
count_lines
determine_compilers
get_compiler_includes
get_headers
final_output
exit 0
