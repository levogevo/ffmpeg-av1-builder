#!/bin/bash

sudo apt-get update

sudo apt-get install autoconf automake build-essential cmake git-core \
  libass-dev libfreetype6-dev libsdl2-dev libtool libva-dev libvdpau-dev \
  libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev pkg-config \
  texinfo wget zlib1g-dev nasm yasm libssl-dev time python3 meson ninja-build\
  doxygen xxd jq lshw -y || exit 1

curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"
cargo install cargo-c || exit 1

python3 -m pip install virtualenv || exit 1
 