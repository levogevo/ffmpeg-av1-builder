#!/usr/bin/env bash

usage() {
     echo "./scripts/build.sh [options]"
     echo -e "\th:\tdisplay this help output"
     echo -e "\tA:\tbuild all AV1 encoders (default is only svt-av1-psy)"
     echo -e "\ts:\tbuild svt-av1 (default is svt-av1-psy)"
     echo -e "\to:\tbuild other encoders (x264/5 and vpx)"
     echo -e "\tr:\tbuild rockchip media libraries"
     echo -e "\tv:\tbuild libvmaf"
     echo -e "\tl:\tcompile without lto (default is enabled)"
     echo -e "\tO n:\tbuild optimization level (default is 3)" 
}

# global path variables
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BUILDER_DIR" || exit

# build with psy and lto as default
BUILD_PSY='Y'
BUILD_LTO='Y'

# options for ffmpeg configure
FFMPEG_CONFIGURE_OPT=""

GREP_FILTER="av1"
OPTS='hAsvorlO:'
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
               BUILD_PSY='Y'
               echo "building psy"
               ;;
        A)
               BUILD_ALL_AV1='Y'
               FFMPEG_CONFIGURE_OPT+="--enable-libaom --enable-librav1e "
               echo "building all other av1 encoders"
               ;;
        s)
               BUILD_SVT='Y'
               BUILD_PSY=false
               echo "building svt-av1"
               ;;
        v)
               BUILD_VMAF='Y'
               FFMPEG_CONFIGURE_OPT+="--enable-libvmaf "
               echo "building libvmaf"
               ;;
        o)
               BUILD_OTHERS='Y'
               GREP_FILTER+="|x26|libvpx"
               FFMPEG_CONFIGURE_OPT+="--enable-libx264 --enable-libx265 --enable-libvpx "
               echo "building other encoders"
               ;;
        r)
               BUILD_ROCKCHIP='Y'
               GREP_FILTER+="|rkmpp"
               FMPEG_CONFIGURE_OPT+="--enable-version3 --enable-libdrm --enable-rkmpp --enable-rkrga "
               echo "building rockchip media platform"
               ;;
        l)
               BUILD_LTO='N'
               echo "building without lto"
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
               OPT_LVL=$OPTARG
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

BASE_DIR="$(pwd)"
REPOS_DIR="$BASE_DIR/repos"
SVT_DIR="$REPOS_DIR/svt"
RAV1E_DIR="$REPOS_DIR/rav1e"
FFMPEG_DIR="$REPOS_DIR/ffmpeg"
AOM_DIR="$REPOS_DIR/aom"
VMAF_DIR="$REPOS_DIR/vmaf"
DAV1D_DIR="$REPOS_DIR/dav1d"
OPUS_DIR="$REPOS_DIR/opus"
RKMPP_DIR="$REPOS_DIR/rkmpp"
RKRGA_DIR="$REPOS_DIR/rkrga"
DOVI_DIR="$REPOS_DIR/dovi"
HDR10_DIR="$REPOS_DIR/hdr10plus"
SVT_PSY_DIR="$REPOS_DIR/svt-psy"
X264_DIR="$REPOS_DIR/x264"
X265_DIR="$REPOS_DIR/x265"
GTEST_DIR="$REPOS_DIR/googletest"
VPX_DIR="$REPOS_DIR/vpx"
test -d "$REPOS_DIR" || mkdir "$REPOS_DIR"

# test if options are different
# so that rebuild is forced
if [[ "$(sort "$BASE_DIR/.last_opts")" != "$(echo "$@" | sort )" ]]; then
     FORCE_REBUILD=1
fi

# save options use
echo "$@" > "$BASE_DIR/.last_opts"

# save which commits were successful
GOOD_COMMIT_BUILDS="$BASE_DIR/.good_commits"
good_commit_output() {
     echo "$(git remote -v | head -n1 | awk '{print $2}' | sed 's/.*\///' | sed 's/\.git//'):$(git rev-parse HEAD)"
}
set_commit_status() {
     grep -q "$(good_commit_output)" "$GOOD_COMMIT_BUILDS" || good_commit_output >> "$GOOD_COMMIT_BUILDS"
}

