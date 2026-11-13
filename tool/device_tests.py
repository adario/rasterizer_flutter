"""Runs integration tests, one `flutter test` per NAME:DIR:ENV:TEST[:DEVICE] argument, each under a stall watchdog, and
prints one event line per test's pass or failure, each summary, `RASTERIZER` lines, and STALL if a run is silent for
120 s once its tests have started (600 s before, for the build), killing it then. FINISHED at the end.
It stops at the first unexpected failure: a test failing, a STALL or a non-zero exit kills the run at once and prints
STOPPED, with the step, the test, its log and the steps not run, and exits with 1. `--expect=NAME:REGEX` makes the
failure of NAME's tests whose names match REGEX expected: EXPECTED FAIL, and the run goes on. `--keep-going` runs
every step whatever fails.
- DIR is relative to the repository's root, e.g. rasterizer_gpu/example or flame_rasterizer/benchmark.
- ENV is one variable for the build, e.g. IMPELLER_BACKEND=vulkan or IMPELLER_BACKEND=opengles for the emulator's
  Vulkan or OpenGL ES, or empty, for Flutter's own pick: OpenGL ES on the emulator.
- TEST is the test file, with any flutter test flags, e.g. 'integration_test/golden_test.dart --dart-define=BACKEND=gpu'.
- DEVICE defaults to emulator-5554: macos, an iPhone's UDID, or chrome, otherwise. With chrome, the test runs on web,
  in headless Chrome, with `flutter drive` and the app's test_driver/integration_test.dart, through the chromedriver in
  the repository's build/chromedriver/ (Chrome for Testing's, of the installed Chrome's version), started for the run;
  add --wasm to TEST for skwasm rather than CanvasKit. flutter drive reports the tests only once they're all done, so
  a failure stops the run at the end of its step, and the build and run are under the 600 s watchdog. It reports only
  widget tests' failures: a plain `test` that fails passes there, so tests run on web use testWidgets (the rasterizer_gpu
  example's integration_test/web_test.dart). The tests'
  `binding.reportData` is saved next to the log, as NAME.json, and its `images`, PNGs in base64 by path, as golden_test
  writes them on web, into the folder NAME/. Keep the Mac awake: asleep, even under `caffeinate -i` (on battery, or
  with the lid closed), it only runs in its short dark wakes, so the build takes many times as long, and flutter drive
  loses the browser (`invalid session id`) or times out after 20 minutes, with no test failing.
Each run's full output goes to the repository's build/test_logs/NAME.log. Run from anywhere, in the background,
writing its events to a file, and follow it with tool/follow.py:
  python3 -I tool/device_tests.py gles_selftest:rasterizer_gpu/example:IMPELLER_BACKEND=opengles:integration_test/self_test_test.dart > e.txt
tool/matrix.py runs the usual matrix through it."""
import base64, json, os, platform, re, signal, subprocess, sys, threading, time

TOOL = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOL)
LOGS = os.path.join(ROOT, 'build', 'test_logs')
# Chrome for Testing's archive for this machine.
_CFT = {'darwin': 'mac-arm64' if platform.machine() == 'arm64' else 'mac-x64',
        'linux': 'linux64'}.get(sys.platform, 'win64')
CHROMEDRIVER = os.path.join(ROOT, 'build', 'chromedriver', f'chromedriver-{_CFT}',
                            'chromedriver.exe' if _CFT == 'win64' else 'chromedriver')
STALL_S, BUILD_S = 120, 600
progress = re.compile(r'^(\d\d:\d\d) \+(\d+)(?: ~\d+)?(?: -(\d+))?: (.*)$')
# flutter drive's lines, on web: a failing test's, then the summary
web_failure = re.compile(r'^Failure in method: (.*)$')


def say(s):
    print(s, flush=True)


