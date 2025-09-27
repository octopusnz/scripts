#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Configurable variables
REPO="koalaman/shellcheck"       # Replace with the GitHub repo, e.g., "torvalds/linux"
MIN_VERSION="0.11.0"             # Version to compare against
GITHUB_API="https://api.github.com/repos/$REPO/releases"

# Fetch release tags from GitHub
if ! release_tags=$(curl -s "$GITHUB_API" | jq -r '.[].tag_name' 2>/dev/null); then
    echo "Failed to fetch releases or jq not available."
    exit 1
fi

if [ -z "$release_tags" ]; then
    echo "No releases found."
    exit 1
fi

# Find the latest release version
latest_release=""
while IFS= read -r version; do
    clean_version="${version#v}"
    if [[ $clean_version =~ ^[0-9] ]]; then
        if [ -z "$latest_release" ] || \
           [ "$(printf "%s\n%s" "${latest_release#v}" "$clean_version" | sort -V | tail -n1)" = "$clean_version" ]; then
            latest_release="$version"
        fi
    fi
done <<< "$release_tags"

if [ -z "$latest_release" ]; then
    echo "No valid release versions found."
    exit 1
fi

echo "The latest release is: $latest_release"

echo
echo "Checking for versions greater than $MIN_VERSION:"

# Find the latest version newer than MIN_VERSION
latest_newer=""
while IFS= read -r version; do
    # Remove leading "v" if present
    clean_version="${version#v}"
    
    # Skip if not a version number (e.g., "stable", "latest")
    if [[ ! $clean_version =~ ^[0-9] ]]; then
        continue
    fi
    
    # Check if this version is newer than MIN_VERSION
    if [ "$(printf "%s\n%s" "$MIN_VERSION" "$clean_version" | sort -V | tail -n1)" = "$clean_version" ] && \
       [ "$clean_version" != "$MIN_VERSION" ]; then
        # Update latest_newer if this is the first or newer
        if [ -z "$latest_newer" ] || \
           [ "$(printf "%s\n%s" "$latest_newer" "$clean_version" | sort -V | tail -n1)" = "$clean_version" ]; then
            latest_newer="$clean_version"
        fi
    fi
done <<< "$release_tags"

if [ -n "$latest_newer" ]; then
    echo "Latest version newer than $MIN_VERSION: $latest_newer"
else
    echo "There were no newer versions found"
fi
