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

export ARCH=$(uname -m)
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
  git stash && git stash drop
  git pull
  rm -rf mpp_build.user
  mkdir mpp_build.user
  cd mpp_build.user || exit
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
  git stash && git stash drop
  git pull
  rm -rf rga_build.user
  mkdir rga_build.user
  cd rga_build.user || exit
  meson setup ../ rga_build.user --buildtype release -Db_lto=true \
     --default-library=shared -Dlibdrm=false -Dlibrga_demo=false \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="-fpermissive $COMP_FLAGS" || exit
  ninja -vC rga_build.user || exit
  sudo ninja -vC rga_build.user install || exit
else
  git clone https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_DIR" --depth 1  
fi

# build svt-av1
cd "$SVT_DIR/" || exit
git pull
rm -rf build_svt.user
mkdir build_svt.user
cd build_svt.user || exit
make clean
cmake .. -DCMAKE_BUILD_TYPE=Release -DSVT_AV1_LTO=ON \
          -DCMAKE_C_FLAGS="-O3 $COMP_FLAGS" \
          -DCMAKE_CXX_FLAGS="-O3 $COMP_FLAGS" || exit
make -j "$(nproc)" || exit
sudo make install || exit

# build rav1e
cd "$RAV1E_DIR/" || exit
git stash && git stash drop
git pull
rm -rf ffmpeg_build.user && mkdir ffmpeg_build.user || exit
source "$HOME/.cargo/env" # for good measure
cargo clean
RUSTFLAGS="-C target-cpu=native" cargo cinstall --release \
     --prefix="$(pwd)"/ffmpeg_build.user \
     --libdir="$(pwd)"/ffmpeg_build.user/lib \
     --includedir="$(pwd)"/ffmpeg_build.user/include || exit
cd ffmpeg_build.user || exit
sudo cp ./lib/* /usr/local/lib/ -r || exit
sudo cp ./include/* /usr/local/include/ -r || exit

# build aom
cd "$AOM_DIR/" || exit
git stash && git stash drop
git pull
rm -rf build_aom.user
mkdir build_aom.user
cd build_aom.user || exit
make clean
cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
          -DENABLE_TESTS=OFF \
          -DCMAKE_C_FLAGS="-flto -O3 $COMP_FLAGS" \
          -DCMAKE_CXX_FLAGS="-flto -O3 $COMP_FLAGS" || exit
make -j "$(nproc)" || exit
sudo make install || exit

# build libvmaf
cd "$VMAF_DIR/libvmaf" || exit
git stash && git stash drop
git pull
python3 -m virtualenv .venv
source .venv/bin/activate
rm -rf build.user
mkdir build.user
cd build.user || exit
pip install meson
meson setup ../ build.user --buildtype release -Denable_float=true -Db_lto=true \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="$COMP_FLAGS" || exit
ninja -vC build.user || exit
sudo ninja -vC build.user install || exit

# build dav1d
cd "$DAV1D_DIR" || exit
git stash && git stash drop
git pull
rm -rf build.user
mkdir build.user
cd build.user || exit
meson setup ../ build.user --buildtype release -Db_lto=true \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="$COMP_FLAGS" || exit
ninja -vC build.user || exit
sudo ninja -vC build.user install || exit

# build opus
cd "$OPUS_DIR" || exit
git stash && git stash drop
git pull
./autogen.sh || exit
export CFLAGS="-O3 -flto $COMP_FLAGS"
./configure || exit
make -j "$(nproc)" || exit
sudo make install || exit
unset CFLAGS

# ldconfig for shared libs
sudo mkdir /etc/ld.so.conf.d/
echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/ffmpeg.conf || exit 1
sudo ldconfig

# build ffmpeg
cd "$FFMPEG_DIR/" || exit
git stash && git stash drop
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