check_edition2024() {
     if grep -q "edition2024" Cargo.toml ; then
          echo "edition2024 already enabled"
          return 0
     fi
     echo -e 'cargo-features = ["edition2024"]\n\n'"$(cat Cargo.toml)" > Cargo.toml || return 1
     return 0
}

GIT_DEPTH='5'
check_for_rebuild() {
     # don't stash this actual repo
     CURRENT_REPO="$(basename "$(git rev-parse --show-toplevel)")"
     if [[ "$CURRENT_REPO" == "ffmpeg-av1-builder" ]]; then 
          exit 1
     fi
     git config pull.rebase false
     git stash && git stash drop
     git pull || return 1
     LATEST_REMOTE="$(git ls-remote "$(git config --get remote.origin.url)" HEAD | awk '{ print $1 }')"
     CURRENT_HEAD="$(git rev-parse HEAD)"
     test "$FORCE_REBUILD" == '1' && return 1
     test "$LATEST_REMOTE" != "$CURRENT_HEAD" && return 1
     # check if project built successfully
     grep -q "$(good_commit_output)" "$GOOD_COMMIT_BUILDS" || return 1
     return 0
}

# prefix to install
PREFIX='/usr/local'

# lto mess
if [[ "$BUILD_LTO" == 'Y' ]]; then
     LTO_SWITCH='ON'
     LTO_FLAG='-flto'
     LTO_BOOL='true'
     LTO_CONFIGURE='--enable-lto'
     FFMPEG_CONFIGURE_OPT+="${LTO_CONFIGURE} "
elif [[ "$BUILD_LTO" == 'N' ]]; then
     LTO_SWITCH='OFF'
     LTO_FLAG=''
     LTO_BOOL='false'
     LTO_CONFIGURE=''
fi

# architecture/cpu compile flags
ARCH=$(uname -m)
COMP_FLAGS=""
if [[ "$ARCH" == "x86_64" ]]
then
  COMP_FLAGS+=" -march=native"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]
then
  COMP_FLAGS+=" -mcpu=native"
fi

# compilation job count
if commmand -v nproc 2> /dev/null ; then
     THREADS="$(nproc)"
fi

# for MacOs / Darwin
if [ "$(uname)" == "Darwin" ] ; then
     COMP_FLAGS+=" -I${PREFIX}/include"
     FFMPEG_CONFIGURE_OPT+="--enable-rpath "
     THREADS="$(sysctl -n hw.ncpu)"
fi

echo "COMP_FLAGS: [${COMP_FLAGS}]"

# for ccache
export PATH="/usr/lib/ccache:$PATH"

# check for required local directories
REQ_DIRS=(
     "${PREFIX}/bin" 
     "${PREFIX}/lib"
     "${PREFIX}/include"
     "${PREFIX}/share"
)

for DIR in "${REQ_DIRS[@]}"
do
     test -d "$DIR" || \
          mkdir -p "$DIR" || \
          sudo mkdir -p "$DIR" 
done

# WSL2 hardware clock skew
if [[ "$(uname -r)" =~ "WSL" ]] ; then
     sudo hwclock -s
fi

# clone ffmpeg
git clone https://github.com/FFmpeg/FFmpeg "$FFMPEG_DIR"

build_mpp() {
     # build mpp
     git clone --depth "$GIT_DEPTH" -b jellyfin-mpp https://github.com/nyanmisaka/mpp.git "$RKMPP_DIR"
     cd "$RKMPP_DIR/" || return 1
     check_for_rebuild && return 0
     rm -rf mpp_build.user
     mkdir mpp_build.user
     cd mpp_build.user || return 1
     make clean
     cmake .. -DCMAKE_BUILD_TYPE=Release \
               -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
               -DCMAKE_INSTALL_RPATH="${PREFIX}/lib" \
               -DBUILD_SHARED_LIBS=ON \
               -DBUILD_TEST=OFF \
               -DCMAKE_C_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" \
               -DCMAKE_CXX_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" || return 1
     ccache make -j"${THREADS}" || return 1
     sudo make install || return 1
}

