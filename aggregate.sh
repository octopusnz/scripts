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

# User editable config options. See aggregate.txt for more information.

lock_file="/aggregate.lock"
lock_file_dir="/tmp"
make_reg="makefile"
file_ext_name="c"
file_reg="^.*\.(c)$"

# Regex used in functions

include_reg_sys="^\\s*#\\s*include\\s*+[<][^>]*[>]\\s*"
include_reg_usr="^\\s*#\\s*include\\s*+[\"][^\"]*[\"]\\s*"
cc_reg="(^\\s*CC\\s*)(\\s*:\\s*)?(\\s*?\\s*)?(=)"
clean_regex="<(.*?)>|\"(.*?)\""
# function_regex="^\s*(?:(?:inline|static)\s+){0,2}(?!else|typedef|return)\w+\s+\*?\s*(\w+)\s*\([^0]+\)\s*;?"

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

tmp_charge(){

  set +o nounset

  if [[ "${#tmp_array[@]}" -gt 0 ]]; then
      for deeper_files in "${tmp_array[@]}"; do
          cd "${deeper_files}"
          cust_get_files
      done
  fi

  set -o nounset

}

cust_get_files() {

    shopt -s nocasematch
    success=0

    for files in *; do
        if [[ -f "${files}" ]]; then
            if [[ "${files}" =~ ${make_reg} ]]; then
                full_projects+=("${PWD}"/"${files}")
                success=$((success+1))
                #This will only find the first one
                break
            fi
        fi
    done

    shopt -u nocasematch

    if [[ "${success}" -eq 0 ]]; then
        unset tmp_array
        for dirs in *; do
            if [[ -d "${dirs}" ]]; then
                tmp_array+=("${PWD}"/"${dirs}")
            fi
        done
        tmp_charge
    fi
}

dir_check() {

    for dirs in *; do
        if [[ -d "${dirs}" ]]; then
            dirs_array+=("${PWD}"/"${dirs}")
        fi
    done

    for deeper_files in "${dirs_array[@]}"; do
        cd "${deeper_files}"
        cust_get_files
    done

    project_cleanup

    return 0;
}

project_cleanup() {

    if [[ "${#full_projects[@]}" -lt 1 ]]; then
        printf "We didn't find any matching projects. Nothing to do.\n"
        exit 0
    fi

    all_projects=()

    for such_projects in "${full_projects[@]}"; do
        such_projects="${such_projects,,}" &&
        such_projects="${such_projects%/*}/"
        #such_projects="${such_projects##*/}" &&
        all_projects+=("${such_projects}");
    done

    # Will probably blow up before this due to above commands failing but just
    # in case ...

  if [[ "${#all_projects[@]}" -lt 1 ]]; then
    printf "We couldn't parse the projects dirs. Nothing to do.\n"
    printf "We got these: %s" "${full_projects[@]}"
    exit 0
  fi

  return 0;
}

# Get all project dirs that contain the project file (i.e could be Makefile).
# The search is recursive from the dir the script was executed from.

get_project_dirs(){

full_projects=()
tmp_array=()
success=0

    shopt -s nocasematch

    for files in *; do
        if [[ -f "${files}" ]]; then
          if [[ "${files}" =~ ${make_reg} ]]; then
            full_projects+=("${PWD}"/"${files}")
            success=$((success+1))
            #This will only find the first one
            break
          fi
        fi
    done

    shopt -u nocasematch

    if [[ "${success}" -gt 0 ]]; then
        project_cleanup

    else
        dir_check
    fi

    return 0;
}

# Get all files and store in array against project based on file ext variable.

