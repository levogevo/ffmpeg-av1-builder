#!/bin/bash

BASE_DIR=$(pwd)
SVT_DIR="$BASE_DIR/svt"
RAV1E_DIR="$BASE_DIR/rav1e"
FFMPEG_DIR="$BASE_DIR/ffmpeg"
AOM_DIR="$BASE_DIR/aom"
VMAF_DIR="$BASE_DIR/vmaf"
DAV1D_DIR="$BASE_DIR/dav1d"
OPUS_DIR="$BASE_DIR/opus"
RKMPP_DIR="$BASE_DIR/rkmpp"
RKRGA_DIR="$BASE_DIR/rkrga"

# clone
git clone --depth 1 https://gitlab.com/AOMediaCodec/SVT-AV1.git "$SVT_DIR"
git clone --depth 1 https://github.com/xiph/rav1e "$RAV1E_DIR"
git clone --depth 1 https://aomedia.googlesource.com/aom "$AOM_DIR"
git clone --depth 1 https://github.com/Netflix/vmaf "$VMAF_DIR"
git clone --depth 1 https://code.videolan.org/videolan/dav1d.git "$DAV1D_DIR"
git clone --depth 1 https://github.com/xiph/opus.git "$OPUS_DIR"

export ARCH=$(arch)
export COMP_FLAGS=""
if [[ "$ARCH" == "x86_64" ]]
then
  COMP_FLAGS="-march=native"
elif [[ "$ARCH" == "aarch64" ]]
then
  COMP_FLAGS="-mcpu=native"
fi
echo "COMP_FLAGS: $COMP_FLAGS"

# for ccache
export PATH="/usr/lib/ccache/:$PATH"

# rockchip ffmpeg libs
FFMPEG_ROCKCHIP=""
IS_ROCKCHIP=$(uname -r | grep "rockchip" > /dev/null && echo "yes" || echo "no")
if [[ "$IS_ROCKCHIP" == "yes" ]]
then
  FFMPEG_ROCKCHIP="--enable-gpl --enable-version3 --enable-libdrm --enable-rkmpp --enable-rkrga"

  # clone rockchip specific repos
  git clone --depth 1 https://github.com/nyanmisaka/ffmpeg-rockchip.git "$FFMPEG_DIR" 
  git clone -b jellyfin-mpp --depth=1 https://github.com/nyanmisaka/mpp.git "$RKMPP_DIR"
  git clone -b jellyfin-rga --depth=1 https://github.com/nyanmisaka/rk-mirrors.git "$RKRGA_DIR"

  # build mpp
  cd "$RKMPP_DIR/" || exit
  git pull
  rm -rf mpp_build
  mkdir mpp_build
  cd mpp_build || exit
  make clean
  cmake .. -DCMAKE_BUILD_TYPE=Release \
           -DBUILD_SHARED_LIBS=ON \
           -DBUILD_TEST=OFF \
           -DCMAKE_C_FLAGS="-O3 $COMP_FLAGS" \
           -DCMAKE_CXX_FLAGS="-O3 $COMP_FLAGS" || exit
  make -j "$(nproc)" || exit
  sudo make install || exit

  # build rga
  cd "$RKRGA_DIR" || exit
  git pull
  rm -rf rga_build
  mkdir rga_build
  cd rga_build || exit
  meson setup ../ rga_build --buildtype release -Db_lto=true \
     --default-library=shared -Dlibdrm=false -Dlibrga_demo=false \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="-fpermissive $COMP_FLAGS" || exit
  ninja -vC rga_build || exit
  sudo ninja -vC rga_build install || exit
else
  git clone https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_DIR" --depth 1  
fi

# build svt-av1
cd "$SVT_DIR/" || exit
git pull
rm -rf build
mkdir build
cd build || exit
make clean
cmake .. -DCMAKE_BUILD_TYPE=Release -DSVT_AV1_LTO=ON \
          -DCMAKE_C_FLAGS="-O3 $COMP_FLAGS" \
          -DCMAKE_CXX_FLAGS="-O3 $COMP_FLAGS" || exit
make -j "$(nproc)" || exit
sudo make install || exit

# build rav1e
cd "$RAV1E_DIR/" || exit
git pull
rm -rf ffmpeg_build && mkdir ffmpeg_build || exit
source "$HOME/.cargo/env" # for good measure
cargo clean
RUSTFLAGS="-C target-cpu=native" cargo cinstall --release \
     --prefix="$(pwd)"/ffmpeg_build \
     --libdir="$(pwd)"/ffmpeg_build/lib \
     --includedir="$(pwd)"/ffmpeg_build/include || exit
cd ffmpeg_build || exit
sudo cp ./lib/* /usr/local/lib/ -r || exit
sudo cp ./include/* /usr/local/include/ -r || exit

# build aom
cd "$AOM_DIR/" || exit
git pull
mkdir build
cd build || exit
make clean
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
          -DCMAKE_C_FLAGS="-flto -O3 $COMP_FLAGS" \
          -DCMAKE_CXX_FLAGS="-flto -O3 $COMP_FLAGS" || exit
make -j "$(nproc)" || exit
sudo make install || exit

# build libvmaf
cd "$VMAF_DIR/libvmaf" || exit
git pull
python3 -m virtualenv .venv
source .venv/bin/activate
rm -rf build
mkdir build
cd build || exit
pip install meson
meson setup ../ build --buildtype release -Denable_float=true -Db_lto=true \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="$COMP_FLAGS" || exit
ninja -vC build || exit
sudo ninja -vC build install || exit

# build dav1d
cd "$DAV1D_DIR" || exit
git pull
rm -rf build
mkdir build
cd build || exit
meson setup ../ build --buildtype release -Db_lto=true \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="$COMP_FLAGS" || exit
ninja -vC build || exit
sudo ninja -vC build install || exit

# build opus
cd "$OPUS_DIR" || exit
git pull
./autogen.sh || exit
export CFLAGS="-O3 -flto $COMP_FLAGS"
./configure || exit
make -j "$(nproc)" || exit
sudo make install || exit
unset CFLAGS

# ldconfig for shared libs
echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/ffmpeg.conf
sudo ldconfig

# build ffmpeg
cd "$FFMPEG_DIR/" || exit
git pull
export PKG_CONFIG_PATH+=":/usr/local/lib/pkgconfig"
make clean
./configure --enable-libsvtav1 --enable-librav1e \
     --enable-libaom --enable-libvmaf \
     --enable-libdav1d --enable-libopus \
     --arch="$ARCH" --cpu=native \
     --enable-lto $FFMPEG_ROCKCHIP \
     --extra-cflags="-O3 $COMP_FLAGS" \
     --extra-cxxflags="-O3 $COMP_FLAGS" \
     --disable-doc --disable-htmlpages \
     --disable-podpages --disable-txtpages || exit
make -j "$(nproc)" || exit
sudo make install || exit

# validate encoders
hash -r
source ~/.profile
ffmpeg -encoders | grep "av1"
