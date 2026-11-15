#!/bin/sh
# Starts a virtual display, Xvfb on :99, and with VNC=1 a VNC server on it (port 5900, password rasterizer), then runs
# the command. Xvfb's OpenGL ES is Mesa's llvmpipe. With WAYLAND=1, weston runs in a window on Xvfb, so VNC shows it,
# and GTK apps draw on its Wayland display, as on most Linux desktops, where Flutter draws into a subsurface. Their
# OpenGL ES is llvmpipe too.
set -e
Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp > /tmp/xvfb.log 2>&1 &
export DISPLAY=:99
i=0
while [ ! -e /tmp/.X11-unix/X99 ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
if [ "$VNC" = 1 ]; then
  x11vnc -display :99 -rfbport 5900 -passwd rasterizer -forever -shared -quiet -bg -o /tmp/x11vnc.log
fi
if [ "$WAYLAND" = 1 ]; then
  export XDG_RUNTIME_DIR=/tmp/xdg WAYLAND_DISPLAY=wayland-1 GDK_BACKEND=wayland
  mkdir -p -m 700 "$XDG_RUNTIME_DIR"
  weston --backend=x11 --renderer=pixman --socket="$WAYLAND_DISPLAY" --width=1280 --height=1024 \
    > /tmp/weston.log 2>&1 &
  i=0
  while [ ! -e "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
fi
exec "$@"
