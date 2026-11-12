"""Runs the check on web, as integration_test/check_test.dart does elsewhere: for each renderer, CanvasKit (js) or skwasm
(wasm), and each time, builds the benchmark with MODE=check, serves build/web locally, and runs it in headless Chrome with
the repository's tool/web_shot.py, in real time, until it logs its FLAME_RASTERIZER check line, which is printed.
Screenshots go to build/web_check/. Exits with 1 unless every check passed.

usage: python3 -I tool/web_check.py [js,wasm] [0.0,3.7,8.0,15.0]
"""
import os
import re
import socket
import subprocess
import sys
import time
import urllib.request

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOT = os.path.join(APP, '..', '..', 'tool', 'web_shot.py')


def free_port():
    """A port no server listens on now."""
    with socket.socket() as s:
        s.bind(('localhost', 0))
        return s.getsockname()[1]


def serving(url, server, seconds=10):
    """Whether the server answers at url, waiting for it up to seconds, unless it exits."""
    end = time.time() + seconds
    while time.time() < end and server.poll() is None:
        try:
            with urllib.request.urlopen(url, timeout=1):
                return True
        except OSError:
            time.sleep(0.2)
    return False


def check(renderer, t):
    """The check's line for a renderer and time, or why there's none."""
    command = ['flutter', 'build', 'web', '--dart-define=MODE=check', f'--dart-define=CHECK_TIME={t}']
    if renderer == 'wasm':
        command.append('--wasm')
    b = subprocess.run(command, cwd=APP, capture_output=True, text=True)
    if b.returncode != 0:
        return 'BUILD FAILED\n' + (b.stdout + b.stderr)[-2000:]
    # A free port, and the build checked to answer on it, rather than another server.
    port = free_port()
    url = f'http://localhost:{port}'
    server = subprocess.Popen([sys.executable, '-I', '-m', 'http.server', '-b', 'localhost', '-d',
                               os.path.join(APP, 'build', 'web'), str(port)], stdout=subprocess.DEVNULL,
                              stderr=subprocess.PIPE, text=True)
    try:
        if not serving(url, server):
            server.terminate()
            return 'SERVER FAILED\n' + server.communicate()[1][-2000:]
        png = os.path.join(APP, 'build', 'web_check', f'{renderer}_{t}.png')
        s = subprocess.run([sys.executable, '-I', SHOT, url, png, 't90000',
                            r'FLAME_RASTERIZER check (PASS|FAIL)'], capture_output=True, text=True)
    finally:
        server.terminate()
        server.wait()
    # Chrome's log line, without its prefix and the console call's source.
    lines = [re.sub(r'.*(FLAME_RASTERIZER check.*?)(", source: .*)?$', r'\1', l) for l in s.stdout.splitlines()
             if 'FLAME_RASTERIZER check' in l]
    return lines[-1] if lines else 'NO RESULT\n' + (s.stdout + s.stderr)[-2000:]


def main(renderers='js,wasm', times='0.0,3.7,8.0,15.0'):
    os.makedirs(os.path.join(APP, 'build', 'web_check'), exist_ok=True)
    passed = True
    for renderer in renderers.split(','):
        for t in times.split(','):
            result = check(renderer, t)
            passed = passed and 'check PASS' in result
            print(f'{renderer} {t}: {result}', flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    if len(sys.argv) > 3:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
