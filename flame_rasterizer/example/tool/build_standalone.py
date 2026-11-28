"""Builds one of the example's games on its own, for a platform and in a
build mode, with `flutter build`, and opens the folder with the built app once
it's done. On Android, iOS and macOS the game gets its own app id, name and
icon, so that it installs beside the example, and its file is named after it,
such as TubeRunner.app or TubeRunner-release.apk. tool/make_icons.py makes the
icons. From flame_rasterizer/example:

  python3 -I tool/build_standalone.py tube_shooter android release

On iOS and macOS, --bundle-id replaces the whole bundle id, and --team-id
gives the development team that signs the app:

  python3 -I tool/build_standalone.py tube_runner ios release \
      --bundle-id com.example.tubeRunner --team-id ABCDE12345

With --archive, in profile or release mode, an iOS or macOS build makes an
Xcode archive instead, such as build/macos/archive/TubeRunner.xcarchive, to
open in Xcode's Organizer later, to notarize or distribute the app. On iOS
`flutter build ipa` makes it, and tries an App Store IPA in build/ios/ipa too;
on macOS, which flutter doesn't archive, `xcodebuild archive` does, once
`flutter build macos --config-only` has set the project up, with the Hardened
Runtime that notarization needs.

With --install, an Android or iOS build is installed on a device, given by
its id or name as `flutter devices` lists them, before its folder opens:

  python3 -I tool/build_standalone.py tube_runner android release \
      --install emulator-5554

Arguments after `--` go to `flutter build` as they are, such as
`-- --no-codesign` for iOS, or `-- -o build/web_pinball` for the web.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile
import zipfile

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


def output(platform, mode, archive, flutter_args):
    """The folder that the app or its archive is built in, under the
    example."""
    if archive:
        return os.path.join('build', platform, 'archive')
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


def install(folder, game, platform, mode, device):
    """Installs game's app, built for platform in mode in folder, on device,
    given by its id or name, and returns flutter's exit code. Flutter
    uninstalls the app first if it's there, with its data."""
    with tempfile.TemporaryDirectory() as temp:
        if platform == 'android':
            binary = os.path.join(folder,
                                  '%s-%s.apk' % (file_name(game), mode))
        else:
            # flutter install takes an IPA, not an .app, on iOS.
            binary = os.path.join(temp, file_name(game) + '.ipa')
            ipa(os.path.join(folder, file_name(game) + '.app'), binary)
        return run([
            'flutter', 'install', '--' + mode, '-d', device,
            '--use-application-binary', binary,
        ], dict(os.environ))


def ipa(app, path):
    """Zips the .app at app into an IPA at path, in its Payload folder."""
    parent = os.path.dirname(app)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for root, folders, files in os.walk(app):
            for name in folders + files:
                full = os.path.join(root, name)
                # With their modes, so that the executables stay executable.
                archive.write(full, os.path.join(
                    'Payload', os.path.relpath(full, parent)))


def reveal(folder):
    """Opens folder in the platform's file manager."""
    if sys.platform == 'darwin':
        subprocess.run(['open', folder])
    elif sys.platform == 'win32':
        os.startfile(folder)
    else:
        subprocess.run(['xdg-open', folder])


