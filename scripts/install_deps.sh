#!/bin/bash

PKG_MNG="apt-get"

sudo "$PKG_MNG" update
sudo "$PKG_MNG" upgrade -qy

sudo "$PKG_MNG" install autoconf automake build-essential cmake git-core g++-12 \
  libass-dev libfreetype6-dev libsdl2-dev libtool libva-dev libvdpau-dev gcc-12 \
  libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev pkg-config bc \
  texinfo wget zlib1g-dev nasm yasm libssl-dev time python3 meson ninja-build gobjc++ \
  doxygen xxd jq lshw gnuplot python3-pip curl clang valgrind ccache gawk mawk -y || exit 1

curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"
cargo install cargo-c || exit 1

sudo rm /etc/pip.conf
grep -q '\[global\]' /etc/pip.conf 2> /dev/null || printf '%b' '[global]\n' | sudo tee -a /etc/pip.conf > /dev/null
sudo sed -i '/^\[global\]/a\break-system-packages=true' /etc/pip.conf
pip install --upgrade pip
python3 -m pip install --upgrade virtualenv || exit 1
 