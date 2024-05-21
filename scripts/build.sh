#!/bin/bash

usage() {
     echo "./scripts/build.sh [-h] [-p] [-o] [-r] [-O n]"
     echo -e "\th: display this help output"
     echo -e "\tp: build svt-av1-psy with dovi library"
     echo -e "\to: build other encoders x264/5 and vpx"
     echo -e "\tr: build rockchip media libraries" 
     echo -e "\tO n: build at optimization n (1, 2, 3)" 
}

update_git() {
     git config pull.rebase false
     git stash && git stash drop
     git pull
}

GREP_FILTER="av1"
OPTS='hporO:'
NUM_OPTS=$(echo -n $OPTS | wc -m)
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
               GREP_FILTER+="|x26|libvpx"
               echo "building other encoders"
               ;;
        r)
               export BUILD_ROCKCHIP="true"
               GREP_FILTER+="|rkmpp"
               echo "building rockchip media platform"
               ;;
        O)
               if [[ ${OPTARG} != ?(-)+([[:digit:]]) || ${OPTARG} -lt 0 ]]; then
                    echo "${OPTARG} is not a positive integer"
                    usage
                    exit 1
               fi
               if [[ ${OPTARG} -gt 3 ]]; then
                    echo "${OPTARG} is greater than 3"
                    usage
                    exit 1
               fi
               # set optimization level
               export OPT_LVL="$OPTARG"
               ;;
        *)
               echo 'unsupported flag(s)'
               usage
               exit 1
               ;;
    esac
done

# set default optimization level
if [[ -z $OPT_LVL ]]; then
     OPT_LVL=3
fi
echo "building with O${OPT_LVL}"

# wait a sec for outputs to show
sleep 1

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
X264_DIR="$BASE_DIR/x264"
X265_DIR="$BASE_DIR/x265"
VPX_DIR="$BASE_DIR/vpx"

# save options use
echo "$@" > "$BASE_DIR/.last_opts"

# clone
git clone --depth 1 https://gitlab.com/AOMediaCodec/SVT-AV1.git "$SVT_DIR"
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
               -DCMAKE_C_FLAGS="-O${OPT_LVL} $COMP_FLAGS" \
               -DCMAKE_CXX_FLAGS="-O${OPT_LVL} $COMP_FLAGS" || exit
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
     --optimization="$OPT_LVL" -Dc_args="$COMP_FLAGS" -Dcpp_args="-fpermissive $COMP_FLAGS" || exit
     ninja -vC rga_build.user || exit
     sudo ninja -vC rga_build.user install || exit
fi

if [[ "$BUILD_PSY" == "true" ]];
then
     # clone svt specific repos
     git clone --depth 1 https://github.com/quietvoid/dovi_tool "$DOVI_DIR"
     git clone --depth 1 https://github.com/gianni-rosato/svt-av1-psy "$SVT_PSY_DIR"

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
               -DCMAKE_C_FLAGS="-O${OPT_LVL} $COMP_FLAGS" \
               -DCMAKE_CXX_FLAGS="-O${OPT_LVL} $COMP_FLAGS" || exit
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
               -DCMAKE_C_FLAGS="-O${OPT_LVL} $COMP_FLAGS" \
               -DCMAKE_CXX_FLAGS="-O${OPT_LVL} $COMP_FLAGS" || exit
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
          -DCMAKE_C_FLAGS="-flto -O${OPT_LVL} $COMP_FLAGS" \
          -DCMAKE_CXX_FLAGS="-flto -O${OPT_LVL} $COMP_FLAGS" || exit
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
     --optimization="$OPT_LVL" -Dc_args="$COMP_FLAGS" -Dcpp_args="$COMP_FLAGS" || exit
ninja -vC build.user || exit
sudo ninja -vC build.user install || exit

# build dav1d
cd "$DAV1D_DIR" || exit
update_git
rm -rf build.user
mkdir build.user
cd build.user || exit
meson setup ../ build.user --buildtype release -Db_lto=true \
     --optimization="$OPT_LVL" -Dc_args="$COMP_FLAGS" -Dcpp_args="$COMP_FLAGS" || exit
ninja -vC build.user || exit
sudo ninja -vC build.user install || exit