def run(command, env):
    """Runs command in the example with env, once it's printed, and returns
    its exit code."""
    print(' '.join(command), flush=True)
    return subprocess.run(command, cwd=EXAMPLE, env=env).returncode


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
    parser.add_argument('--bundle-id',
                        help='the whole bundle id, for iOS and macOS, '
                        'instead of the example\'s with the game\'s suffix')
    parser.add_argument('--team-id',
                        help='the development team that signs the app, for '
                        'iOS and macOS')
    parser.add_argument('--archive', action='store_true',
                        help='make an Xcode archive, for iOS and macOS, in '
                        'profile or release mode')
    parser.add_argument('--install', metavar='DEVICE',
                        help='install the app on this device, by its id or '
                        'name, for Android and iOS')
    args = parser.parse_args()

    apple = args.platform in ('ios', 'macos')
    if apple and sys.platform != 'darwin':
        parser.error('%s builds only on macOS' % args.platform)
    if not apple and (args.bundle_id or args.team_id or args.archive):
        parser.error('--bundle-id, --team-id and --archive are for iOS and '
                     'macOS only')
    if args.archive and args.mode == 'debug':
        parser.error('--archive is for profile or release mode')
    if args.install and (args.platform not in ('android', 'ios') or
                         args.archive):
        parser.error('--install is for Android and iOS builds, without '
                     '--archive')
    if args.bundle_id and not re.fullmatch(r'[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+',
                                           args.bundle_id):
        parser.error('a bundle id has letters, digits and hyphens, in two or '
                     'more parts with dots between them')
    if args.team_id and not re.fullmatch(r'[A-Z0-9]{10}', args.team_id):
        parser.error('a team id has 10 capital letters and digits')

    subcommand = PLATFORMS[args.platform]
    if args.archive and args.platform == 'ios':
        subcommand = 'ipa'
    command = [
        'flutter', 'build', subcommand, '--' + args.mode,
        '-t', 'lib/main_%s.dart' % args.game,
    ]
    if args.archive and args.platform == 'macos':
        command.append('--config-only')
    env = dict(os.environ)
    # Build settings for xcodebuild, over the defaults in
    # ios/Flutter/*.xcconfig and macos/Runner/Configs/AppInfo.xcconfig.
    settings = {}
    if args.platform == 'android':
        command += ['--android-project-arg', 'standalone=' + args.game]
    elif apple:
        settings['APP_ID_SUFFIX'] = apple_suffix(args.game)
        settings['APP_DISPLAY_NAME'] = GAMES[args.game]
        # The .app's name, and its executable's: not PRODUCT_NAME, which
        # would rename the plugins' Swift packages too.
        settings['APP_FILE_NAME'] = file_name(args.game)
        # Its icon set, which tool/make_icons.py makes.
        settings['APP_ICON_NAME'] = 'AppIcon' + file_name(args.game)
        if args.bundle_id:
            settings['APP_BUNDLE_ID'] = args.bundle_id
        if args.team_id:
            # Without a team, iOS builds take the one that flutter finds, and
            # macOS ones are signed to run locally.
            settings['APP_TEAM_ID'] = args.team_id
            if args.platform == 'macos':
                settings['APP_SIGN_IDENTITY'] = 'Apple Development'
        # Flutter hands these to xcodebuild.
        for key, value in settings.items():
            env['FLUTTER_XCODE_' + key] = value
    command += args.flutter_args

    code = run(command, env)
    if code == 0 and args.archive and args.platform == 'macos':
        archive = [
            'xcodebuild', '-workspace', 'macos/Runner.xcworkspace',
            '-scheme', 'Runner', '-configuration', args.mode.capitalize(),
            '-archivePath', os.path.join('build', 'macos', 'archive',
                                         file_name(args.game)),
            # Warnings and errors only, as flutter's.
            'archive', '-quiet',
        ]
        if args.team_id:
            # As flutter does for signed iOS builds, so that Xcode can make
            # the team's profile.
            archive.append('-allowProvisioningUpdates')
        # Notarization needs the Hardened Runtime.
        settings['APP_HARDENED_RUNTIME'] = 'YES'
        archive += ['%s=%s' % setting for setting in settings.items()]
        code = run(archive, env)
    if code == 0:
        folder = os.path.join(EXAMPLE, output(
            args.platform, args.mode, args.archive, args.flutter_args))
        if os.path.isdir(folder):
            if args.platform == 'android':
                rename_apks(folder, args.game, args.mode)
            if args.install:
                code = install(folder, args.game, args.platform, args.mode,
                               args.install)
            reveal(folder)
        else:
            print('No folder at %s to open' % folder)
    return code


if __name__ == '__main__':
    sys.exit(main())
