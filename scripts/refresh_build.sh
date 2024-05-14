#!/bin/bash

git pull
bash ./scripts/install_deps.sh || exit 1
bash ./scripts/build.sh || exit 1