# build opus
cd "$OPUS_DIR" || exit
update_git
./autogen.sh || exit
export CFLAGS="-O${OPT_LVL} -flto $COMP_FLAGS"
./configure || exit
make -j "$(nproc)" || exit
sudo make install || exit
unset CFLAGS

if [[ "$BUILD_OTHERS" == "true" ]]; then

     # clone other encoder specific repos
     git clone --depth 1 https://code.videolan.org/videolan/x264.git "$X264_DIR"
     git clone --depth 1 https://bitbucket.org/multicoreware/x265_git.git "$X265_DIR"
     git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git "$VPX_DIR"

     FFMPEG_OTHERS="--enable-gpl --enable-libx264 --enable-libx265 --enable-libvpx"     
     
     # build x264
     cd "$X264_DIR" || exit
     update_git
     ./configure --enable-static --enable-pic \
          --enable-shared --enable-lto \
          --extra-cflags="-O${OPT_LVL} $COMP_FLAGS" || exit
     make -j "$(nproc)" || exit
     sudo make install || exit

     # build x265
     cd "$X265_DIR" || exit
     test -d ".git" && git stash && git stash drop
     test -d ".git" && config pull.rebase false
     test -d ".git" && git pull
     # x265 is dumb and only generates pkgconfig
     # if git is not there ("release")
     mv .git .no_git
     rm -rf build.user
     mkdir build.user
     cd build.user || exit
     cmake ../source -DCMAKE_BUILD_TYPE=Release -DNATIVE_BUILD=ON \
               -G "Unix Makefiles" -DHIGH_BIT_DEPTH=ON \
               -DENABLE_HDR10_PLUS=ON \
               -DEXPORT_C_API=ON -DENABLE_SHARED=ON \
               -DCMAKE_C_FLAGS="-flto -O${OPT_LVL} $COMP_FLAGS" \
               -DCMAKE_CXX_FLAGS="-flto -O${OPT_LVL} $COMP_FLAGS" || exit
     make -j "$(nproc)" || exit
     sudo make install || exit
     cd "$X265_DIR" || exit
     # revert git
     mv .no_git .git

     # build vpx
     cd "$VPX_DIR" || exit
     update_git
     ./configure --enable-pic --as=yasm \
          --extra-cflags="-O${OPT_LVL} $COMP_FLAGS" \
          --extra-cxxflags="-O${OPT_LVL} $COMP_FLAGS" \
          --disable-examples --disable-docs \
          --enable-better-hw-compatibility \
          --enable-vp9-highbitdepth \
          --enable-shared
     make -j "$(nproc)" || exit
     sudo make install || exit
fi

# ldconfig for shared libs
sudo mkdir /etc/ld.so.conf.d/
echo -e "/usr/local/lib\n/usr/local/lib/x86_64-linux-gnu" | sudo tee /etc/ld.so.conf.d/ffmpeg.conf || exit 1
sudo ldconfig

# build ffmpeg
cd "$FFMPEG_DIR/" || exit
update_git
export PKG_CONFIG_PATH+=":$(pkg-config --variable pc_path pkg-config)"
./configure --enable-libsvtav1 --enable-librav1e \
     --enable-libaom --enable-libvmaf \
     --enable-libdav1d --enable-libopus \
     $FFMPEG_OTHERS \
     --arch="$ARCH" --cpu=native \
     --enable-lto $FFMPEG_ROCKCHIP \
     --extra-cflags="-O${OPT_LVL} $COMP_FLAGS" \
     --extra-cxxflags="-O${OPT_LVL} $COMP_FLAGS" \
     --disable-doc --disable-htmlpages \
     --disable-podpages --disable-txtpages || exit
make -j "$(nproc)" || exit
sudo make install || exit
sudo cp ff*_g /usr/local/bin/

# validate encoders
hash -r
source ~/.profile
echo -e "\n"
ffmpeg 2>&1 | grep "configuration"
echo -e "\n  encoders:"
ffmpeg -encoders 2>&1 | grep -E "$GREP_FILTER" | grep -Ev "configuration|wmav1"
echo -e "\n  decoders:"
ffmpeg -decoders 2>&1 | grep -E "$GREP_FILTER" | grep -Ev "configuration|wmav1"
exit 0