get_files(){

  local proj
  local files_array
  local files
  local tmp_array
  local such_files

  declare -gA my_codes

  proj=""
  my_codes=()

  # TO-DO: If there are project dirs within dirs we get them all.

  for proj in "${all_projects[@]}"; do
    files_array=()
    files=""
    tmp_array=()
    such_files=""

    shopt -s globstar

    for files in "${proj}"**/*; do
      if [[ -f "${files}" ]]; then
        tmp_array+=("${files}")
      fi
    done

    shopt -u globstar

    shopt -s nocasematch

    for such_files in "${tmp_array[@]}"; do

    if [[ "${such_files}" =~ ${file_reg} ]]; then
      files_array+=("${such_files}")

    fi
    done

    shopt -u nocasematch

    if [[ "${#files_array[@]}" -gt 0 ]]; then
      my_codes+=(["${proj}"]="${files_array[@]}")
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

  such_projects=""
  line_count=()
  tmp_array=()

  for such_projects in "${!my_codes[@]}"; do

    countme=0
    many_projects=""

    IFS=' ' read -r -t 3 -a tmp_array <<< "${my_codes["${such_projects}"]}"

    for many_projects in "${tmp_array[@]}"; do
      countme=$((countme+$(wc -l < "${many_projects}")))

      if [[ "${countme}" -gt 0 ]]; then
        line_count+=(["${such_projects}"]="${countme}")
      fi
    done
  done

  # TO-DO: Maybe consider removing the project from the project array if it
  # has no files with lines ? Depends on final output.

  return 0;
}

determine_compilers(){

  local projects
  local cc_line

  declare -gA comp_array

  projects=""
  comp_array=()

  for projects in "${full_projects[@]}"; do

      cc_line=""
      cc_success_counter=0

    while read -r -t 3 cc_line || [[ -n "${cc_line}" ]]; do

        if [[ "${cc_line}" =~ ${cc_reg} ]]; then

            projects="${projects%/*}/"
            cc_line="${cc_line#*\=}"
            comp_array+=(["${projects}"]="${cc_line}");
            cc_success_counter="${cc_success_counter}"+1
            break
        fi

    done < "${projects}"

    # TO-DO: Maybe put another check in here that cc is a valid command
    if [[ "${cc_success_counter}" -eq 0 ]]; then
        printf "Couldn't find a specific compiler in %s\n" "${projects}"
        printf "We will set cc as default \n"
        projects="${projects%/*}/"
        comp_array+=(["${projects}"]="cc");
    fi

  done

  # TO-DO: Review this, supposed to be a catchall if all of the above fails.
  if [[ "${#comp_array[@]}" -lt 1 ]]; then
    printf "Couldn't parse compilers, nothing to do."
    exit 1
  fi

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

  projects=""
  compiler_includes=()

  for projects in "${comp_array[@]}"; do

    tmp_var=""
    tmp_var_2=""
    tmp_array=()
    tmp_array_2=()
    such_locations=""

    # TO-DO: Put the compiler command line variables into a string
    #        Maybe look at get opts?

    tmp_var="$(${projects} -E -x c - -v < /dev/null 2>&1)" &&
    tmp_var="${tmp_var#*#include <...> search starts here:}" &&
    tmp_var="${tmp_var%End of search list.*}" &&
    tmp_var="${tmp_var// /}"

    #TO-DO: Look at read-array command line args

    readarray -t tmp_array <<< "${tmp_var}"

    #TO-DO: Probably look at just removing project rather than error out

    if [[ "${#tmp_array[@]}" -lt 1 ]]; then
      printf "Couldn't parse system header locations from compiler"
      exit 1
    fi

    # Check if dir exists. This will also get rid of whitespace fields.

    for such_locations in "${tmp_array[@]}"; do
      if [[ -d "${such_locations}" ]]; then
        tmp_array_2+=("${such_locations}")
      fi
    done

    if [[ "${#tmp_array_2[@]}" -lt 1 ]]; then
      printf "Couldn't parse system header locations from compiler"
      exit 1
    fi

    # Flatten back into a string

    tmp_var_2=${tmp_array_2[*]}

    # Store string in associative array using compiler value as key.

    compiler_includes+=(["${projects}"]="${tmp_var_2}")
  done

  return 0;
}

get_headers(){

  local such_projects
  local raw_headers

  declare -gA usr_problem_headers
  declare -gA sys_problem_headers
  declare -gA sys_headers
  declare -gA usr_headers

  usr_problem_headers=()
  sys_problem_headers=()
  sys_headers=()
  usr_headers=()
  such_projects=""

  for such_projects in "${!my_codes[@]}"; do

    raw_headers=()

    # TO-DO: Try to get rid of this IFS usage

    IFS=' ' read -r -t 3 -a raw_headers <<< "${my_codes["${such_projects}"]}"
    regex_headers "${such_projects}"
  done

  return 0;
}

regex_headers(){

  if [[ "${#}" -ne 1 ]]; then
    printf "[ERROR]: We expected 1 argument to the regex_headers() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 1
  fi

  local make_line
  local such_loop
  local array_sys
  local array_usr

  declare -A clean_array_sys
  declare -A clean_array_usr

  array_sys=()
  array_usr=()
  clean_array_sys=()
  clean_array_usr=()
  such_loop=""

  for such_loop in "${raw_headers[@]}"; do

    make_line=""

    #TO-DO: Investigate whether the OR "-n" here needs nounsetmatch to be
    #       temporarily disabled.

    # We read these into associative arrays just to clear out any duplicates
    # using the keys.

    while read -r -t 3 make_line || [[ -n "${make_line}" ]]; do

      if [[ "${make_line}" =~ ${include_reg_sys} ]]; then
          clean_array_sys+=(["${BASH_REMATCH[0]}"]="${1}")
      elif [[ "${make_line}" =~ ${include_reg_usr} ]]; then
          clean_array_usr+=(["${BASH_REMATCH[0]}"]="${1}")
      fi
    done < "${such_loop}"
  done

  if [[ "${#clean_array_sys[@]}" -gt 0 ]]; then
    dirty_key=""
    for dirty_key in "${!clean_array_sys[@]}"; do
      array_sys+=("${dirty_key}")
    done
    input_clean "${1}" 0 "${array_sys[@]}"
  fi

  if [[ "${#clean_array_usr[@]}" -gt 0 ]]; then
    dirty_key=""
    for dirty_key in "${!clean_array_usr[@]}"; do
      array_usr+=("${dirty_key}")
    done
    input_clean "${1}" 1 "${array_usr[@]}"
  fi

  return 0;
}

input_clean(){

  # TO-DO: Need to investigate this a bit. I think it's passing all the indicies
  # of the array as individual parameters? i.e if 2 are in the array it will
  # send 4 params in total from regex_headers.

  if [[ "${#}" -lt 3 ]]; then
    printf "[ERROR]: We expected at least 3 arguments to the regex_headers()\
           function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 1
  fi

  local tmp_clean_1
  local tmp_clean_2
  local tmp_clean_3
  local header_type
  local tmp_array
  local such_headers
  local cleaned_string
  local input_tmp_sys
  local input_tmp_usr
  local input_proj_name

  tmp_array=()
  such_headers=""
  input_tmp_sys=()
  input_tmp_usr=()
  input_proj_name=""
  header_type=""

 # Get and set the parameters passed from the regex_headers() function.

  input_proj_name="${1}"
  header_type="${2}"
  shift 2
  tmp_array=("$@")

  # Clean each header string 1-1 then put it in the appropriate array.

  for such_headers in "${tmp_array[@]}"; do

    cleaned_string=""
    tmp_clean_1=""
    tmp_clean_2=""
    tmp_clean_3=""
    tmp_clean_1="${such_headers}"

    if [[ "${tmp_clean_1}" =~ ${clean_regex} ]]; then
        tmp_clean_2="${BASH_REMATCH[0]}" &&
        tmp_clean_3="${tmp_clean_2##*/}"
        cleaned_string="${tmp_clean_3//[^0-9a-zA-Z\.\-\_]/}";

    # TO-DO: Maybe need to think about another check here that the above
    #        succeeded. It will likely blow up before due to command failing.

      if [[ "${header_type}" -eq 0 ]]; then
        input_tmp_sys+=("${cleaned_string}")
      elif [[ "${header_type}" -eq 1 ]]; then
        input_tmp_usr+=("${cleaned_string}")
      fi
    fi
  done

  # Send the arrays of cleaned strings on their way to their final function
  # to check if they exist.

  if [[ "${#input_tmp_sys[@]}" -gt 0 ]]; then
    find_prob_sys_headers "${input_proj_name}" "${input_tmp_sys[@]}"
  fi

  if [[ "${#input_tmp_usr[@]}" -gt 0 ]]; then
    find_prob_usr_headers "${input_proj_name}" "${input_tmp_usr[@]}"
  fi

  return 0;
}

