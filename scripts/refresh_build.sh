#!/bin/bash

# global path variables
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BUILDER_DIR" || exit

git stash
git stash drop
git pull
bash ./scripts/install_deps.sh || exit 1
bash ./scripts/build.sh $(cat .last_opts) || exit 1
