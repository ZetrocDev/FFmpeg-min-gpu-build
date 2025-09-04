script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir=$script_dir/win64

temp_dir=$HOME/ffmpeg-tmp
mkdir $temp_dir

pacman -Syu --noconfirm --needed \
    && pacman -S --noconfirm --needed base-devel git yasm nasm pkgconf cmake mingw-w64-gcc mingw-w64-headers mingw-w64-crt mingw-w64-winpthreads ninja wget \
    && pacman -Scc --noconfirm --needed
    
CROSS_PREFIX="/usr/x86_64-w64-mingw32"
export PKG_CONFIG_PATH="$CROSS_PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$CROSS_PREFIX/lib/pkgconfig"

mkdir $temp_dir
cd $temp_dir

#Create $temp_dir/toolchain.cmake for cross-compile
cat > "$temp_dir/toolchain.cmake" << 'EOF'
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_SYSTEM_VERSION 6.1)
set(triple x86_64-w64-mingw32)
set(CMAKE_C_COMPILER ${triple}-gcc)
set(CMAKE_CXX_COMPILER ${triple}-g++)
set(CMAKE_RC_COMPILER ${triple}-windres)
set(CMAKE_RANLIB ${triple}-gcc-ranlib)
set(CMAKE_AR ${triple}-gcc-ar)
set(CMAKE_SYSROOT /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH /usr/x86_64-w64-mingw32)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

#LIBOPUS
git clone https://github.com/xiph/opus.git
cd opus
./autogen.sh
./configure --host=x86_64-w64-mingw32 --prefix="$CROSS_PREFIX" --disable-shared --enable-static
make -j$(nproc)
make install

cd $temp_dir

# LIBX264
git clone --depth 1 https://code.videolan.org/videolan/x264.git
cd $temp_dir/x264

./configure \
        --host=x86_64-w64-mingw32 \
        --cross-prefix=x86_64-w64-mingw32- \
        --enable-static \
        --disable-cli \
        --prefix="$CROSS_PREFIX"

make -j8
make install

#NVENC
cd $temp_dir
git clone --depth 1 https://github.com/FFmpeg/nv-codec-headers.git nv
cd $temp_dir/nv
make install PREFIX="$CROSS_PREFIX"

#VPL
cd $temp_dir
git clone --depth 1 https://github.com/intel/libvpl.git
cd $temp_dir/libvpl
git checkout 3591aa94dfbdf4566cd19f3e976ae5b769ab4fa2

mkdir build
cd build

cmake .. -GNinja \
        -DCMAKE_TOOLCHAIN_FILE=$temp_dir/toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$CROSS_PREFIX" \
        -DBUILD_DISPATCHER=ON \
        -DBUILD_DEV=ON \
        -DBUILD_PREVIEW=OFF \
        -DBUILD_TOOLS=OFF \
        -DBUILD_TOOLS_ONEVPL_EXPERIMENTAL=OFF \
        -DINSTALL_EXAMPLE_CODE=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTS=OFF
        
ninja -j8
ninja install

#patch vpl.pc for static cross-compile
rm "$CROSS_PREFIX/lib/pkgconfig/vpl.pc"
cat > "$CROSS_PREFIX/lib/pkgconfig/vpl.pc" << 'EOF'
prefix=/usr/x86_64-w64-mingw32
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: vpl
Description: Intel Video Processing Library
Version: 2.13.0
Libs: -L${libdir} -lvpl -lstdc++ -lole32 -lsetupapi -luuid -lm -static-libgcc -static-libstdc++
Cflags: -I${includedir} -I${includedir}/vpl
EOF

#AMF
cd $temp_dir
git clone https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git
mkdir -p "$CROSS_PREFIX/include/AMF"
cp -r AMF/amf/public/include/* "$CROSS_PREFIX/include/AMF/"

cd $temp_dir
wget https://www.ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz
tar -xf ffmpeg-7.1.1.tar.xz
cd ffmpeg-7.1.1

mkdir $temp_dir/build

./configure \
     --prefix=$temp_dir/build \
    --target-os=mingw32 \
    --arch=x86_64 \
    --cross-prefix=x86_64-w64-mingw32- \
    --disable-everything \
    --disable-autodetect \
    --disable-programs \
    --disable-pthreads \
    --enable-w32threads \
    --disable-network \
    --disable-doc \
    --disable-avfilter \
    --disable-swscale \
    --disable-swresample \
    --disable-avformat \
    --disable-postproc \
    --enable-gpl \
    --enable-libx264 \
    --enable-encoder=libx264 \
    --enable-encoder=libopus \
    --enable-libopus \
    --enable-d3d11va \
    --enable-nvenc \
    --enable-ffnvcodec \
    --enable-encoder=h264_nvenc \
    --enable-encoder=h264_qsv \
    --enable-amf \
    --enable-encoder=h264_amf \
    --enable-libvpl \
    --pkg-config=pkg-config \
    --pkg-config-flags="--static" \
    --extra-cflags="-I$CROSS_PREFIX/include -static-libgcc -static-libstdc++" \
    --extra-ldflags="-L$CROSS_PREFIX/lib -lvpl -lole32 -lsetupapi -luuid -lm -static-libgcc -static-libstdc++" \
    --enable-shared \
    --disable-static

make -j"$(nproc)"
make install

mkdir $target_dir
cp -R $temp_dir/build/bin/*.dll $target_dir
cp /usr/x86_64-w64-mingw32/bin/libwinpthread-1.dll $target_dir
cp /usr/x86_64-w64-mingw32/bin/libstdc++-6.dll $target_dir
cp /usr/x86_64-w64-mingw32/bin/libgcc_s_seh-1.dll $target_dir

rm -rf $temp_dir