#!/bin/bash

BASE_DIR=$(pwd)
SVT_DIR="$BASE_DIR/svt"
RAV1E_DIR="$BASE_DIR/rav1e"
FFMPEG_DIR="$BASE_DIR/ffmpeg"

# clone
git clone https://gitlab.com/AOMediaCodec/SVT-AV1.git "$SVT_DIR" --depth 1
git clone https://github.com/xiph/rav1e "$RAV1E_DIR" --depth 1
git clone https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_DIR" --depth 1

# build svt-av1
cd "$SVT_DIR/" || exit
git pull
mkdir build
cd build || exit
make clean
cmake .. -DCMAKE_BUILD_TYPE=Release -DSVT_AV1_LTO=ON -DNATIVE=ON
make -j "$(nproc)"
sudo make install

# build rav1e
cd "$RAV1E_DIR/" || exit
git pull
rm -rf ffmpeg_build && mkdir ffmpeg_build || exit
source "$HOME/.cargo/env" # for good measure
cargo clean
RUSTFLAGS="-C target-cpu=native" cargo cinstall --release \
     --prefix="$(pwd)"/ffmpeg_build \
     --libdir="$(pwd)"/ffmpeg_build/lib \
     --includedir="$(pwd)"/ffmpeg_build/include

cd ffmpeg_build || exit
sudo cp ./lib/* /usr/local/lib/ -r
sudo cp ./include/* /usr/local/include/ -r

# build ffmpeg
cd "$FFMPEG_DIR/" || exit
export LD_LIBRARY_PATH+=":/usr/local/lib"
export PKG_CONFIG_PATH+=":/usr/local/lib/pkgconfig"
make clean
./configure --enable-libsvtav1 --enable-librav1e
make -j "$(nproc)"
sudo make install

hash -r
source ~/.profile
ffmpeg -encoders | grep "av1"
