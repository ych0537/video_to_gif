#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FFMPEG_VERSION:-7.1.1}"
BUILD_ROOT="$ROOT_DIR/.build/ffmpeg-arm64"
PREFIX="$ROOT_DIR/Vendor/ffmpeg/arm64"
TARBALL="$BUILD_ROOT/ffmpeg-$VERSION.tar.xz"
SOURCE_DIR="$BUILD_ROOT/ffmpeg-$VERSION"
URL="https://ffmpeg.org/releases/ffmpeg-$VERSION.tar.xz"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This bundled ffmpeg build only supports Apple Silicon Macs." >&2
  exit 1
fi

mkdir -p "$BUILD_ROOT" "$PREFIX"

if [[ ! -f "$TARBALL" ]]; then
  curl -L "$URL" -o "$TARBALL"
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  tar -xf "$TARBALL" -C "$BUILD_ROOT"
fi

cd "$SOURCE_DIR"

make distclean >/dev/null 2>&1 || true

./configure \
  --prefix="$PREFIX" \
  --arch=arm64 \
  --target-os=darwin \
  --cc=clang \
  --enable-small \
  --disable-autodetect \
  --disable-debug \
  --disable-doc \
  --disable-network \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-everything \
  --enable-zlib \
  --enable-avcodec \
  --enable-avformat \
  --enable-avfilter \
  --enable-swscale \
  --enable-protocol=file,pipe \
  --enable-demuxer=mov,matroska,avi,flv,asf,mpegts,mpegvideo,image2 \
  --enable-muxer=gif,image2 \
  --enable-decoder=h264,hevc,mpeg4,mpegvideo,msmpeg4v1,msmpeg4v2,msmpeg4v3,wmv1,wmv2,wmv3,vc1,flv,vp8,vp9,av1,prores,qtrle,png \
  --enable-parser=h264,hevc,mpeg4video,mpegvideo,vp8,vp9,av1 \
  --enable-encoder=gif,png \
  --enable-filter=fps,scale,palettegen,paletteuse

make -j"$(sysctl -n hw.ncpu)"
make install
rm -rf "$PREFIX/include" "$PREFIX/lib" "$PREFIX/share"
strip "$PREFIX/bin/ffmpeg" || true

"$PREFIX/bin/ffmpeg" -hide_banner -version
du -h "$PREFIX/bin/ffmpeg"
