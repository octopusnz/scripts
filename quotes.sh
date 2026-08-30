#!/bin/bash
# remove-quotes.sh
# Safely remove single quotes from all file and directory names under a given path.

TARGET_DIR="${1:-.}"   # default to current directory if not passed

conflicts=0

# Dry run: check for conflicts first
echo "Checking for conflicts..."
while IFS= read -r path; do
    newpath=$(echo "$path" | tr -d "'")
    if [[ "$path" != "$newpath" ]]; then
        if [[ -e "$newpath" ]]; then
            echo "CONFLICT: '$path' would become '$newpath' (already exists!)"
            conflicts=1
        fi
    fi
done < <(find "$TARGET_DIR" -depth -name "*'*")

if [[ $conflicts -eq 1 ]]; then
    echo "Conflicts detected! Resolve them before running again."
    exit 1
fi

# Do the renaming
echo "No conflicts found. Renaming..."
while IFS= read -r path; do
    newpath=$(echo "$path" | tr -d "'")
    if [[ "$path" != "$newpath" ]]; then
        echo "Renaming: $path -> $newpath"
        mv -- "$path" "$newpath"
    fi
done < <(find "$TARGET_DIR" -depth -name "*'*")

echo "Done."
