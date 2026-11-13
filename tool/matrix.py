"""The integration matrix, through tool/device_tests.py: on the Android emulator's Vulkan (IMPELLER_BACKEND=vulkan),
then its OpenGL ES (IMPELLER_BACKEND=opengles), then on macOS, then on web in headless Chrome, with CanvasKit (_js)
and skwasm (_wasm), flame_rasterizer's limits test first (and on macOS with the canvas renderer too), then the
self-test, switch, defer, goldens, atlas and Flame check tests; on web, the limits, opacity, edge, goldens and Flame
check tests, with the canvas renderer. Without arguments, all of them, stopping at the first unexpected failure;
otherwise the steps named, e.g. gles_selftest vk_flame, with device_tests.py's flags (--keep-going) passed on.
EXPECTED lists the tests expected to fail, by step. vk_atlas is left out of `all`: it's where the emulator's Vulkan
hang lives (not seen in 30 runs on its own since), so name it to run it. The web steps need the chromedriver in the
repository's build/chromedriver/ (see device_tests.py). Run in the background, and follow with tool/follow.py:
  python3 -I tool/matrix.py > matrix.txt"""
import os, subprocess, sys

TOOL = os.path.dirname(os.path.abspath(__file__))
G, F = 'rasterizer_gpu/example', 'flame_rasterizer/benchmark'
VK, GLES = 'IMPELLER_BACKEND=vulkan', 'IMPELLER_BACKEND=opengles'
GOLD = 'integration_test/golden_test.dart --dart-define=BACKEND=gpu'
LIMITS = 'integration_test/limits_test.dart'
STEPS = {
    'vk_limits': f'{F}:{VK}:{LIMITS}',
    'vk_selftest': f'{G}:{VK}:integration_test/self_test_test.dart',
    'vk_switch': f'{G}:{VK}:integration_test/switch_test.dart',
    'vk_goldens': f'{G}:{VK}:{GOLD}',
    'vk_flame': f'{F}:{VK}:integration_test/check_test.dart',
    'vk_atlas': f'{G}:{VK}:integration_test/atlas_test.dart',
    'gles_limits': f'{F}:{GLES}:{LIMITS}',
    'gles_selftest': f'{G}:{GLES}:integration_test/self_test_test.dart',
    'gles_switch': f'{G}:{GLES}:integration_test/switch_test.dart',
    'gles_defer': f'{G}:{GLES}:integration_test/defer_test.dart',
    'gles_goldens': f'{G}:{GLES}:{GOLD}',
    'gles_atlas': f'{G}:{GLES}:integration_test/atlas_test.dart',
    'gles_flame': f'{F}:{GLES}:integration_test/check_test.dart',
    'mac_limits': f'{F}::{LIMITS}:macos',
    'mac_limits_canvas': f'{F}::{LIMITS} --dart-define=BACKEND=canvas:macos',
    'mac_selftest': f'{G}::integration_test/self_test_test.dart:macos',
    'mac_switch': f'{G}::integration_test/switch_test.dart:macos',
    'mac_goldens': f'{G}::integration_test/golden_test.dart:macos',
    'mac_atlas': f'{G}::integration_test/atlas_test.dart:macos',
    'mac_flame': f'{F}::integration_test/check_test.dart:macos',
    'web_limits_js': f'{F}::{LIMITS}:chrome',
    'web_limits_wasm': f'{F}::{LIMITS} --wasm:chrome',
    'web_opacity_js': f'{G}::integration_test/opacity_test.dart:chrome',
    'web_opacity_wasm': f'{G}::integration_test/opacity_test.dart --wasm:chrome',
    'web_edge_js': f'{G}::integration_test/edge_test.dart:chrome',
    'web_edge_wasm': f'{G}::integration_test/edge_test.dart --wasm:chrome',
    'web_goldens_js': f'{G}::integration_test/golden_test.dart:chrome',
    'web_goldens_wasm': f'{G}::integration_test/golden_test.dart --wasm:chrome',
    'web_flame_js': f'{F}::integration_test/check_test.dart:chrome',
    'web_flame_wasm': f'{F}::integration_test/check_test.dart --wasm:chrome',
}
# Step: a regex of the names of its tests expected to fail.
EXPECTED = {}
flags = [a for a in sys.argv[1:] if a.startswith('--')]
names = [a for a in sys.argv[1:] if not a.startswith('--')] or [k for k in STEPS if k != 'vk_atlas']
sys.exit(subprocess.call([sys.executable, '-I', os.path.join(TOOL, 'device_tests.py'), *flags,
                          *[f'--expect={k}:{EXPECTED[k]}' for k in names if k in EXPECTED],
                          *[f'{k}:{STEPS[k]}' for k in names]]))
