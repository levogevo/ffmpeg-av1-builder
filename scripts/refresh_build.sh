#!/bin/bash

git pull
bash ./scripts/install_deps.sh || exit 1
bash ./scripts/build.sh $(cat .last_opts) || exit 1