build_rkga() {     
     # build rga
     git clone --depth "$GIT_DEPTH" -b jellyfin-rga https://github.com/nyanmisaka/rk-mirrors.git "$RKRGA_DIR"
     cd "$RKRGA_DIR" || return 1 
     check_for_rebuild && return 0
     rm -rf rga_build.user
     mkdir rga_build.user
     meson setup . rga_build.user \
          --buildtype release \
          --prefix "${PREFIX}" \
          --default-library=shared \
          -Db_lto=true \
          -Dlibdrm=false \
          -Dlibrga_demo=false \
          --optimization="$OPT_LVL" \
          -Dc_args="${COMP_FLAGS}" \
          -Dcpp_args="-fpermissive ${COMP_FLAGS}" || return 1
     ccache ninja -vC rga_build.user || return 1
     sudo ninja -vC rga_build.user install || return 1
}

# rockchip ffmpeg libs
# IS_ROCKCHIP=$(uname -r | grep "rockchip" > /dev/null && echo "yes" || echo "no")
if [[ "$BUILD_ROCKCHIP" == "Y" ]]
then
     # override default ffmpeg directory
     FFMPEG_DIR+="-rkmpp"
     git clone --depth "$GIT_DEPTH" https://github.com/nyanmisaka/ffmpeg-rockchip.git "$FFMPEG_DIR"

     build_mpp || exit 1
     build_rkga || exit 1

fi

build_dovi() {
     # build dovi_tool
     git clone --depth "$GIT_DEPTH" https://github.com/quietvoid/dovi_tool "$DOVI_DIR"
     cd "$DOVI_DIR" || return 1 
     check_for_rebuild && return 0
     check_edition2024
     source "$HOME/.cargo/env" # for good measure
     cargo clean
     RUSTFLAGS="-C target-cpu=native" ccache cargo build --release
     sudo cp target/release/dovi_tool "${PREFIX}/bin/" || return 1

     # build libdovi
     cd dolby_vision || return 1
     check_edition2024
     RUSTFLAGS="-C target-cpu=native" ccache cargo cbuild --release
     sudo -E bash -lc "cargo cinstall --prefix=${PREFIX} --release" || return 1
     set_commit_status
}

build_hdr10plus() {
     # build hdr10plus_tool
     git clone --depth "$GIT_DEPTH" https://github.com/quietvoid/hdr10plus_tool "$HDR10_DIR"
     cd "$HDR10_DIR" || return 1 
     check_for_rebuild && return 0
     check_edition2024
     source "$HOME/.cargo/env" # for good measure
     cargo clean
     RUSTFLAGS="-C target-cpu=native" ccache cargo build --release
     sudo cp target/release/hdr10plus_tool "${PREFIX}/bin/" || return 1

     # build libhdr10plus
     cd hdr10plus || return 1
     check_edition2024
     RUSTFLAGS="-C target-cpu=native" ccache cargo cbuild --release
     sudo -E bash -lc "cargo cinstall --prefix=${PREFIX} --release" || return 1
     set_commit_status
}

