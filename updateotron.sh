#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Why this? 
# https://stackoverflow.com/questions/4494336/how-do-you-store-a-list-of-directories-into-an-array-in-bash-and-then-print-the

shopt -s dotglob
shopt -s nullglob

# Here you can define your directories

git_dir="$HOME/sources/compile/"
rbenv_dir="$HOME/.rbenv/"
ruby_build_dir="$HOME/.rbenv/plugins/ruby-build/"
ruby_projects_dir="$HOME/ruby/"
all_dir=("$git_dir" "$rbenv_dir" "$ruby_build_dir" "$ruby_projects_dir")
git_test=("$git_dir"*/)
git_array=()

# The following exit codes are specified.
# When adding new ones take into account: 
# http://www.tldp.org/LDP/abs/html/exitcodes.html
#
# Exit 0 - Success.
# Exit 1 - Reserved for system.
# Exit 2 - Reserved for system.
# Exit 3 - Lock file exists. 
#	The script creates a file called updateotron.lock and checks for its 
# 	existence to prevent the script running multiple times.
# Exit 4 - Lock file does not exist. 
# 	At the end of the script when running cleanup we check for the lock
#	file before running rm. Where did it go?

startup(){
	echo "Welcome to the update script."
	echo "Doing some setup."
	
	if [ -f "updateotron.lock" ]
		then
			echo "[ERROR 3]: Lock file exists."
			exit 3
	fi

	echo "[MSG]: Creating lock file."
	touch updateotron.lock
	echo ""
	echo "1. Checking that directories exist."

	for dir in "${all_dir[@]}"; do
		if [ ! -d "$dir" ] 
			then
    			echo "[WARNING]: Directory '$dir' does not exist."
    		else 
    			echo "$dir OK"
    	fi;
	done

	echo ""
	echo "2. Checking which directories are git repositories."
	
	for many_dir in "${git_test[@]}"; do
		git -C "$many_dir" rev-parse > /dev/null 2>&1 && 
			git_array+=("$many_dir")
	done

	for dir_test in "${git_array[@]}"; do
		echo "$dir_test"
	done	
}

cleanup(){
	echo ""
	echo "3. Cleaning up and exiting"
	echo "[MSG]: Unsetting variables"
	unset all_dir check_dir dir git_dir git_test many_dir rbenv_dir
	unset ruby_build_dir ruby_projects_dir 

	if [ ! -f "updateotron.lock" ]
		then
			echo "[ERROR 4]: Lock file does not exist"
			exit 4
		else 
			echo "[MSG]: Removing lock file"
			rm updateotron.lock
			exit 0
	fi
}

startup
cleanup
