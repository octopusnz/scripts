#!/usr/bin/env bash

# aggregate
# This script gives you a consolidated view of your C code.

set -o errexit
set -o nounset
set -o pipefail

DEFAULT_IFS=$' \t\n'

cpp='cpp-10.2'
compiler_string='CC='
file_ext='c'

#TODO need to make these ignore whitespace

sys_include_string='#include <'
usr_include_string='#include \"'
lock_file_dir='/tmp'
lock_file='/aggregate.lock'
project_file='Makefile'

include_reg_sys='^\\s*#\\s*include\\s*+[<][^>]*[>]\\s*'
include_reg_usr='^\\s*#\\s*include\\s*+[\"][^\"]*[\"]\\s*'

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

  IFS="${DEFAULT_IFS}"
  unset DEFAULT_IFS
  unset MAPFILE

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
  local such_locations
  local tmp_locations

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

  # TODO - try and replicate the sed with bash param expansion!

  tmp_locations=()

  mapfile -t tmp_locations < <("${cpp}" -v -x c < /dev/null 2>&1 | \
    sed -nE 's/^ ([^ ]+)$/\1/p')

  # Even though cpp does this check for non-existent dirs, we'll do it again.
  # Because we trust no one.

  header_locations=()

  for such_locations in "${tmp_locations[@]}"; do

    if [[ -d "${such_locations}" ]]; then
      header_locations+=("${such_locations}")
    fi
  done

  return 0;
}

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

get_files(){

  local such_projects
  local tmp_proj
  declare -gA my_codes

  # TODO - Because the find is recursive if there are project dirs within
  # project dirs it will include the files twice.

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

input_clean(){

  local tmp_clean_1
  local tmp_clean_2

  cleaned_var=''

  tmp_clean_1="${1,,}" &&
    tmp_clean_2="${tmp_clean_1//[^0-9a-z\.\-]/}" &&
    cleaned_var="${tmp_clean_2}";

    if [[ "${2}" -eq 0 ]]; then


    elif [[ "${2}" -eq 1 ]]; then

  return 0;
}

regex_headers(){

  local make_line

  while read -r -t 3 make_line || [[ -n "${make_line}" ]]; do

    if [[ "${make_line}" =~ ${include_reg_sys} ]]; then
      input_clean "${BASH_REMATCH[0]}" 0

    elif [[ "${make_line}" =~ ${include_reg_usr} ]]; then
      input_clean "${BASH_REMATCH[0]}" 1
    fi
  done < "${1}"

  return 0;
}

get_headers(){

  local such_projects
  local tmp_array
  local tmp_head
  declare -gA sys_headers
  declare -gA usr_headers

  for such_projects in "${!my_codes[@]}"; do

    tmp_array=()
    tmp_head=()

    IFS=' ' read -r -t 3 -a tmp_array <<< "${my_codes["${such_projects}"]}"
    IFS="${DEFAULT_IFS}"

    for such_wisdom in "${tmp_array[@]}"; do
      regex_headers "${such_wisdom}"
    done

    mapfile -t tmp_head < <(grep -h "${sys_include_string}" "${tmp_array[@]}")

    # TODO: Need to cater these param expansion scenarios for both:
    # #include <test> and #include<test> etc ...

    if [[ "${#tmp_head[@]}" -gt 0 ]]; then
      sys_headers+=(["${such_projects}"]="${tmp_head[@]#\#include *}")
    fi

    tmp_head=()

    mapfile -t tmp_head < <(grep -h "${usr_include_string}" "${tmp_array[@]#}")

    if [[ "${#tmp_head[@]}" -gt 0 ]]; then
      usr_headers+=(["${such_projects}"]="${tmp_head[@]#\#include *}")
    fi
  done

  return 0;
}

determine_compilers(){

  local such_projects
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

#get_all_library_locations(){
#
#for compilers in "${comp_array[@]}"; do
# echo "WOO"
#done
#  return 0;
#}


print_some_stuff(){

  echo "Header Locations:"
  echo "${!header_locations[@]}"
  echo "${header_locations[@]}"
  echo ""
  echo "All Projects:"
  echo "${!all_projects[@]}"
  echo "${all_projects[@]}"
  echo ""
  echo "C Files:"
  echo "${!my_codes[@]}"
  echo "${my_codes[@]}"
  echo ""
  echo "System Headers:"
  echo "${!sys_headers[@]}"
  echo "${sys_headers[@]}"
  echo ""
  echo "User Headers:"
  echo "${!usr_headers[@]}"
  echo "${usr_headers[@]}"
  echo ""
  echo "Compilers:"
  echo "${!comp_array[@]}"
  echo "${comp_array[@]}"

  return 0;
}

setup
get_project_dirs
get_files
get_headers
determine_compilers
print_some_stuff
exit 0