# We take the list of headers found from the project files and look for them
# in the directories the compiler has in its include path.
# If we can't find the header we'll add it to a new array problem_headers.

find_prob_sys_headers(){

  if [[ "${#}" -lt 2 ]]; then
    printf "[ERROR]: We expected at least 2 arguments to the"
    printf "find_prob_sys_headers()function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 1
  fi

  local comp_lookup
  local head_lookup
  local such_dirs
  local success_counter
  local proj_name
  local tmp_array
  local headers
  local tmp_sys_headers
  local tmp_sys_problem_headers

  proj_name=""
  headers=""
  tmp_array=()
  tmp_sys_headers=()
  tmp_sys_problem_headers=()

  proj_name="${1}"
  shift
  tmp_array=("$@")

  # Go back through and get the compiler string from this array. Based on the
  # project folder which was passed into this function.

  comp_lookup="${comp_array[${proj_name}]}"

  # Need to build this array on the fly based on the string of dirs we
  # have in another array.

  head_lookup=()
  IFS=' ' read -r -t 3 -a head_lookup <<< "${compiler_includes[${comp_lookup}]}"

  success_counter=0

  for headers in "${tmp_array[@]}"; do

    such_dirs=""

    for such_dirs in "${head_lookup[@]}"; do

    # TO-DO: [5]: Decide whether we want to count all successes

      if [[ -f "${such_dirs%/}/${headers}" ]]; then
        success_counter=$((success_counter+1))
        break
      fi
    done

    if [[ "${success_counter}" -gt 0 ]]; then
      tmp_sys_headers+=("${headers}")
    else
      tmp_sys_problem_headers+=("${headers}")
    fi
  done

  if [[ "${#tmp_sys_headers[@]}" -gt 0 ]]; then
      sys_headers+=(["${proj_name}"]="${tmp_sys_headers[@]}")
  fi

  if [[ "${#tmp_sys_problem_headers[@]}" -gt 0 ]]; then
      sys_problem_headers+=(["${proj_name}"]="${tmp_sys_problem_headers[@]}")
  fi

  return 0;
}

