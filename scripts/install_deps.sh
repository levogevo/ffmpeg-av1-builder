#!/usr/bin/env bash

COMMON_DEP_NAMES="autoconf automake cmake libtool texinfo \
  wget nasm yasm python3 meson doxygen jq gnuplot ccache gawk"

COMMON_DEP_NAMES_LINUX="time clang valgrind curl bc lshw xxd pkg-config"

APT_DEP_NAMES="build-essential git-core libass-dev libfreetype6-dev \
  libsdl2-dev libva-dev libvdpau-dev libvorbis-dev libxcb1-dev mold \
  libxcb-shm0-dev libxcb-xfixes0-dev zlib1g-dev libssl-dev ninja-build \
  gobjc++ python3-pip mawk libnuma-dev mediainfo mkvtoolnix libgtest-dev"

PACMAN_DEP_NAMES="base-devel ninja python-pip"

BREW_DEP_NAMES="pkgconf mkvtoolnix"

install_deps() {
  if command -v nala ; then
    echo "Installing with nala"
    sudo nala update
    sudo nala install -y $COMMON_DEP_NAMES \
      $COMMON_DEP_NAMES_LINUX \
      $APT_DEP_NAMES && return 0
  fi
  if command -v apt ; then
    echo "Installing with apt"
    sudo apt-get update
    sudo apt-get install -y $COMMON_DEP_NAMES \
      $COMMON_DEP_NAMES_LINUX \
      $APT_DEP_NAMES || exit 1
    return 0
  fi
  if command -v pacman ; then
    echo "Installing with pacman"
    sudo pacman -S $COMMON_DEP_NAMES \
      $COMMON_DEP_NAMES_LINUX \
      $PACMAN_DEP_NAMES --noconfirm || exit 1
    return 0
  fi
  if command -v brew ; then
    echo "Installing with brew"
    brew install $COMMON_DEP_NAMES \
      $BREW_DEP_NAMES || exit 1
    return 0
  fi
  return 1
}

install_deps

curl https://sh.rustup.rs -sSf | sh -s -- -y
source "$HOME/.cargo/env"
cargo install cargo-c || exit 1

if test -f /etc/pip.conf ; then
  sudo rm /etc/pip.conf
  grep -q '\[global\]' /etc/pip.conf 2> /dev/null || printf '%b' '[global]\n' | sudo tee -a /etc/pip.conf > /dev/null
  sudo sed -i '/^\[global\]/a\break-system-packages=true' /etc/pip.conf
fi
python3 -m pip install --upgrade virtualenv --break-system-packages || exit 1
