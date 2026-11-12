"""Release runs on the Android emulator, whose release builds use its OpenGL ES: the example's atlas page (which renders
every frame, so its probation ends) launched with adb, each launch printing its `RASTERIZER_EXAMPLE support` line, or
how it was killed, to check what the self-test remembers across launches (RasterizerGpu.rememberSelfTest).
Kills: `fg` force-stops the app the moment it logs its first rasterized frame, as the self-test's warm-up starts; `bg`
sends it Home then, and force-stops it 3 s later, in the background; `switch` force-stops it 2 s after its support line
says it switched to the GPU renderer, during the probation; `switch-bg` sends it Home then, and force-stops it 3 s later;
`probation` force-stops it once it logs the probation's end. A kill that came too late (the self-test, or the probation,
had finished) is marked MISSED. Other launches end in the background (Home, then a force-stop), which counts for nothing.
The sequence:
  1. a first launch: the self-test runs and passes;
  2. killed twice in the foreground during the self-test, then launched twice: remembered as a failure;
  3. an upgrade (adb install -r) clears it: the self-test runs again;
  4. killed twice in the background during the self-test, then launched: not remembered;
  5. killed twice in the foreground during the probation, then launched twice: remembered, "after the switch";
  6. an upgrade clears it; killed twice after the probation, then launched: not remembered;
  7. killed twice in the background during the probation, then launched: not remembered.
Run from anywhere, with adb and flutter on the PATH; `build` builds the release APK first:
  python3 -I tool/release_launches.py [build]"""
import os, shutil, subprocess, sys, time


def find_adb():
    """adb from $ANDROID_HOME, else $ANDROID_SDK_ROOT, else PATH, else the Android SDK's macOS default folder."""
    for var in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        sdk = os.environ.get(var)
        if sdk and os.path.isfile(os.path.join(sdk, 'platform-tools', 'adb')):
            return os.path.join(sdk, 'platform-tools', 'adb')
    return shutil.which('adb') or os.path.expanduser('~/Library/Android/sdk/platform-tools/adb')


ADB = find_adb()
EX = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG = 'dev.rasterizer.rasterizer_gpu_example'
APK = os.path.join(EX, 'build/app/outputs/flutter-apk/app-release.apk')


def adb(*args):
    return subprocess.run([ADB, *args], capture_output=True, text=True).stdout


def say(s):
    print(s, flush=True)


def install():
    say('INSTALL -r: ' + adb('install', '-r', APK).strip().splitlines()[-1])


def launch(kill=None, limit=30):
    adb('shell', 'am', 'force-stop', PKG)
    adb('logcat', '-c')
    log = subprocess.Popen([ADB, 'logcat', '-v', 'raw', '-s', 'flutter:I'], stdout=subprocess.PIPE, text=True, bufsize=1)
    adb('shell', 'am', 'start', '-n', f'{PKG}/.MainActivity')
    start, result = time.monotonic(), None
    try:
        for line in log.stdout:
            line = line.strip()
            if 'first frame rasterized' in line and kill in ('fg', 'bg'):
                if kill == 'bg':
                    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
                    time.sleep(3)
                adb('shell', 'am', 'force-stop', PKG)
                result = (f'killed in the foreground at its first rasterized frame ({line})' if kill == 'fg' else
                          f'sent Home at its first rasterized frame, killed 3 s later ({line})')
                break
            if 'RASTERIZER_EXAMPLE support' in line and kill in ('switch', 'switch-bg'):
                if 'backend gpu' not in line:
                    result = f'NOT SWITCHED: {line}'
                    break
                if kill == 'switch':
                    time.sleep(2)
                else:
                    adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
                    time.sleep(3)
                adb('shell', 'am', 'force-stop', PKG)
                result = (f'killed in the foreground 2 s after the switch ({line})' if kill == 'switch' else
                          f'sent Home at the switch, killed 3 s later ({line})')
                break
            if 'probation ended' in line and kill == 'probation':
                adb('shell', 'am', 'force-stop', PKG)
                result = f'killed in the foreground after the probation ({line})'
                break
            if 'RASTERIZER_EXAMPLE support' in line and not kill:
                result = line
                break
            if time.monotonic() - start > limit:
                result = 'TIMEOUT'
                break
    finally:
        log.kill()
    # A support line, or the probation's end, logged before the kill means the kill came too late
    time.sleep(1)
    marker = {'fg': 'RASTERIZER_EXAMPLE support', 'bg': 'RASTERIZER_EXAMPLE support', 'switch': 'probation ended',
              'switch-bg': 'probation ended'}.get(kill)
    late = [l for l in adb('logcat', '-d', '-v', 'raw', '-s', 'flutter:I').splitlines() if marker and marker in l]
    if late:
        result += f'  [MISSED: {late[0].strip()}]'
    if not kill:
        # Ended in the background, so that the launch counts for nothing (a kill in the foreground during the
        # probation would count).
        adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
        time.sleep(2)
    adb('shell', 'am', 'force-stop', PKG)
    say(f'LAUNCH {kill or "plain"}: {result}')


if sys.argv[1:] == ['build']:
    b = subprocess.run(['flutter', 'build', 'apk', '--release', '--target-platform', 'android-arm64',
                        '--dart-define=PAGE=atlas', '--dart-define=ENTRIES=100'], cwd=EX, capture_output=True, text=True)
    say('BUILD ' + (b.stdout + b.stderr).strip().splitlines()[-1])
install()
say('-- 1. a first launch: the self-test runs and passes')
launch()
say('-- 2. killed twice in the foreground during the self-test, then launched: remembered as a failure')
launch('fg')
launch('fg')
launch()
launch()
say('-- 3. an upgrade (install -r) clears it: the self-test runs again')
install()
launch()
say('-- 4. killed twice in the background during the self-test, then launched: not remembered')
launch('bg')
launch('bg')
launch()
say('-- 5. killed twice in the foreground during the probation, then launched twice: remembered, "after the switch"')
launch('switch')
launch('switch')
launch()
launch()
say('-- 6. an upgrade clears it; killed twice after the probation, then launched: not remembered')
install()
launch('probation', limit=600)
launch('probation', limit=600)
launch()
say('-- 7. killed twice in the background during the probation, then launched: not remembered')
launch('switch-bg')
launch('switch-bg')
launch()
say('FINISHED')
