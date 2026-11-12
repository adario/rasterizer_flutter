# A Linux environment for the plugin: Flutter's Linux desktop toolchain, the C/C++ compilers for the core, and a
# virtual display whose OpenGL ES is Mesa's software renderer, llvmpipe. Built and run by tool/linux/linux.py.
# Arch-neutral: built here it's linux/arm64; on an x86_64 Linux machine, linux/amd64.
FROM debian:trixie-slim

# Flutter's Linux desktop requirements, gcc & clang, Mesa (EGL, OpenGL ES, llvmpipe) & its info tools, Xvfb & x11vnc
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils file rsync procps \
      clang g++ cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
      libegl1 libgles2 libgl1-mesa-dri mesa-utils \
      xvfb xauth x11vnc \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash dev \
    && mkdir -p /opt/flutter /work /home/dev/.pub-cache \
    && chown dev:dev /opt/flutter /work /home/dev/.pub-cache
USER dev

# The same Flutter as on the Mac (~/Applications/flutter/version), with the Linux host's artifacts and the universal ones
# (fonts, sky_engine, flutter_gpu, the engine): otherwise each `docker run --rm` downloads them again
ARG FLUTTER_VERSION=3.47.9
ENV PATH=/opt/flutter/bin:$PATH PUB_CACHE=/home/dev/.pub-cache
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter \
    && flutter --disable-analytics \
    && dart --disable-analytics \
    && flutter config --enable-linux-desktop --no-enable-android --no-enable-web \
    && flutter precache --linux --no-android --no-ios --no-web --no-macos --no-windows --no-fuchsia \
    && flutter --version

# Mesa's default on Xvfb, made explicit: rasterizer_gpu's example reads it to pick the linux_llvmpipe golden set
ENV GALLIUM_DRIVER=llvmpipe
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
