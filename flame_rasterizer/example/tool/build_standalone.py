"""Builds one of the example's games on its own, for a platform and in a
build mode, with `flutter build`. On Android, iOS and macOS the game gets its
own app id and name, so that it installs beside the example. From
flame_rasterizer/example:

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
    command += args.flutter_args

    print(' '.join(command), flush=True)
    return subprocess.run(command, cwd=EXAMPLE, env=env).returncode


if __name__ == '__main__':
    sys.exit(main())
