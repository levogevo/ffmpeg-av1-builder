#!/bin/bash

DEPENDENCY_LIST="autoconf automake build-essential cmake git-core g++-12 \
  libass-dev libfreetype6-dev libsdl2-dev libtool libva-dev libvdpau-dev gcc-12 \
  libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev pkg-config bc \
  texinfo wget zlib1g-dev nasm yasm libssl-dev time python3 meson ninja-build gobjc++ \
  doxygen xxd jq lshw gnuplot python3-pip curl clang valgrind ccache gawk mawk"

USING_NALA=$(which nala > /dev/null; echo $?)
USING_APT=$(which apt > /dev/null; echo $?)
USING_PACMAN=$(which pacman > /dev/null; echo $?)

if [[ "$USING_NALA" == "0" ]]; then
  # if nala fails, try apt
  USING_APT="1"
  echo "Installing with nala"
  sudo nala update
  sudo nala install -y $DEPENDENCY_LIST || USING_APT="0"
fi
if [[ "$USING_APT" == "0" ]]; then
  echo "Installing with apt"
  sudo apt-get update
  sudo apt-get install -y $DEPENDENCY_LIST || exit 1
fi
if [[ "$USING_PACMAN" == "0" ]]; then
  echo "Installing with pacman"
  sudo pacman -S $DEPENDENCY_LIST --no-confirm || exit 1
fi

curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"
cargo install cargo-c || exit 1

sudo rm /etc/pip.conf
grep -q '\[global\]' /etc/pip.conf 2> /dev/null || printf '%b' '[global]\n' | sudo tee -a /etc/pip.conf > /dev/null
sudo sed -i '/^\[global\]/a\break-system-packages=true' /etc/pip.conf
pip install --upgrade pip
python3 -m pip install --upgrade virtualenv || exit 1
 