def run(name, d, env, test, device='emulator-5554', expected=None, keep_going=False):
    """Runs one step; returns None, or why it stopped."""
    os.makedirs(LOGS, exist_ok=True)
    log = open(os.path.join(LOGS, f'{name}.log'), 'w', buffering=1)
    environ = dict(os.environ)
    if env:
        k, v = env.split('=', 1)
        environ[k] = v
    web = device == 'chrome'
    if web:
        target, *flags = test.split()
        command = ['flutter', 'drive', '--driver=test_driver/integration_test.dart', f'--target={target}', *flags,
                   '-d', 'web-server', '--browser-name=chrome', '--headless']
        data = os.path.join(ROOT, d, 'build', 'integration_response_data.json')
        if os.path.exists(data):
            os.remove(data)
        driver = subprocess.Popen([CHROMEDRIVER, '--port=4444'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1)
    else:
        command = ['flutter', 'test', *test.split(), '-d', device]
    p = subprocess.Popen(command, cwd=os.path.join(ROOT, d), env=environ, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True, bufsize=1, start_new_session=True)
    state = {'last': time.monotonic(), 'started': False, 'stalled': False}

    def watch():
        while p.poll() is None:
            time.sleep(1)
            limit = STALL_S if state['started'] else BUILD_S
            if time.monotonic() - state['last'] > limit:
                state['stalled'] = True
                say(f'{name} STALL after {limit:.0f} s of silence')
                os.killpg(p.pid, signal.SIGKILL)
                return

    threading.Thread(target=watch, daemon=True).start()
    prev, expected_fails, stop = (0, 0), 0, None
    for line in p.stdout:
        log.write(line)
        state['last'] = time.monotonic()
        m = progress.match(line.strip())
        f = web_failure.match(line.strip()) if web else None
        if f:
            prev = (prev[0], prev[1] + 1)
            if expected and expected.search(f.group(1)):
                expected_fails += 1
                say(f'{name} EXPECTED FAIL {f.group(1)}')
            else:
                say(f'{name} FAIL {f.group(1)}')
                if not keep_going:
                    stop = f'test failed: {f.group(1)}'
        elif web and line.startswith('All tests passed'):
            say(f'{name} {line.strip()}')
        elif m:
            passed, failed = int(m.group(2)), int(m.group(3) or 0)
            # flutter's `loading <file>` line comes before the build, which is silent
            if 'loading' not in m.group(4):
                state['started'] = True
            # The line naming the test that starts next: the one before it passed
            if passed > prev[0]:
                say(f'{name} {m.group(1)} PASS (+{passed}) before: {m.group(4)}')
            if failed > prev[1]:
                if expected and expected.search(m.group(4)):
                    expected_fails += failed - prev[1]
                    say(f'{name} {m.group(1)} EXPECTED FAIL {m.group(4)}')
                else:
                    say(f'{name} {m.group(1)} FAIL {m.group(4)}')
                    if not keep_going:
                        stop = f'test failed: {m.group(4)}'
                        os.killpg(p.pid, signal.SIGKILL)
                        break
            prev = (passed, failed)
            if 'All tests passed' in line or 'Some tests failed' in line:
                say(f'{name} {line.strip()}')
        elif 'RASTERIZER' in line:
            say(f'{name} {line.strip()[:300]}')
    p.wait()
    if web:
        driver.kill()
        if os.path.exists(data):
            saved = os.path.join(LOGS, f'{name}.json')
            os.replace(data, saved)
            with open(saved) as f:
                images = (json.load(f) or {}).get('images') or {}
            for path, png in images.items():
                out = os.path.join(LOGS, name, path)
                os.makedirs(os.path.dirname(out), exist_ok=True)
                with open(out, 'wb') as f:
                    f.write(base64.b64decode(png))
    if state['stalled']:
        return 'STALL'
    if stop:
        return stop
    say(f'{name} exit {p.returncode}')
    # flutter exits with 1 when any test failed, expected ones too
    if p.returncode and not (p.returncode == 1 and prev[1] and prev[1] == expected_fails):
        return f'exit {p.returncode}'


args = [a for a in sys.argv[1:] if not a.startswith('--')]
keep_going = '--keep-going' in sys.argv[1:]
expect = {}
for a in sys.argv[1:]:
    if a.startswith('--expect='):
        k, pattern = a[len('--expect='):].split(':', 1)
        expect[k] = re.compile(pattern)
for i, arg in enumerate(args):
    name, *rest = arg.split(':')
    why = run(name, *rest, expected=expect.get(name), keep_going=keep_going)
    if why and not keep_going:
        left = ' '.join(a.split(':')[0] for a in args[i + 1:]) or 'none'
        say(f'STOPPED at {name}: {why}; log {os.path.join(LOGS, name + ".log")}; not run: {left}')
        sys.exit(1)
say('FINISHED')
