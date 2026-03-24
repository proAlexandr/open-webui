#!/usr/bin/env bash
set -euo pipefail

TARGET_BRANCH="promakh-patches"

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

is_rebase_in_progress() {
    local git_dir
    git_dir="$(git rev-parse --git-dir)"
    [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]
}

confirm_yes_default() {
    local prompt="$1"
    local reply
    read -r -p "$prompt [Y/n] " reply
    case "$reply" in
    "" | [Yy])
        return 0
        ;;
    [Nn])
        return 1
        ;;
    *)
        echo "Please answer Y or n."
        confirm_yes_default "$prompt"
        return $?
        ;;
    esac
}

require_cmd git

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: run this script inside a git repository." >&2
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working tree is not clean. Commit or stash changes first." >&2
    exit 1
fi

if ! git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    echo "Error: branch '$TARGET_BRANCH' does not exist locally." >&2
    exit 1
fi

echo "Fetching origin main and tags..."
git fetch origin main --tags

echo "Check the latest release here: https://github.com/open-webui/open-webui/releases/latest"
read -r -p "Enter the latest version tag (e.g. v0.9.6): " latest_tag

if [[ -z "$latest_tag" ]]; then
    echo "Error: tag cannot be empty." >&2
    exit 1
fi

if [[ ! "$latest_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: tag has unexpected format: $latest_tag (expected v0.0.0)" >&2
    exit 1
fi

if ! git rev-parse -q --verify "refs/tags/$latest_tag" >/dev/null 2>&1; then
    echo "Error: tag '$latest_tag' was not found after fetch." >&2
    exit 1
fi

new_version="${latest_tag#v}"
current_tag="$(git describe --tags --match 'v*' --abbrev=0 "$TARGET_BRANCH" 2>/dev/null || true)"

if [[ -z "$current_tag" ]]; then
    echo "Error: failed to determine current v* tag for branch '$TARGET_BRANCH'." >&2
    exit 1
fi

current_version="${current_tag#v}"

if [[ "$current_version" == "$new_version" ]]; then
    echo "Branch '$TARGET_BRANCH' already uses the latest version: $current_version"
    exit 0
fi

if ! confirm_yes_default "Do you want to update $current_version => $new_version?"; then
    echo "Update cancelled by user."
    exit 0
fi

echo "Checking out '$TARGET_BRANCH'..."
git checkout "$TARGET_BRANCH"

echo "Rebasing '$TARGET_BRANCH' onto '$latest_tag'..."
if ! git rebase "$latest_tag"; then
    if ! is_rebase_in_progress; then
        echo "Error: rebase failed before entering conflict resolution flow." >&2
        exit 1
    fi
    while true; do
        echo "Rebase has conflicts. Resolve them, stage changes, then choose an option."
        read -r -p "Press Y to continue or N to abort rebase: " answer
        case "$answer" in
        [Yy])
            if GIT_EDITOR=true git rebase --continue; then
                break
            fi
            if ! is_rebase_in_progress; then
                echo "Error: rebase failed and is no longer in progress." >&2
                exit 1
            fi
            ;;
        [Nn])
            git rebase --abort
            echo "Rebase aborted."
            exit 1
            ;;
        *)
            echo "Please press Y or N."
            ;;
        esac
    done
fi

echo "Branch '$TARGET_BRANCH' was successfully updated to '$latest_tag'."