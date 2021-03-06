./configure \
  --prefix="$HOME/ffmpeg_build" \
  --pkg-config-flags="--static" \
  --extra-cflags="-I$HOME/ffmpeg_build/include" \
  --extra-ldflags="-L$HOME/ffmpeg_build/lib" \
  --extra-libs="-lpthread -lm" \
  --ld="g++" \
  --bindir="$HOME/bin" \
  --disable-everything \
  --disable-doc \
  --disable-alsa \
  --disable-filters \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-error-resilience \
  --disable-pixelutils \
  --enable-small \
  --disable-runtime-cpudetect \
  --enable-gpl \
  --enable-gnutls \
  --enable-libfdk-aac \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libvorbis \
  --enable-filter=aresample \
  --enable-muxer=pcm_s16le \
  --enable-demuxer=aac,mp3,ogg,mpegaudio,webm_dash_manifest,flv,mov,hls,wtv \
  --enable-decoder=aac,vorbis,mp3,opus \
  --enable-parser=aac,vorbis,opus \
  --enable-encoder=pcm_s16le \
  --enable-protocol=file,http,https,pipe \
  --enable-nonfree