find_prob_usr_headers(){

  if [[ "${#}" -lt 2 ]]; then
    printf "[ERROR]: We expected at least 2 arguments to the"
    printf "find_prob_usr_headers() function.\n"
    printf "But we got %s instead.\n" "${#}"
    exit 1
  fi

  local proj_name
  local tmp_array
  local headers
  local headers_reg
  local files_array
  local such_files
  local files
  local tmp_usr_headers
  local tmp_usr_problem_headers
  local success_counter

  proj_name=""
  tmp_array=()
  headers=""
  headers_reg=""
  files_array=()
  such_files=""
  files=""
  tmp_usr_headers=()
  tmp_usr_problem_headers=()

  proj_name="${1}"
  shift
  tmp_array=("$@")

  shopt -s globstar

  for files in "${proj_name}"**/*; do
    if [[ -f "${files}" ]]; then
      files_array+=("${files}")
    fi
  done

  shopt -u globstar

  for headers in "${tmp_array[@]}"; do

    headers_reg="${headers}"
    success_counter=0

    for such_files in "${files_array[@]}"; do

      if [[ "${such_files}" =~ ${headers_reg} ]]; then
        tmp_usr_headers+=("${headers}")
        success_counter=$(("${success_counter}" +1))
        break
      fi
    done

    if [[ "${success_counter}" -eq 0 ]]; then
      tmp_usr_problem_headers+=("${headers}")
    fi
  done

  if [[ "${#tmp_usr_headers[@]}" -gt 0 ]]; then
      usr_headers+=(["${proj_name}"]="${tmp_usr_headers[@]}")
  fi

  if [[ "${#tmp_usr_problem_headers[@]}" -gt 0 ]]; then
      usr_problem_headers+=(["${proj_name}"]="${tmp_usr_problem_headers[@]}")
  fi

  return 0;
}

final_output(){

  local proj

  proj=""

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
    printf "It has these %s files: %s\n" "${file_ext_name}"\
      "${my_codes[${proj}]}"
    printf "Across those files you've written a total of %s lines of code\n"\
        "${line_count[${proj}]}"
    printf "\n"

    if [[ -n "${sys_headers[$proj]}" ]]; then
      printf "The following system header files were included: %s\n"\
        "${sys_headers[$proj]}"
    fi

    if [[ -n "${sys_problem_headers[$proj]}" ]]; then
      printf "We couldn't find the following system header files in the"
      printf " include path for the compiler:\n"
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
