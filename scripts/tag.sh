#!/bin/bash

set -e -u -o pipefail

# Constants
MAX_PRE_VERSION_COUNT=50
REMOTE_NAME="${GIT_REMOTE_NAME:-origin}"
DRY_RUN="${DRY_RUN:-false}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Logging Functions ---
info() { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
die() {
    echo -e "${RED}$*${NC}" >&2
    exit 1
}

# --- Usage/Help ---
usage() {
    cat <<EOF
Usage: $(basename "$0") [COMMAND]

A Git tag management script that supports semantic versioning and date-based versioning.

COMMANDS:
    check_version    Check if version(s) in Version file(s) are already tagged
                     (Fails on non-default branches if version exists)

    (no command)     Create and push tags based on Version file(s)
                     - On default branch: creates release tags
                     - On feature branches: creates prerelease tags

    help, --help     Show this help message

VERSION FILE FORMAT:
    Create a file named "Version" containing:
    - Semantic version: "1.2.3" → creates tag "v1.2.3"
    - Date-based: "date" → creates tag "vYYYY.M.D" (e.g., "v2025.10.17")
    - Monorepo: Place Version files in subdirs → creates "subdir/v1.2.3"

ENVIRONMENT VARIABLES:
    GIT_REMOTE_NAME  Git remote name (default: origin)
    DRY_RUN          Set to 'true' to preview actions without pushing (default: false)

EXAMPLES:
    # Check if version needs to be bumped (for PRs)
    $0 check_version

    # Create and push tags
    $0

    # Dry run mode
    DRY_RUN=true $0

EXIT CODES:
    0    Success
    1    Error (version already exists, no Version files found, etc.)

EOF
    exit 0
}

# --- Git Helper Functions ---

# Fetches the default branch name from the remote.
get_default_branch() {
    git remote show "$REMOTE_NAME" | grep 'HEAD branch' | cut -d' ' -f5
}

# Generates a date-based version string in YYYY.M.D format (no leading zeros).
# Compatible with both GNU date (Linux) and BSD date (macOS).
generate_date_version() {
    local year month day
    year=$(date +%Y)

    # Try GNU date format first (%-m removes leading zero)
    month=$(date +%-m 2>/dev/null || date +%m | sed 's/^0//')
    day=$(date +%-d 2>/dev/null || date +%d | sed 's/^0//')

    echo "${year}.${month}.${day}"
}

# Calculates the version string from a "Version" file.
# Arg1: Path to the Version file
get_version_from_file() {
    local version_file=$1
    local dir
    dir=$(dirname "$version_file")
    local module_path=""

    if [ "$dir" != "." ]; then
        module_path="$dir/"
    fi

    local version_content
    version_content=$(cat "$version_file" | tr -d '[:space:]')

    if [ "$version_content" = "date" ]; then
        echo "${module_path}v$(generate_date_version)"
    else
        echo "${module_path}v$version_content"
    fi
}

# Checks if a tag exists on the remote.
# Arg1: Tag name
tag_exists_on_remote() {
    git ls-remote --exit-code --tags "$REMOTE_NAME" "refs/tags/$1" >/dev/null 2>&1
}

# --- Main Logic Functions ---

# Checks if the version in a file already exists as a tag.
# For non-default branches, it fails if the version is already tagged.
check_version() {
    local version_file=$1
    local default_branch=$2
    local current_branch=$3

    local version_content
    version_content=$(cat "$version_file" | tr -d '[:space:]')

    # Special case: if version is "date", skip tag existence check
    if [ "$version_content" = "date" ]; then
        success "Version file '$version_file' is set to 'date'. Tag will be based on the current date."
        return 0
    fi

    local version
    version=$(get_version_from_file "$version_file")

    info "Checking version $version from file $version_file..."

    if tag_exists_on_remote "$version"; then
        warn "Version ${version} already exists as a tag on ${REMOTE_NAME}."
        if [ "$current_branch" != "$default_branch" ]; then
            die "Version file '$version_file' must be updated before merging."
        fi
    else
        success "Version ${version} is not yet tagged."
    fi
}

# Creates and pushes a release tag.
# Arg1: Version file path
create_release_tag() {
    local version_file=$1
    local version
    version=$(get_version_from_file "$version_file")

    local version_content
    version_content=$(cat "$version_file" | tr -d '[:space:]')

    # Check if this is a date-based version
    if [ "$version_content" = "date" ]; then
        # For date-based versions, handle same-day releases with incrementing counter
        if tag_exists_on_remote "$version"; then
            info "Base date tag $version already exists. Finding next available counter..."
            local counter=1
            while [ $counter -lt $MAX_PRE_VERSION_COUNT ]; do
                local versioned_tag="${version}.${counter}"
                info "  Trying tag: $versioned_tag"

                if tag_exists_on_remote "$versioned_tag"; then
                    warn "  Tag $versioned_tag already exists."
                    ((counter++))
                else
                    info "Creating and pushing release tag $versioned_tag..."
                    if [ "$DRY_RUN" = "true" ]; then
                        warn "[DRY RUN] Would create and push tag: $versioned_tag"
                    else
                        git tag "$versioned_tag"
                        git push "$REMOTE_NAME" "$versioned_tag"
                        echo "tag=$versioned_tag" >> "${GITHUB_OUTPUT:-/dev/null}"
                    fi
                    success "Successfully pushed tag $versioned_tag."
                    return 0
                fi
            done
            die "Could not find an available date version for $version after $MAX_PRE_VERSION_COUNT attempts."
        else
            info "Creating and pushing release tag $version..."
            if [ "$DRY_RUN" = "true" ]; then
                warn "[DRY RUN] Would create and push tag: $version"
            else
                git tag "$version"
                git push "$REMOTE_NAME" "$version"
                echo "tag=$version" >> "${GITHUB_OUTPUT:-/dev/null}"
            fi
            success "Successfully pushed tag $version."
        fi
    else
        # For regular semantic versions, use original logic
        if tag_exists_on_remote "$version"; then
            warn "Release tag $version already exists. Skipping."
        else
            info "Creating and pushing release tag $version..."
            if [ "$DRY_RUN" = "true" ]; then
                warn "[DRY RUN] Would create and push tag: $version"
            else
                git tag "$version"
                git push "$REMOTE_NAME" "$version"
                echo "tag=$version" >> "${GITHUB_OUTPUT:-/dev/null}"
            fi
            success "Successfully pushed tag $version."
        fi
    fi
}

# Finds the next available prerelease tag, creates, and pushes it.
# Arg1: Version file path
# Arg2: Current branch name
create_prerelease_tag() {
    local version_file=$1
    local current_branch=$2
    local base_version
    base_version=$(get_version_from_file "$version_file")

    # Sanitize branch name for use in prerelease version.
    # Example: 'feature/DEV-123-new-login' -> 'feature-DEV-123-new-login'
    local prerelease_suffix
    prerelease_suffix=$(echo "$current_branch" | sed -e 's/[^0-9a-zA-Z]/-/g' -e 's/--+/-/g')

    info "Finding next prerelease version for $base_version on branch $current_branch..."

    local counter=1
    while [ $counter -lt $MAX_PRE_VERSION_COUNT ]; do
        local tag_to_try="${base_version}-${prerelease_suffix}.${counter}"
        info "  Trying tag: $tag_to_try"

        if tag_exists_on_remote "$tag_to_try"; then
            warn "  Tag $tag_to_try already exists."
            ((counter++))
        else
            info "Found available tag: $tag_to_try"
            if [ "$DRY_RUN" = "true" ]; then
                warn "[DRY RUN] Would create and push tag: $tag_to_try"
            else
                git tag "$tag_to_try"
                git push "$REMOTE_NAME" "$tag_to_try"
                echo "tag=$tag_to_try" >> "${GITHUB_OUTPUT:-/dev/null}"
            fi
            success "Successfully pushed tag $tag_to_try."
            return 0
        fi
    done

    die "Could not find an available prerelease version for $base_version after $MAX_PRE_VERSION_COUNT attempts."
}


# --- Main Execution ---
main() {
    # Handle help
    if [ "${1:-}" = "help" ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        usage
    fi

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    info "Current branch is: $current_branch"

    # Find all 'Version' files.
    local version_files
    version_files=$(find . -name "Version" | sed 's|^\./||')
    if [[ -z "${version_files// /}" ]]; then
        warn "No 'Version' files found. Nothing to do."
        exit 0
    fi

    # Fetch all tags from remote for faster local checks.
    info "Fetching all tags from ${REMOTE_NAME}..."
    git fetch --tags "$REMOTE_NAME"

    local default_branch
    default_branch=$(get_default_branch)
    info "Default branch is: $default_branch"

    # Mode 1: Check versions
    if [ "${1:-}" = "check_version" ]; then
        info "\nRunning in 'check_version' mode."
        for file in $version_files; do
            check_version "$file" "$default_branch" "$current_branch"
        done
        success "\nAll version files look good!"
        exit 0
    fi

    # Mode 2: Create and push tags
    info "\nRunning in 'create_tag' mode."
    [ "$DRY_RUN" = "true" ] && warn "DRY RUN MODE: No tags will actually be created or pushed."

    for file in $version_files;
    do
        if [ "$current_branch" == "$default_branch" ]; then
            create_release_tag "$file"
        else
            create_prerelease_tag "$file" "$current_branch"
        fi
    done

    success "\nTagging process complete."
}

# Run the main function with all provided script arguments.
main "$@"