build_svt_av1_psy() {
     # build svt-av1-psy
     # svt-av1-psy cannot be cleanly updated 
     # due to histories error
     local GIT_REPO_URL='https://github.com/gianni-rosato/svt-av1-psy'
     local CMAKE_BUILD_DIR="$SVT_PSY_DIR/build_svt.user"
     REMOTE_HEAD_SHA="$(git ls-remote "$GIT_REPO_URL" HEAD | awk '{ print $1 }')"
     CURR_HEAD_SHA="$(git -C "$SVT_PSY_DIR" rev-parse HEAD)"
     if [[ "$REMOTE_HEAD_SHA" != "$CURR_HEAD_SHA" ]]; then
          # wipe and start over
          rm -rf "$SVT_PSY_DIR"
          git clone --depth "$GIT_DEPTH" "$GIT_REPO_URL" "$SVT_PSY_DIR"
     fi
     cd "$SVT_PSY_DIR" || return 1

     check_for_rebuild && \
          cd "$CMAKE_BUILD_DIR" && \
          sudo make install && \
          set_commit_status && \
          return 0

     sudo rm -rf "$CMAKE_BUILD_DIR"
     mkdir "$CMAKE_BUILD_DIR"
     cd "$CMAKE_BUILD_DIR" || return 1
     cmake \
          -DCMAKE_BUILD_TYPE=Release \
          -DSVT_AV1_LTO="${LTO_SWITCH}" \
          -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DENABLE_AVX512=ON \
          -DBUILD_TESTING=OFF \
          -DCOVERAGE=OFF \
          -DLIBDOVI_FOUND=0 \
          -DLIBHDR10PLUS_RS_FOUND=0 \
          -DCMAKE_INSTALL_RPATH="${PREFIX}/lib" \
          -DCMAKE_C_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" \
          -DCMAKE_CXX_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" \
          "$SVT_PSY_DIR" || return 1
     make clean
     ccache make -j"${THREADS}" || return 1
     sudo make install
     cd "$SVT_PSY_DIR/" || return 1
     set_commit_status
}

build_svt_av1() {
     # build svt-av1
     local CMAKE_BUILD_DIR="$SVT_DIR/build_svt.user"
     git clone --depth "$GIT_DEPTH" https://gitlab.com/AOMediaCodec/SVT-AV1.git "$SVT_DIR"
     cd "$SVT_DIR" || return 1

     check_for_rebuild && \
          cd "$CMAKE_BUILD_DIR" && \
          sudo make install && \
          set_commit_status && \
          return 0

     sudo rm -rf "$CMAKE_BUILD_DIR"
     mkdir "$CMAKE_BUILD_DIR"
     cd "$CMAKE_BUILD_DIR" || return 1
     cmake \
          -DCMAKE_BUILD_TYPE=Release \
          -DSVT_AV1_LTO="${LTO_SWITCH}" \
          -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DENABLE_AVX512=ON \
          -DBUILD_TESTING=OFF \
          -DCOVERAGE=OFF \
          -DCMAKE_INSTALL_RPATH="${PREFIX}/lib" \
          -DCMAKE_C_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" \
          -DCMAKE_CXX_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" \
          "$SVT_DIR/" || return 1
     make clean
     ccache make -j"${THREADS}" || return 1
     sudo make install || return 1
     set_commit_status
}

if [[ "$BUILD_PSY" == "Y" ]];
then
     build_dovi || exit 1
     build_hdr10plus || exit 1
     build_svt_av1_psy || exit 1
else
     build_svt_av1 || exit 1
fi

build_rav1e() {
     # build rav1e
     git clone --depth "$GIT_DEPTH" https://github.com/xiph/rav1e "$RAV1E_DIR"
     cd "$RAV1E_DIR" || return 1 
     check_for_rebuild && return 0
     rm -rf ffmpeg_build.user && mkdir ffmpeg_build.user || return 1
     source "$HOME/.cargo/env" # for good measure
     cargo clean
     RUSTFLAGS="-C target-cpu=native" ccache cargo cbuild --release
     sudo -E bash -lc "cargo cinstall --prefix=${PREFIX} --release" || return 1
     set_commit_status
}

build_aom_av1() {
     # build aom
     git clone --depth "$GIT_DEPTH" https://aomedia.googlesource.com/aom "$AOM_DIR"
     cd "$AOM_DIR" || return 1 
     check_for_rebuild && return 0
     rm -rf build_aom.user
     mkdir build_aom.user
     cd build_aom.user || return 1
     make clean
     cmake .. -DCMAKE_BUILD_TYPE=Release \
               -DBUILD_SHARED_LIBS=ON \
               -DENABLE_TESTS=OFF \
               -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
               -DCMAKE_C_FLAGS="${LTO_FLAG} -O${OPT_LVL} ${COMP_FLAGS}" \
               -DCMAKE_CXX_FLAGS="${LTO_FLAG} -O${OPT_LVL} ${COMP_FLAGS}" || return 1
     ccache make -j"${THREADS}" || return 1
     sudo make install || return 1
     set_commit_status
}

