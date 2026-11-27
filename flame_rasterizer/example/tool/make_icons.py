"""Makes the standalone games' app icons, for tool/build_standalone.py, from
a screenshot of each game's first frame that shows READY, without READY and
the HUD. From flame_rasterizer/example, on macOS, with ImageMagick's
`magick`:

  python3 -I tool/make_icons.py

integration_test/app_icons_test.dart takes the screenshots, 1024 by 1024, in
the macOS app. With --from, the icons are made from the screenshots in a
folder instead, such as the one that the test printed, named after the games,
such as tube_runner.png:

  python3 -I tool/make_icons.py --from <folder>

Each game gets:
- on iOS, the screenshot, at every size of the example's icon set, in
  ios/Runner/Assets.xcassets/AppIconTubeRunner.appiconset;
- on macOS, the screenshot in a tile with rounded corners, as Apple's
  template draws icons, at every size of the example's icon set, in
  macos/Runner/Assets.xcassets/AppIconTubeRunner.appiconset;
- on Android, in android/app/src/standalone/tube_runner/res, which only the
  game's app has, ic_launcher_tube_runner: a legacy icon, the screenshot at
  48 dp, and an adaptive icon, whose foreground is the screenshot at 108 dp,
  of which the launcher shows the middle 72 dp or less.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# The games, as tool/build_standalone.py names them, with the names of their
# app files, which name their icon sets on iOS and macOS.
GAMES = {
    'tube_shooter': 'TubeShooter',
    'revolute_pinball': 'RevolutePinball',
    'tube_runner': 'TubeRunner',
}

EXAMPLE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

TEST = 'integration_test/app_icons_test.dart'

# Android's densities, with their pixels per dp.
DENSITIES = {
    'mdpi': 1,
    'hdpi': 1.5,
    'xhdpi': 2,
    'xxhdpi': 3,
    'xxxhdpi': 4,
}

# Apple's macOS icon template, at 1024 by 1024: the tile's side, and its
# corners' radius.
TILE = 824
TILE_RADIUS = 185.4

ADAPTIVE_ICON = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@android:color/black" />
    <foreground android:drawable="@mipmap/{name}_foreground" />
</adaptive-icon>
'''


def magick(*args):
    """Runs ImageMagick with args, writing 8-bit PNGs without metadata."""
    output = args[-1]
    subprocess.run(['magick', *args[:-1], '-strip', '-depth', '8', output],
                   check=True)


def capture():
    """Runs the test that takes the screenshots, and returns their folder."""
    command = ['flutter', 'test', TEST, '-d', 'macos']
    print(' '.join(command), flush=True)
    result = subprocess.run(command, cwd=EXAMPLE, capture_output=True,
                            text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode != 0:
        sys.exit('%s failed' % TEST)
    paths = re.findall(r'^ICON (.+\.png) ', result.stdout, re.MULTILINE)
    if len(paths) != len(GAMES):
        sys.exit('%s printed %d screenshots, not %d' %
                 (TEST, len(paths), len(GAMES)))
    return os.path.dirname(paths[0])


def icon_set(platform, name):
    """The folder of platform's icon set called name."""
    return os.path.join(EXAMPLE, platform, 'Runner', 'Assets.xcassets',
                        name + '.appiconset')


def apple_icons(platform, source, name):
    """Makes platform's icon set called name from source, a 1024 by 1024
    PNG, at the sizes of the example's own set, AppIcon."""
    folder = icon_set(platform, name)
    if os.path.isdir(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)
    contents = os.path.join(icon_set(platform, 'AppIcon'), 'Contents.json')
    shutil.copy(contents, folder)
    with open(contents) as file:
        images = json.load(file)['images']
    made = set()
    for image in images:
        if image['filename'] in made:
            continue
        made.add(image['filename'])
        side = float(image['size'].split('x')[0])
        pixels = round(side * int(image['scale'][:-1]))
        # iOS icons may have no alpha channel.
        alpha = ['-alpha', 'off'] if platform == 'ios' else []
        magick(source, '-resize', '%dx%d' % (pixels, pixels), *alpha,
               os.path.join(folder, image['filename']))
    print('Made %s' % os.path.relpath(folder, EXAMPLE))


def mac_tile(screenshot, output):
    """Draws screenshot, 1024 by 1024, in a tile with rounded corners in the
    middle of a clear 1024 by 1024 square, as Apple's macOS template does."""
    magick('(', screenshot, '-resize', '%dx%d' % (TILE, TILE), ')',
           '(', '-size', '%dx%d' % (TILE, TILE), 'xc:none', '-fill', 'white',
           '-draw', 'roundrectangle 0,0 %d,%d %s,%s' %
           (TILE - 1, TILE - 1, TILE_RADIUS, TILE_RADIUS), ')',
           '-alpha', 'set', '-compose', 'DstIn', '-composite',
           # -extent composites too, with the last -compose.
           '-compose', 'Over', '-background', 'none', '-gravity', 'center',
           '-extent', '1024x1024', output)


def android_icons(game, screenshot):
    """Makes game's Android icons from screenshot, in resources that only
    its app has."""
    res = os.path.join(EXAMPLE, 'android', 'app', 'src', 'standalone', game,
                       'res')
    if os.path.isdir(res):
        shutil.rmtree(res)
    name = 'ic_launcher_' + game
    for density, scale in DENSITIES.items():
        folder = os.path.join(res, 'mipmap-' + density)
        os.makedirs(folder)
        legacy = round(48 * scale)
        magick(screenshot, '-resize', '%dx%d' % (legacy, legacy),
               '-alpha', 'off', os.path.join(folder, name + '.png'))
        foreground = round(108 * scale)
        magick(screenshot, '-resize', '%dx%d' % (foreground, foreground),
               '-alpha', 'off',
               os.path.join(folder, name + '_foreground.png'))
    folder = os.path.join(res, 'mipmap-anydpi-v26')
    os.makedirs(folder)
    with open(os.path.join(folder, name + '.xml'), 'w') as file:
        file.write(ADAPTIVE_ICON.format(name=name))
    print('Made %s' % os.path.relpath(res, EXAMPLE))


def main():
    parser = argparse.ArgumentParser(
        description='Makes the standalone games\' app icons.')
    parser.add_argument('--from', dest='source', metavar='FOLDER',
                        help='make them from the screenshots in FOLDER, '
                        'instead of taking them')
    args = parser.parse_args()
    if shutil.which('magick') is None:
        sys.exit('ImageMagick\'s magick is missing')
    if args.source is None and sys.platform != 'darwin':
        sys.exit('The screenshots are taken on macOS only: use --from')

    source = args.source or capture()
    with tempfile.TemporaryDirectory() as temp:
        for game, file_name in GAMES.items():
            screenshot = os.path.join(source, game + '.png')
            if not os.path.isfile(screenshot):
                sys.exit('No screenshot at %s' % screenshot)
            apple_icons('ios', screenshot, 'AppIcon' + file_name)
            tile = os.path.join(temp, game + '_tile.png')
            mac_tile(screenshot, tile)
            apple_icons('macos', tile, 'AppIcon' + file_name)
            android_icons(game, screenshot)


if __name__ == '__main__':
    main()
