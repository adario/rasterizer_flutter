"""Copies what integration_test/golden_test.dart wrote into the app's temporary folder, on macOS, an iOS Simulator or
device, or an Android device:
- with UPDATE_GOLDENS, every render, into goldens/<platform>/, replacing the goldens;
- failing renders and their diffs, into build/golden_failures/;
- with GOLDEN_RECORD, the atlas pages, core frames and lists, into build/golden_record/.
Run from rasterizer_gpu/example, after the test:
  python3 -I tool/pull_goldens.py macos | android <serial> | ios-simulator <udid> | ios <udid>
On Android and iOS, flutter test uninstalls the app after the run, with its files: run it with --no-uninstall."""
import os
import shutil
import subprocess
import sys
import tempfile


def find_adb():
    """adb from $ANDROID_HOME, else $ANDROID_SDK_ROOT, else PATH, else the Android SDK's macOS default folder."""
    for var in ('ANDROID_HOME', 'ANDROID_SDK_ROOT'):
        sdk = os.environ.get(var)
        if sdk and os.path.isfile(os.path.join(sdk, 'platform-tools', 'adb')):
            return os.path.join(sdk, 'platform-tools', 'adb')
    return shutil.which('adb') or os.path.expanduser('~/Library/Android/sdk/platform-tools/adb')


ADB = find_adb()
# The test's folder in the app's temporary folder (deviceOutputDir in integration_test/golden_tests.dart).
OUT = 'goldens_rasterizer_gpu_example'
MACOS = os.path.expanduser(f'~/Library/Containers/dev.rasterizer.rasterizerGpuExample/Data/tmp/{OUT}')
PACKAGE = 'dev.rasterizer.rasterizer_gpu_example'
BUNDLE = 'dev.rasterizer.rasterizerGpuExample'
TARGETS = {'macos': 'goldens/macos', 'ios': 'goldens/ios', 'android_emulator': 'goldens/android_emulator', 'android_emulator_gles': 'goldens/android_emulator_gles', 'android': 'goldens/android', 'failures': 'build/golden_failures', 'record': 'build/golden_record'}

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
kind = sys.argv[1] if len(sys.argv) > 1 else 'macos'
device = sys.argv[2] if len(sys.argv) > 2 else None
if kind not in ('macos', 'android', 'ios-simulator', 'ios') or (kind != 'macos' and not device):
    sys.exit(__doc__)


def local(root):
    for folder in TARGETS:
        path = os.path.join(root, folder)
        for name in sorted(os.listdir(path)) if os.path.isdir(path) else []:
            yield folder, name, open(os.path.join(path, name), 'rb').read()


def files():
    """(folder, name, bytes) of each file written."""
    if kind == 'macos':
        yield from local(MACOS)
        return
    if kind == 'ios-simulator':
        data = subprocess.run(['xcrun', 'simctl', 'get_app_container', device, BUNDLE, 'data'], check=True, capture_output=True,
                              text=True).stdout.strip()
        yield from local(os.path.join(data, 'tmp', OUT))
        return
    if kind == 'ios':
        with tempfile.TemporaryDirectory() as out:
            subprocess.run(['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', device, '--domain-type', 'appDataContainer',
                            '--domain-identifier', BUNDLE, '--source', f'tmp/{OUT}', '--destination', out], check=True,
                           capture_output=True)
            yield from local(out)
        return

    def adb(*args):
        return subprocess.run([ADB, '-s', device, *args], check=True, capture_output=True).stdout

    for folder in TARGETS:
        listing = subprocess.run([ADB, '-s', device, 'shell', 'run-as', PACKAGE, 'ls', f'code_cache/{OUT}/{folder}'],
                                 capture_output=True, text=True)
        for name in listing.stdout.split() if listing.returncode == 0 else []:
            yield folder, name, adb('exec-out', 'run-as', PACKAGE, 'cat', f'code_cache/{OUT}/{folder}/{name}')


counts = {}
for folder, name, data in files():
    target = TARGETS[folder]
    if folder in ('failures', 'record') and folder not in counts:
        shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target, exist_ok=True)
    with open(os.path.join(target, name), 'wb') as f:
        f.write(data)
    counts[folder] = counts.get(folder, 0) + 1
print(', '.join(f'{n} into {TARGETS[folder]}' for folder, n in counts.items()) or 'nothing to pull')
