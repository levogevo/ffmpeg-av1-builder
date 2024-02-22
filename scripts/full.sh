#!/bin/bash

bash ./scripts/install_deps.sh || exit 1
bash ./scripts/build.sh || exit 1
bash ./scripts/benchmark.sh || exit 1
