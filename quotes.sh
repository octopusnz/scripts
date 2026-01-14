#!/bin/bash
# remove-quotes.sh
# Safely remove single quotes from all file and directory names under a given path.

TARGET_DIR="${1:-.}"   # default to current directory if not passed

conflicts=0

# Function to transform path by removing quotes
get_transformed_path() {
    local path="$1"
    echo "$path" | tr -d "'"
}

# Function to check if path transformation is needed
# Returns 0 if path needs transformation, 1 otherwise
needs_transformation() {
    local path="$1"
    local newpath
    newpath=$(get_transformed_path "$path")
    [[ "$path" != "$newpath" ]]
}

# Dry run: check for conflicts first
echo "Checking for conflicts..."
while IFS= read -r path; do
    if needs_transformation "$path"; then
        newpath=$(get_transformed_path "$path")
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
    if needs_transformation "$path"; then
        newpath=$(get_transformed_path "$path")
        echo "Renaming: $path -> $newpath"
        mv -- "$path" "$newpath"
    fi
done < <(find "$TARGET_DIR" -depth -name "*'*")

echo "Done."
