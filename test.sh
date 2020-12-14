#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

make_reg="makefile"
full_projects=()
tmp_array=()
success=0

main(){

    shopt -s nocasematch

    for files in *; do
	if [[ -f "${files}" ]]; then
	    if [[ "${files}" =~ ${make_reg} ]]; then
		full_projects+=("${PWD}")
		success=$((success+1))
		#This will only find the first one
		break
	    fi
	fi
    done

    shopt -u nocasematch

    if [[ "${success}" -gt 0 ]]; then
	cleanup
    fi
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
		full_projects+=("${deeper_files}")
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
}

cleanup() {

    if [[ "${#full_projects[@]}" -lt 1 ]]; then
	printf "We didn't find any matching projects. Nothing to do.\n"
	exit 0
    fi

    echo "Before sanitizing we found these projects"
    echo "${full_projects[@]}"

    all_projects=()

    for such_projects in "${full_projects[@]}"; do
	such_projects="${such_projects,,}" &&
	#such_projects="${such_projects%%"${home_dir}}" &&
	all_projects+=("${such_projects}");
    done

    echo "We found these projects:"
    echo "${all_projects[@]}"

    # Will probably blow up before this due to above commands failing but just
    # in case ...

  if [[ "${#all_projects[@]}" -lt 1 ]]; then
    printf "We couldn't parse the projects dirs. Nothing to do.\n"
    printf "We got these: %s" "${full_projects[@]}"
    exit 0
  fi

  exit 0
}

main
dir_check
cleanup
