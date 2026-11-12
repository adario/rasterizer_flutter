"""Builds and runs the Linux environment of tool/linux/Dockerfile (Debian, Flutter's Linux desktop, gcc & clang, Mesa's
llvmpipe on a virtual display). Commands:
  build                  build the image, rasterizer-linux (~4 GB in Docker Desktop's disk image)
  run [-C DIR] CMD...    sync the repository into the container's copy, then run CMD in DIR (relative to its root)
  shell [-C DIR]         the same, with an interactive bash
  doctor                 flutter doctor -v, and the OpenGL ES renderer (EGL & GLX; llvmpipe here)
  pull PATH              copy PATH (relative to the root) from the container's copy into the checkout, e.g. runners
                         `flutter create` generated or recorded goldens; it adds and updates files, never deletes
  clean                  remove the container's copy, build outputs and pub cache (the volumes), not the image
Add --vnc to run or shell to view the virtual display from the Mac: vnc://localhost:5901 (Screen Sharing), password
rasterizer; --no-sync to keep the container's copy as it is, e.g. with runners `flutter create` generated there. The
checkout is mounted read-only and copied into a volume, without build/, .dart_tool/ or .git, so the container's package
config and hook outputs don't clash with the Mac's. E.g.
  python3 -I tool/linux/linux.py run -C rasterizer_gpu/example flutter build linux"""
import os, subprocess, sys

TOOL = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(TOOL))
IMAGE = 'rasterizer-linux'
VOLUMES = {'rasterizer-linux-work': '/work', 'rasterizer-linux-pub': '/home/dev/.pub-cache'}
# Not copied: the Mac's build outputs, package configs, tool & IDE files
EXCLUDE = ['build/', '.dart_tool/', '.git/', '.idea/', 'Pods/', '.symlinks/', '.gradle/', '.DS_Store',
           '.flutter-plugins', '.flutter-plugins-dependencies']
SYNC = ' '.join(['rsync -a --delete', *(f"--exclude '{e}'" for e in EXCLUDE), '/src/ /work/'])


def docker(*args):
    return subprocess.call(['docker', *args])


def run(cmd, d='.', vnc=False, interactive=False, sync=True):
    args = ['run', '--rm', '-v', f'{ROOT}:/src:ro']
    for name, path in VOLUMES.items():
        args += ['-v', f'{name}:{path}']
    if vnc:
        # Only on the Mac's loopback; 5901, as the Mac's own Screen Sharing service may have 5900
        args += ['-e', 'VNC=1', '-p', '127.0.0.1:5901:5900']
    if interactive:
        args.append('-it')
    # The shell starts in / so that rsync can replace /work's contents, then goes to DIR. Excluded paths are kept in
    # /work, so the container's own build outputs survive each sync
    script = f'{SYNC + " && " if sync else ""}cd /work/{d} && exec "$@"'
    return docker(*args, '-w', '/', IMAGE, 'sh', '-c', script, 'sh', *cmd)


def pull(path):
    path = os.path.normpath(path)
    if os.path.isabs(path) or path.split(os.sep)[0] in ('..', '.'):
        sys.exit(f'pull: {path} must be inside the repository')
    # The checkout is mounted writable for this one command. A directory's build outputs aren't copied
    script = ('if [ -d "/work/$1" ]; then mkdir -p "/src/$1" && rsync -a --exclude build/ --exclude .dart_tool/ '
              '"/work/$1/" "/src/$1/"; else rsync -a "/work/$1" "/src/$1"; fi')
    return docker('run', '--rm', '-v', f'{ROOT}:/src', '-v', 'rasterizer-linux-work:/work', '-w', '/', IMAGE,
                  'sh', '-c', script, 'sh', path)


def main(argv):
    if not argv:
        sys.exit(__doc__)
    command, rest = argv[0], argv[1:]
    vnc, sync = '--vnc' in rest, '--no-sync' not in rest
    rest = [a for a in rest if a not in ('--vnc', '--no-sync')]
    d = '.'
    if rest[:1] == ['-C']:
        d, rest = rest[1], rest[2:]
    if command == 'build':
        return docker('build', '-t', IMAGE, *rest, TOOL)
    if command == 'run' and rest:
        return run(rest, d, vnc, sync=sync)
    if command == 'shell':
        return run(['bash'], d, vnc, interactive=sys.stdin.isatty(), sync=sync)
    if command == 'doctor':
        return run(['sh', '-c', 'flutter doctor -v; eglinfo -B 2>&1 | grep -i -m4 "renderer\\|version"; '
                                'glxinfo -B | grep -i "renderer\\|version"'])
    if command == 'pull' and len(rest) == 1:
        return pull(rest[0])
    if command == 'clean':
        return docker('volume', 'rm', '-f', *VOLUMES)
    sys.exit(__doc__)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
