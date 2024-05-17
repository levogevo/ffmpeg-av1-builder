#!/bin/bash

usage() {
     echo "./scripts/build.sh [-h] [-p] [-o] [r] [-a]"
     echo -e "\th: display this help output"
     echo -e "\tp: build svt-av1-psy with dovi library"
     echo -e "\to: build other encoders x264/5 and vpx"
     echo -e "\tr: build rockchip media libraries" 
}

update_git() {
     git config pull.rebase false
     git stash && git stash drop
     git pull
}

OPTS='hpao:'
NUM_OPTS=$(echo $OPTS | tr ':' '\n' | wc -l)
MIN_OPT=0
# using all
MAX_OPT=$(( NUM_OPTS ))
test "$#" -lt $MIN_OPT && echo "not enough arguments" && usage && exit 1
test "$#" -gt $MAX_OPT && echo "too many arguments" && usage && exit 1
while getopts "$OPTS" flag; do
    case "${flag}" in
        h)
               usage
               exit 0
               ;;
        p)
               export BUILD_PSY="true"
               echo "building psy"
               ;;
        o)
               export BUILD_OTHERS="true"
               echo "building other encoders"
               ;;
        r)
               export BUILD_ROCKCHIP="true"
               echo "building rockchip media platform"
               ;;
        *)
               echo "building default"
               ;;
    esac
done

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
DOVI_DIR="$BASE_DIR/dovi"
SVT_PSY_DIR="$BASE_DIR/svt-psy"

# clone
git clone --depth 1 https://gitlab.com/AOMediaCodec/SVT-AV1.git "$SVT_DIR"
git clone --depth 1 https://github.com/quietvoid/dovi_tool "$DOVI_DIR"
git clone --depth 1 https://github.com/gianni-rosato/svt-av1-psy "$SVT_PSY_DIR"
git clone --depth 1 https://github.com/xiph/rav1e "$RAV1E_DIR"
git clone --depth 1 https://aomedia.googlesource.com/aom "$AOM_DIR"
git clone --depth 1 https://github.com/Netflix/vmaf "$VMAF_DIR"
git clone --depth 1 https://code.videolan.org/videolan/dav1d.git "$DAV1D_DIR"
git clone --depth 1 https://github.com/xiph/opus.git "$OPUS_DIR"
git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_DIR"

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
# IS_ROCKCHIP=$(uname -r | grep "rockchip" > /dev/null && echo "yes" || echo "no")
if [[ "$BUILD_ROCKCHIP" == "true" ]]
then
  FFMPEG_ROCKCHIP="--enable-gpl --enable-version3 --enable-libdrm --enable-rkmpp --enable-rkrga"
  FFMPEG_DIR="$BASE_DIR/ffmpeg-rkmpp"

  # clone rockchip specific repos
  git clone --depth 1 https://github.com/nyanmisaka/ffmpeg-rockchip.git "$FFMPEG_DIR" 
  git clone --depth=1 -b jellyfin-mpp https://github.com/nyanmisaka/mpp.git "$RKMPP_DIR"
  git clone --depth=1 -b jellyfin-rga https://github.com/nyanmisaka/rk-mirrors.git "$RKRGA_DIR"

  # build mpp
  cd "$RKMPP_DIR/" || exit
  update_git
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
  update_git
  rm -rf rga_build.user
  mkdir rga_build.user
  cd rga_build.user || exit
  meson setup ../ rga_build.user --buildtype release -Db_lto=true \
     --default-library=shared -Dlibdrm=false -Dlibrga_demo=false \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="-fpermissive $COMP_FLAGS" || exit
  ninja -vC rga_build.user || exit
  sudo ninja -vC rga_build.user install || exit
fi

if [[ "$BUILD_PSY" == "true" ]];
then
     # build dovi_tool
     cd "$DOVI_DIR/" || exit
     update_git
     rm -rf ffmpeg_build.user && mkdir ffmpeg_build.user || exit
     source "$HOME/.cargo/env" # for good measure
     cargo clean
     RUSTFLAGS="-C target-cpu=native" cargo build --release
     sudo cp target/release/dovi_tool /usr/local/bin/ || exit

     # build libdovi
     cd dolby_vision || exit
     RUSTFLAGS="-C target-cpu=native" cargo cinstall --release \
          --prefix="$DOVI_DIR/ffmpeg_build.user" \
          --libdir="$DOVI_DIR/ffmpeg_build.user"/lib \
          --includedir="$DOVI_DIR/ffmpeg_build.user"/include
     cd ffmpeg_build.user || exit
     sudo cp ./lib/* /usr/local/lib/ -r || exit
     sudo cp ./include/* /usr/local/include/ -r

     # build svt-avt-psy
     cd "$SVT_PSY_DIR/" || exit
     update_git
     rm -rf build_svt.user
     mkdir build_svt.user
     cd build_svt.user || exit
     make clean
     cmake .. -DCMAKE_BUILD_TYPE=Release -DSVT_AV1_LTO=ON \
               -DENABLE_AVX512=ON -DBUILD_TESTING=OFF \
               -DCOVERAGE=OFF -DLIBDOVI_FOUND=1 \
               -DCMAKE_C_FLAGS="-O3 $COMP_FLAGS" \
               -DCMAKE_CXX_FLAGS="-O3 $COMP_FLAGS" || exit
     make -j "$(nproc)" || exit
     sudo make install
else
     # build svt-av1
     cd "$SVT_DIR/" || exit
     update_git
     rm -rf build_svt.user
     mkdir build_svt.user
     cd build_svt.user || exit
     make clean
     cmake .. -DCMAKE_BUILD_TYPE=Release -DSVT_AV1_LTO=ON \
               -DENABLE_AVX512=ON -DBUILD_TESTING=OFF \
               -DCOVERAGE=OFF \
               -DCMAKE_C_FLAGS="-O3 $COMP_FLAGS" \
               -DCMAKE_CXX_FLAGS="-O3 $COMP_FLAGS" || exit
     make -j "$(nproc)" || exit
     sudo make install || exit
fi

# build rav1e
cd "$RAV1E_DIR/" || exit
update_git
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
update_git
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
update_git
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
update_git
rm -rf build.user
mkdir build.user
cd build.user || exit
meson setup ../ build.user --buildtype release -Db_lto=true \
     --optimization=3 -Dc_args="$COMP_FLAGS" -Dcpp_args="$COMP_FLAGS" || exit
ninja -vC build.user || exit
sudo ninja -vC build.user install || exit

# build opus
cd "$OPUS_DIR" || exit
update_git
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
update_git
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
sudo cp ff*_g /usr/local/bin/

# validate encoders
hash -r
source ~/.profile
ffmpeg -encoders 2>&1 | grep "av1"
ffmpeg -encoders 2>&1 | grep "rkmpp"
ffmpeg -decoders 2>&1 | grep "rkmpp"
exit 0
