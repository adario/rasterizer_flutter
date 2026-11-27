"""Builds one of the example's games on its own, for a platform and in a
build mode, with `flutter build`, and opens the folder with the built app once
it's done. On Android, iOS and macOS the game gets its own app id and name, so
that it installs beside the example, and its file is named after it, such as
TubeRunner.app or TubeRunner-release.apk. From flame_rasterizer/example:

  python3 -I tool/build_standalone.py tube_shooter android release

Arguments after `--` go to `flutter build` as they are, such as
`-- --no-codesign` for iOS, or `-- -o build/web_pinball` for the web.
"""
import argparse
import os
import subprocess
import sys

# Each game's name, as its app shows it. Android's labels are in
# android/app/build.gradle.kts.
GAMES = {
    'tube_shooter': 'Tube Shooter',
    'revolute_pinball': 'Revolute Pinball',
    'tube_runner': 'Tube Runner',
}

# The `flutter build` subcommand for each platform.
PLATFORMS = {
    'android': 'apk',
    'ios': 'ios',
    'macos': 'macos',
    'web': 'web',
}

MODES = ['debug', 'profile', 'release']

EXAMPLE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def apple_suffix(game):
    """The bundle id's suffix for game: tube_shooter is .tubeShooter, as Apple
    ids can't have underscores."""
    first, *rest = game.split('_')
    return '.' + first + ''.join(word.capitalize() for word in rest)


def file_name(game):
    """The name of game's app file: Tube Runner's is TubeRunner."""
    return GAMES[game].replace(' ', '')


def rename_apks(folder, game, mode):
    """Renames the APKs that flutter built in folder, such as app-release.apk,
    and their .sha1 files after game, such as TubeRunner-release.apk."""
    for name in os.listdir(folder):
        if name.startswith('app-') and (name.endswith(mode + '.apk') or
                                        name.endswith(mode + '.apk.sha1')):
            renamed = file_name(game) + name[len('app'):]
            os.replace(os.path.join(folder, name),
                       os.path.join(folder, renamed))
            print('Renamed %s to %s' % (name, renamed))


def output(platform, mode, flutter_args):
    """The folder that flutter builds the app in, under the example."""
    if platform == 'android':
        return os.path.join('build', 'app', 'outputs', 'flutter-apk')
    if platform == 'ios':
        return os.path.join('build', 'ios', 'iphoneos')
    if platform == 'macos':
        return os.path.join('build', 'macos', 'Build', 'Products',
                            mode.capitalize())
    # The web's can be another, with -o or --output.
    folder = os.path.join('build', 'web')
    for i, arg in enumerate(flutter_args):
        if arg in ('-o', '--output') and i + 1 < len(flutter_args):
            folder = flutter_args[i + 1]
        elif arg.startswith('--output='):
            folder = arg[len('--output='):]
    return folder


def reveal(folder):
    """Opens folder in the platform's file manager."""
    if sys.platform == 'darwin':
        subprocess.run(['open', folder])
    elif sys.platform == 'win32':
        os.startfile(folder)
    else:
        subprocess.run(['xdg-open', folder])


def main():
    parser = argparse.ArgumentParser(
        description='Builds one of the example\'s games on its own.',
        epilog='Arguments after -- go to flutter build as they are.',
    )
    parser.add_argument('game', choices=GAMES)
    parser.add_argument('platform', choices=PLATFORMS)
    parser.add_argument('mode', choices=MODES)
    parser.add_argument('flutter_args', nargs='*', metavar='-- ARGS',
                        help='more arguments for flutter build')
    args = parser.parse_args()

    if args.platform in ('ios', 'macos') and sys.platform != 'darwin':
        parser.error('%s builds only on macOS' % args.platform)

    command = [
        'flutter', 'build', PLATFORMS[args.platform], '--' + args.mode,
        '-t', 'lib/main_%s.dart' % args.game,
    ]
    env = dict(os.environ)
    if args.platform == 'android':
        command += ['--android-project-arg', 'standalone=' + args.game]
    elif args.platform in ('ios', 'macos'):
        # Build settings that flutter hands to xcodebuild, over the defaults
        # in ios/Flutter/*.xcconfig and macos/Runner/Configs/AppInfo.xcconfig.
        env['FLUTTER_XCODE_APP_ID_SUFFIX'] = apple_suffix(args.game)
        env['FLUTTER_XCODE_APP_DISPLAY_NAME'] = GAMES[args.game]
        # The .app's name, and its executable's: not PRODUCT_NAME, which
        # would rename the plugins' Swift packages too.
        env['FLUTTER_XCODE_APP_FILE_NAME'] = file_name(args.game)
    command += args.flutter_args

    print(' '.join(command), flush=True)
    code = subprocess.run(command, cwd=EXAMPLE, env=env).returncode
    if code == 0:
        folder = os.path.join(
            EXAMPLE, output(args.platform, args.mode, args.flutter_args))
        if os.path.isdir(folder):
            if args.platform == 'android':
                rename_apks(folder, args.game, args.mode)
            reveal(folder)
        else:
            print('No folder at %s to open' % folder)
    return code


if __name__ == '__main__':
    sys.exit(main())
