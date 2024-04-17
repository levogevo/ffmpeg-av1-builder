#!/bin/bash

COMMON_DEP_NAMES="autoconf automake cmake libtool pkg-config bc texinfo \
  wget nasm yasm time python3 meson doxygen xxd jq lshw gnuplot curl \
  clang valgrind ccache gawk"

APT_DEP_NAMES="build-essential git-core g++-12 libass-dev libfreetype6-dev \
  libsdl2-dev libva-dev libvdpau-dev gcc-12 libvorbis-dev libxcb1-dev \
  libxcb-shm0-dev libxcb-xfixes0-dev zlib1g-dev libssl-dev ninja-build \
  gobjc++ python3-pip mawk mediainfo mkvpropedit"

PACMAN_DEP_NAMES="base-devel ninja python-pip"

USING_NALA=$(type nala > /dev/null; echo $?)
USING_APT=$(type apt > /dev/null; echo $?)
USING_PACMAN=$(type pacman > /dev/null; echo $?)

if [[ "$USING_NALA" == "0" ]]; then
  # if nala fails, try apt
  USING_APT="1"
  echo "Installing with nala"
  sudo nala update
  sudo nala install -y $COMMON_DEP_NAMES $APT_DEP_NAMES || USING_APT="0"
fi
if [[ "$USING_APT" == "0" ]]; then
  echo "Installing with apt"
  sudo apt-get update
  sudo apt-get install -y $COMMON_DEP_NAMES $APT_DEP_NAMES || exit 1
fi
if [[ "$USING_PACMAN" == "0" ]]; then
  echo "Installing with pacman"
  sudo pacman -S $COMMON_DEP_NAMES $PACMAN_DEP_NAMES --noconfirm || exit 1
fi

curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"
cargo install cargo-c || exit 1

sudo rm /etc/pip.conf
grep -q '\[global\]' /etc/pip.conf 2> /dev/null || printf '%b' '[global]\n' | sudo tee -a /etc/pip.conf > /dev/null
sudo sed -i '/^\[global\]/a\break-system-packages=true' /etc/pip.conf
pip install --upgrade pip
python3 -m pip install --upgrade virtualenv || exit 1
 