if [[ "$BUILD_ALL_AV1" == "Y" ]]; then
     build_rav1e || exit 1
     build_aom_av1 || exit 
fi

build_vmaf() {
     # build libvmaf
     git clone --depth "$GIT_DEPTH" https://github.com/Netflix/vmaf "$VMAF_DIR" || \
     cd "$VMAF_DIR/libvmaf" || return 1
     check_for_rebuild && return 0
     python3 -m virtualenv .venv
     (
          source .venv/bin/activate
          rm -rf build.user
          mkdir build.user
          pip install meson
          meson setup . build.user \
               --buildtype release \
               --prefix "${PREFIX}" \
               -Denable_float=true \
               -Db_lto="${LTO_BOOL}" \
               --optimization="$OPT_LVL" \
               -Dc_args="${COMP_FLAGS}" \
               -Dcpp_args="${COMP_FLAGS}" || exit
          ccache ninja -vC build.user || exit
          sudo ninja -vC build.user install || exit
     )
     set_commit_status
}

if [[ "$BUILD_VMAF" == "Y" ]]; then
     build_vmaf || exit 1
fi

build_dav1d() {
     # build dav1d
     git clone --depth "$GIT_DEPTH" https://code.videolan.org/videolan/dav1d.git "$DAV1D_DIR"
     cd "$DAV1D_DIR" || return 1
     check_for_rebuild && return 0
     rm -rf build.user
     mkdir build.user
     meson setup . build.user \
          --buildtype release \
          -Db_lto="${LTO_BOOL}" \
          --prefix "${PREFIX}" \
          --optimization="$OPT_LVL" \
          -Dc_args="${COMP_FLAGS}" \
          -Dcpp_args="${COMP_FLAGS}" || return 1
     ccache ninja -vC build.user || return 1
     sudo ninja -vC build.user install || return 1
     set_commit_status
}

build_opus() {
     # build opus
     git clone --depth "$GIT_DEPTH" https://github.com/xiph/opus.git "$OPUS_DIR"
     cd "$OPUS_DIR" || return 1
     check_for_rebuild && return 0
     ./autogen.sh || return 1
     CFLAGS="-O${OPT_LVL} ${LTO_FLAG} ${COMP_FLAGS}"
     export CFLAGS
     make clean
     ./configure --prefix="${PREFIX}" || return 1
     ccache make -j"${THREADS}" || return 1
     sudo make install || return 1
     unset CFLAGS
     set_commit_status
}

build_dav1d || exit 1
build_opus || exit 1


build_x264() {
     # build x264
     git clone --depth "$GIT_DEPTH" https://code.videolan.org/videolan/x264.git "$X264_DIR"
     cd "$X264_DIR" || return 1
     check_for_rebuild && return 0
     make clean
     ./configure --enable-static \
          --enable-pic \
          --enable-shared "${LTO_CONFIGURE}" \
          --prefix="${PREFIX}" \
          --extra-cflags="-O${OPT_LVL} ${COMP_FLAGS}" || return 1
     ccache make -j"${THREADS}" || return 1
     sudo make install || return 1
     set_commit_status
}

build_x265() {
     # build x265
     git clone --depth "$GIT_DEPTH" https://bitbucket.org/multicoreware/x265_git.git "$X265_DIR"
     cd "$X265_DIR" || return 1
     test -d ".no_git" && mv .no_git .git
     test -d ".git" && check_for_rebuild && return 0
     # x265 is dumb and only generates pkgconfig
     # if git is not there ("release")
     mv .git .no_git
     rm -rf build.user
     mkdir build.user
     cd build.user || return 1
     cmake ../source -DCMAKE_BUILD_TYPE=Release \
               -DNATIVE_BUILD=ON \
               -G "Unix Makefiles" \
               -DHIGH_BIT_DEPTH=ON \
               -DENABLE_HDR10_PLUS=ON \
               -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
               -DEXPORT_C_API=ON \
               -DENABLE_SHARED=ON \
               -DCMAKE_C_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" \
               -DCMAKE_CXX_FLAGS="-O${OPT_LVL} ${COMP_FLAGS}" || return 1
     ccache make -j"${THREADS}" || return 1
     sudo make install || return 1
     cd "$X265_DIR" || return 1
     # revert git
     mv .no_git .git
     set_commit_status
}

