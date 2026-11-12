"""Screenshots a page in headless Chrome, with a scratch profile, and prints the page's console lines and errors: the web
smoke check, for an example built for web.

  flutter build web [--wasm]                     # in rasterizer_gpu/example/
  python3 -m http.server -d build/web 8000       # in another shell
  python3 -I ../../tool/web_shot.py http://localhost:8000 tiger.png

The page runs in virtual time, for BUDGET ms of it (default 20000); `t<ms>` runs it in real time instead, for at most
that long, or until a console line matches UNTIL, a regular expression, then screenshots it through Chrome's DevTools
protocol. Pages that wait for frames, such as flame_rasterizer's check, need real time: in virtual time their frames
never come. Chrome is CHROME_EXECUTABLE, as for Flutter, or else the default macOS install.

usage: python3 -I web_shot.py URL OUT.png [BUDGET | t<ms> [UNTIL]]
"""
import base64
import json
import os
import re
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'


def _printed(line):
    """Whether a line of Chrome's log is one to print: the page's console, or an error."""
    return ('CONSOLE' in line or 'ERROR' in line) and 'cv_display_link' not in line


def _virtual_time(chrome, profile, url, out, budget):
    r = subprocess.run([chrome, '--headless=new', f'--user-data-dir={profile}', '--window-size=1024,768',
                        f'--virtual-time-budget={budget}', '--enable-logging=stderr', '--v=0',
                        f'--screenshot={os.path.abspath(out)}', url], capture_output=True, text=True, timeout=120)
    for line in r.stderr.splitlines():
        if _printed(line):
            print(line[:400])
    return r.returncode


def _devtools_call(ws_url, method):
    """Calls a DevTools method on a page's WebSocket, with no parameters, and returns its result."""
    host, port, path = re.match(r'ws://([^:/]+):(\d+)(/.*)', ws_url).groups()
    with socket.create_connection((host, int(port)), timeout=30) as s:
        key = base64.b64encode(os.urandom(16)).decode()
        s.sendall((f'GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                   f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
        buffer = b''
        while b'\r\n\r\n' not in buffer:
            buffer += s.recv(4096)
        header, buffer = buffer.split(b'\r\n\r\n', 1)
        if b' 101 ' not in header.split(b'\r\n')[0]:
            raise RuntimeError(header.decode(errors='replace'))

        def read(n):
            nonlocal buffer
            while len(buffer) < n:
                chunk = s.recv(1 << 16)
                if not chunk:
                    raise RuntimeError('DevTools closed the connection')
                buffer += chunk
            data, buffer = buffer[:n], buffer[n:]
            return data

        # A client's frames are masked, a server's aren't.
        payload = json.dumps({'id': 1, 'method': method}).encode()
        mask = os.urandom(4)
        length = (struct.pack('!B', 0x80 | len(payload)) if len(payload) < 126
                  else struct.pack('!BH', 0x80 | 126, len(payload)))
        s.sendall(b'\x81' + length + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
        message = b''
        while True:
            first, second = read(2)
            n = second & 0x7f
            if n == 126:
                n = struct.unpack('!H', read(2))[0]
            elif n == 127:
                n = struct.unpack('!Q', read(8))[0]
            message += read(n)
            if not first & 0x80:
                continue  # A fragment: more follow.
            reply, message = json.loads(message), b''
            if reply.get('id') == 1:
                if 'error' in reply:
                    raise RuntimeError(reply['error'])
                return reply['result']


def _real_time(chrome, profile, url, out, ms, until):
    p = subprocess.Popen([chrome, '--headless=new', f'--user-data-dir={profile}', '--window-size=1024,768',
                          '--remote-debugging-port=0', '--enable-logging=stderr', '--v=0', url],
                         stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    try:
        os.set_blocking(p.stderr.fileno(), False)
        deadline, matched = time.time() + ms / 1000, False
        while time.time() < deadline and not matched and p.poll() is None:
            line = p.stderr.readline()
            if not line:
                time.sleep(0.1)
                continue
            if _printed(line):
                print(line.rstrip()[:400], flush=True)
                matched = until is not None and re.search(until, line) is not None
        if p.poll() is not None:
            return p.returncode
        # Chrome writes the port it picked into the profile.
        with open(os.path.join(profile, 'DevToolsActivePort')) as f:
            port = f.readline().strip()
        with urllib.request.urlopen(f'http://127.0.0.1:{port}/json/list') as r:
            page = next(t for t in json.load(r) if t['type'] == 'page')
        png = _devtools_call(page['webSocketDebuggerUrl'], 'Page.captureScreenshot')['data']
        with open(out, 'wb') as f:
            f.write(base64.b64decode(png))
        return 0 if until is None or matched else 1
    finally:
        p.kill()
        p.wait()


def main(url, out, budget='20000', until=None):
    chrome = os.environ.get('CHROME_EXECUTABLE', CHROME)
    with tempfile.TemporaryDirectory() as profile:
        if budget.startswith('t'):
            code = _real_time(chrome, profile, url, out, int(budget[1:]), until)
        else:
            code = _virtual_time(chrome, profile, url, out, budget)
    print('exit', code, 'png', os.path.getsize(out) if os.path.exists(out) else None)
    return code


if __name__ == '__main__':
    if len(sys.argv) not in (3, 4, 5) or (len(sys.argv) == 5 and not sys.argv[3].startswith('t')):
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
