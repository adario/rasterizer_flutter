"""Prints the lines of FILE matching PATTERN as they're written, and exits once a line matches END, or after LIMIT seconds
(590 by default). For the events files of tool/device_tests.py and
rasterizer_gpu/example/tool/release_launches.py, run in the background; unlike `tail -f`, it exits by itself.
  python3 -I tool/follow.py FILE PATTERN END [LIMIT]
e.g. python3 -I tool/follow.py e.txt 'STALL|PASS|FAIL|exit|FINISHED' FINISHED"""
import os, re, sys, time

path, pattern, end = sys.argv[1], re.compile(sys.argv[2]), re.compile(sys.argv[3])
limit = float(sys.argv[4]) if len(sys.argv) > 4 else 590
deadline = time.monotonic() + limit
while not os.path.exists(path) and time.monotonic() < deadline:
    time.sleep(0.5)
with open(path) as f:
    while time.monotonic() < deadline:
        line = f.readline()
        if not line:
            time.sleep(0.5)
            continue
        if pattern.search(line):
            print(line.rstrip(), flush=True)
        if end.search(line):
            sys.exit(0)
print('FOLLOW timed out', flush=True)