build_vpx() {
     # build vpx
     git clone --depth "$GIT_DEPTH" https://chromium.googlesource.com/webm/libvpx.git "$VPX_DIR" || \
     cd "$VPX_DIR" || return 1 
     check_for_rebuild && return 0
     if [[ "$ARCH" == "x86_64" ]]; then
          VP_COMP_FLAGS="${COMP_FLAGS}";
     else
          VP_COMP_FLAGS=""
     fi
     make clean
     ./configure --prefix="${PREFIX}" \
          --extra-cflags="-O${OPT_LVL} $VP_COMP_FLAGS" \
          --extra-cxxflags="-O${OPT_LVL} $VP_COMP_FLAGS" \
          --disable-examples \
          --disable-docs \
          --enable-better-hw-compatibility \
          --enable-shared \
          --enable-ccache \
          --enable-vp8 \
          --enable-vp9 \
          --enable-vp9-highbitdepth
     ccache make -j"${THREADS}" || return 1
     sudo make install || return 1
     set_commit_status
}

if [[ "$BUILD_OTHERS" == "Y" ]]; then
     build_x264 || exit 1
     build_x265 || exit 1
     build_vpx || exit 1
     # # build gtest
     # git clone --depth "$GIT_DEPTH" https://github.com/google/googletest "$GTEST_DIR"
     # cd "$GTEST_DIR" || exit
     # check_for_rebuild
     # rm -rf build
     # mkdir build
     # cd build || exit
     # cmake -DCMAKE_INSTALL_PREFIX="${PREFIX}" ../
     # ccache make -j"${THREADS}"
     # sudo make install
fi

if command -v ldconfig ; then
     # ldconfig for shared libs
     test -d /etc/ld.so.conf.d/ || sudo mkdir /etc/ld.so.conf.d/
     echo -e "${PREFIX}/lib\n${PREFIX}/lib/$(gcc -dumpmachine)" | sudo tee /etc/ld.so.conf.d/ffmpeg.conf || exit 1
     sudo ldconfig
fi

# build ffmpeg
cd "$FFMPEG_DIR/" && check_for_rebuild
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:$PKG_CONFIG_PATH"
make clean

# TODO: remove after HEVC decoding is not broken in master
git checkout e20ee9f9aec94f8cea1bf4fd8ed3fb096fb205e5

./configure --enable-libsvtav1 \
     --prefix="${PREFIX}" \
     --enable-libdav1d \
     --enable-libopus \
     $FFMPEG_CONFIGURE_OPT \
     --arch="$ARCH" \
     --cpu=native \
     --enable-gpl \
     --extra-cflags="-O${OPT_LVL} ${COMP_FLAGS}" \
     --extra-cxxflags="-O${OPT_LVL} ${COMP_FLAGS}" \
     --disable-doc \
     --disable-htmlpages \
     --disable-podpages \
     --disable-txtpages || exit
ccache make -j"${THREADS}" || exit
sudo make install || exit
set_commit_status
sudo cp ff*_g "${PREFIX}/bin/"

# validate encoders
hash -r
source ~/.profile
echo -e "\n"
ffmpeg 2>&1 | grep "configuration"
echo -e "\n  encoders:"
ffmpeg -encoders 2>&1 | grep -E "$GREP_FILTER" | grep -Ev "configuration|wmav1"
echo -e "\n  decoders:"
ffmpeg -decoders 2>&1 | grep -E "$GREP_FILTER" | grep -Ev "configuration|wmav1"
# output for filter/libvmaf
if [[ "$BUILD_VMAF" == "Y" ]]; then
     echo -e "\n  filters:"
     ffmpeg -filters 2> /dev/null | grep libvmaf
fi
exit 0
