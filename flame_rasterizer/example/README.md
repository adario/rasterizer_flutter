# flame_rasterizer_example

[flame_rasterizer](..)'s example app. It shows flame_rasterizer's SVGs next to flame_svg's, in a
[Widgetbook](https://pub.dev/packages/widgetbook) laid out as Flame's own examples are. Run it with
`flutter run -d <macos | chrome | an iPhone | emulator-5554 | linux | windows>`. On an iPhone, pick your development
team in Xcode first (Runner ▸ Signing & Capabilities), as the project has none.

On Linux, the app's sounds go through flame_audio's audioplayers_linux, which builds against GStreamer. On Debian or
Ubuntu, install its headers first: `sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev`. Playing the
sounds also needs `gstreamer1.0-plugins-base` and `gstreamer1.0-plugins-good`, for its WAV parser, which most desktops
already have. The repository's Linux container (`tool/linux/`) installs all four.

On Windows, building needs Visual Studio's "Desktop development with C++" workload, and Developer Mode on, for the
symlinks Flutter makes to the app's plugins: see Flutter's
[Windows setup](https://docs.flutter.dev/platform-integration/windows/setup).

The example runs on Flame's main branch: flame 2.0.0-dev, flame_audio 2.13.0-dev, flame_svg 3.0.0-dev and
flame_forge2d 0.21.0-dev, through the workspace's dependency overrides (the root `pubspec.yaml`), as Flame's examples
do. On web, flame_rasterizer draws with the canvas renderer.

## Games on their own

Three games also run on their own, outside the Widgetbook and without the status bar. A settings button in the top
right corner opens a dialog with the renderer and the game's knobs, except Zoom and Speed. The game pauses while the
dialog shows, and goes on with the new settings once it closes.

- Tube Shooter: `flutter run -t lib/main_tube_shooter.dart`.
- Revolute Pinball: `flutter run -t lib/main_revolute_pinball.dart`. On a desktop or in a desktop browser, in landscape,
  its Square setting, off at first, narrows the table to the window's height.
- Tube Runner: `flutter run -t lib/main_tube_runner.dart`. It's a prototype of an endless runner on Tube Shooter's
  tubes, which only runs on its own.

`tool/build_standalone.py` builds one of them for Android (an APK), iOS, macOS or the web, in debug, profile or release
mode, and opens the folder with the built app once it's done. For instance:

```sh
python3 -I tool/build_standalone.py tube_shooter android release
```

Arguments after `--` go to `flutter build`, such as `-- --no-codesign`. On Android, iOS and macOS, the game gets its own
app id, name and icon, so it installs beside the example, and its file is named after it, such as
`TubeShooter-release.apk` or `TubeShooter.app`. `tool/make_icons.py` makes the icons. On Android, the script passes
`--android-project-arg standalone=tube_shooter` (`android/app/build.gradle.kts`) and renames the APK. On iOS and macOS,
it sets the `APP_ID_SUFFIX`, `APP_DISPLAY_NAME`, `APP_FILE_NAME` and `APP_ICON_NAME` build settings, as `FLUTTER_XCODE_`
environment variables, over the defaults in `ios/Flutter/*.xcconfig` and `macos/Runner/Configs/AppInfo.xcconfig`.

Its options:

- **`--bundle-id com.example.tubeShooter`**, on iOS and macOS, replaces the whole bundle id (`APP_BUNDLE_ID`).
- **`--team-id ABCDE12345`**, on iOS and macOS, gives the development team that signs the app (`APP_TEAM_ID`). Without
  a team, iOS builds take the one that flutter finds, and macOS builds are signed to run locally. With one, macOS builds
  are signed with its Apple Development identity (`APP_SIGN_IDENTITY`). These settings apply only to the Runner target:
  `PRODUCT_BUNDLE_IDENTIFIER`, `DEVELOPMENT_TEAM` or `PRODUCT_NAME` set on the command line would also change the
  plugins' Swift package targets.
- **`--archive`**, in profile or release mode, makes an iOS or macOS build an Xcode archive instead, such as
  `build/macos/archive/TubeShooter.xcarchive`, to open later in Xcode's Organizer to notarize or distribute the app. On
  iOS, `flutter build ipa` makes it, and also tries an App Store IPA in `build/ios/ipa` (none with `-- --no-codesign`).
  On macOS, which flutter doesn't archive, `xcodebuild archive` makes it, once `flutter build macos --config-only` has
  set the project up for the game. It uses the same build settings, plus the Hardened Runtime that notarization needs
  (`APP_HARDENED_RUNTIME`, off in other builds).
- **`--install <device>`**, on Android and iOS without `--archive`, installs the app on a device, given by its id or
  name as `flutter devices` lists them, before the folder opens.

## Shared knobs and SVGs

Every use case has a Renderer knob (see [Svg Renderers](#svg--svg-renderers)) and a status bar under the game. They also
share these knobs:

- **Zoom**: the camera's zoom, from 0.25× to 5×.
- **Speed**: the game's speed, from 0, which stands still, to 2×.
- **Cache mode** and **Cache size**: flame_svg's image cache, shown with Flame SVG only. Tube Shooter, which draws no
  SVGs, doesn't have them.

Zoom and Speed are continuous sliders, which show their values to two decimals. A new renderer makes a new game, which
goes on from where the old one was. So does a new cache, except in Svg Renderers, which loads its SVG again in the
running game. The other knobs change the running game.

The use cases other than Svg Renderers, Svg Shooter and Tube Shooter pick their SVGs at random from 13 of the 27
(`randomSvgNames`, in `commons/svg_renderers.dart`). They leave out:

- setup_merge and recycle_merge, which pair with setup and recycle in Svg Renderers;
- prism and spaceship_2, which only Svg Renderers shows;
- Svg Shooter's rocket_ship, missile, spaceship_game and wireframes (`wireframe/`);
- tiger, until the cost of its hitboxes and Box2D pieces is measured;
- android, which doesn't suit collisions.

Collidable Svgs and Revolute Joint Svgs follow [flame_path_shapes](https://github.com/adario/flame_path_shapes), a Flame
examples app with path shapes, which isn't part of Flame. Multiple Shapes follows Flame's own
[`MultipleShapesExample`](https://github.com/flame-engine/flame/blob/main/examples/lib/stories/collision_detection/multiple_shapes_example.dart).

## Svg ▸ Svg Renderers

One SVG rotates in the centre, inside a ring of more. Each SVG in the ring is smaller than the one before, and starts
rotating a little later. Its knobs, in Widgetbook's panel, pick:

- **Renderer**, one of:
  - GPU (mesh): flame_rasterizer with rasterizer_gpu's mesh renderer, its default, which imports each SVG once into
    triangles;
  - GPU (atlas): flame_rasterizer with rasterizer_gpu's atlas renderer, which rasterizes the SVGs into an atlas each
    frame;
  - Canvas: flame_rasterizer with the canvas renderer everywhere (`RasterizerGpu.forceCanvas`);
  - Flame SVG: flame_svg. In Tube Shooter, which draws no SVGs, this entry shows as Flame, as Flame's own components
    draw there.

  A GPU entry is inactive where its renderer isn't supported: on web and without Impeller. The first choice is the
  first active entry among GPU (mesh), GPU (atlas) and Canvas. An active GPU entry shows the graphics API that Impeller
  renders with: Metal (mesh) and Metal (atlas) on iOS and macOS, Vulkan (mesh) and Vulkan (atlas) on Android, and GLES
  (mesh) and GLES (atlas) on OpenGL ES. Links keep the labels GPU (mesh), GPU (atlas) and Flame SVG, so that a link
  picks the same entry on every device and in every use case. A link to an inactive GPU entry draws with Canvas.
  Widgetbook's dropdown can't make an entry inactive, so this knob is the example's own (`commons/renderer_knob.dart`).
- **Svg**: one of the 27 SVGs in `assets/svgs/` and `assets/svgs/wireframe/`, loaded into the running game.
- **SVG Number**: the number of SVGs in the ring, from 10 to 500, 100 by default.
- **Fade SVGs**: off by default. Each SVG in the ring is fainter than the one before, through its paint's opacity.
  flame_rasterizer still draws them all in one run.
- **Zoom**: the running game keeps its SVG and its times.
- **Speed**: the rotation's speed. At 1, a turn takes 2 s.
- **Cache mode** and **Cache size**: flame_svg's `fixedRatio` and `cacheSize`. The SVG loads again with them.

A new SVG, SVG number, fade or cache replaces the components. The new ones start turned as far as the ones they
replace.

The FPS is at the game's top left. The status bar under the game shows:

- the renderer;
- the frame times, in ms: render, build and raster, each the mean and the 90th percentile of the last 60 frames.
  Render is the components' own time, without flame_rasterizer's frame;
- the renderer's own numbers. For flame_rasterizer, its runs and entries, and with a GPU renderer, the mesh renderer's
  run targets or the atlas renderer's pages, their size, and the frame's CPU, upload and encode times. For flame_svg,
  its cache use.

Things to look at:

- the times and the FPS as the SVG number grows, for each renderer;
- Fade SVGs, which costs flame_rasterizer nothing more, and makes flame_svg blend its cached images through a
  translucent paint;
- Zoom. flame_rasterizer stays sharp, as it draws at the device's resolution under the camera. In integral cache mode,
  flame_svg rasterizes new images, and its cache use grows. In fixed mode, it scales the images it cached, which blur
  as it zooms in;
- Speed at 0: the renderers' cost without motion. All of them still draw every frame: flame_svg its cached images, and
  flame_rasterizer the SVGs, with each of its renderers;
- setup_merge and recycle_merge: setup and recycle with most or all of their strokes in one colour, to show how each
  renderer merges strokes where they meet;
- the tiger, the heaviest SVG. With GPU (atlas), its build time is the core's work and the atlas upload, every frame.
  With GPU (mesh), it's imported once, and a frame costs the CPU what a light SVG's does, but its tens of thousands of
  triangles cost the GPU at every zoom;
- alien, invader_1, invader_2, recycle, recycle_merge, setup and setup_merge, which use clip paths. flame_rasterizer
  doesn't support clip paths, so it draws these SVGs unclipped.

## Svg ▸ Collidable Svgs

After flame_path_shapes' `CollidableSvgPathsExample`. SVGs picked at random move and spin in an arena the size of the
game at a zoom of 1. Their hitboxes are flame_rasterizer's `SvgHitbox`es, in the shape of their paths, whatever draws
them. Two SVGs that collide swap their velocities, and one that hits a wall bounces off it.

Flame checks collisions once a frame, after the moves. So on a long frame, a small, fast SVG can cross a wall without
touching it. An SVG whose centre went past a wall comes back to it, moving away from it.

Its knobs pick:

- **Renderer**: as above, with the same hitboxes for all.
- **SVG Number**: 2 to 50, 4 by default, in the running game. New SVGs come in where there's room, or the last ones go.
  All the SVGs shrink when too many wouldn't fit.
- **Zoom**: the camera's zoom on the arena, whose walls stay put.
- **Speed**: as above.
- **Cache mode** and **Cache size**: as above.

The status bar adds the collisions so far. The game doesn't draw hitboxes.

## Collision Detection ▸ Multiple Shapes

After Flame's `MultipleShapesExample`. Shapes made from SVGs picked at random fill the arena in rows, with a snowman of
three `CircleHitbox`es. They move, spin, and wrap around the arena's walls. Their hitboxes are `SvgHitbox`es of the
SVGs' outlines, whatever draws them. While a shape collides with another, Flame's `tint` turns it green, and on a wall,
purple. The snowman's circles take their own colours. Drag a shape to throw it.

Its knobs pick:

- **Renderer**: as above.
- **Shapes**: Paths, the default, or SVGs, drawn as they are. A path shape is its SVG's outline (`SvgOutline.path`) as
  one path, with two paint layers: a fill in a colour of its own at an alpha of 0.8, and a round stroke in a lighter
  colour, 1/50 of the outline's longer side wide. flame_rasterizer draws paths with `RasterizerPathComponent`, and
  Flame SVG with Flame's `PathComponent`. The shapes of one SVG share one path, sized by their components' scale, so
  with flame_rasterizer they share one scene, tinted or not. New shapes make a new game, as a new renderer does.
- **Shape Number**: 2 to 50, 15 by default, not counting the snowman, in the running game. As in Collidable Svgs, new
  shapes come in where there's room, or the last ones go. The game then resizes all the shapes to the largest scale, up
  to 1, at which the rows hold that many. The snowman keeps the size it has in Flame's example.
- **Zoom** and **Speed**: as in Collidable Svgs.
- **Cache mode** and **Cache size**: as in Collidable Svgs, with SVGs only, as paths use no flame_svg cache.

The status bar adds the number of shapes, and of those colliding now.

Things to look at:

- the runs. flame_rasterizer draws one, however many shapes are tinted, SVGs or paths, as it folds a tint into each
  SVG's or path's paints rather than drawing a layer per tint;
- the raster time and the size of the targets or atlas, while shapes are tinted and while none are;
- with Paths, Flame's `PathComponent`, which draws each path with the canvas, against flame_rasterizer's.

## Forge2D ▸ Revolute Joint Svgs

After flame_path_shapes' `RevoluteJointWithMotorExample`, which extends Flame's Forge2D example. In a `Forge2DGame` at
10 pixels a meter, a motor turns a wheel of five circles under a funnel of two ramps. Walls run along the game's edges
at a zoom of 1. Each tap drops 15 bodies, half balls and half SVGs picked at random, 3 to 3.5 m at their longer side.
They fall through the funnel into the wheel.

The SVG bodies collide as the convex pieces of their outlines, made once for each SVG and size (`commons/forge2d.dart`).
An `SvgHitbox` of the SVG's `outline`, sampled every 0.1 m, gives polygons, and Flame's `convexPieces` cuts them into
convex pieces, which Box2D takes as polygons. The example leaves out pieces under 0.1 m across, about a pixel, as
flame_forge2d warns about them.

Its knobs pick:

- **Renderer**: as above.
- **Pieces**: off by default. It draws the SVG bodies' convex pieces over them, those dropped before too, to show how
  closely the bodies follow the SVGs.
- **Zoom**: the camera's zoom, on top of the world's 10 pixels a meter. The walls stay put.
- **Speed**: the physics' speed.
- **Cache mode** and **Cache size**: as in Collidable Svgs. The SVGs are sized in pixels and scaled to meters, so that
  fixed mode rasterizes them at 10 pixels a meter, not at their size in meters.

The status bar adds the balls and SVGs dropped. As in flame_path_shapes, the number of bodies, the walls, ramps and
wheel included, is at the top right.

Things to look at: the runs. flame_rasterizer draws one, however many bodies fall. The SVG bodies have a higher priority
than the balls, walls, ramps and wheel, which the canvas draws, so they draw above them, all in one run. In the
component tree's order, the balls between them would end a run at nearly every SVG body, and with the mesh renderer,
each run has a target of its own. Bodies don't overlap, so the game looks the same. A Forge2D game can do the same: give
its vector bodies a priority above its canvas-drawn ones. Pieces draws after all the bodies, which keeps the SVGs in one
run too.

The game destroys its Box2D world when it's removed, as Box2D has room for only 128 worlds at once, and removing a game
from its widget doesn't free its world.

flame_forge2d's forge2d binds Box2D's C library. Its build hook compiles the library with the platform's C toolchain, as
rasterizer_gpu's hook does its core. On web, forge2d loads Box2D's WebAssembly build, bundled as an asset.

## Games ▸ Svg Shooter

A vertical shooter after Rogue Shooter, one of Flame's example games, with SVGs for its sprites
(`stories/games/svg_shooter/`, a file per component). The player's spaceship is an SVG in colour, and the enemies and
missiles are wireframe SVGs. Hundreds of SVGs are on screen at once, each with an `SvgHitbox` in the shape of its
paths, whatever draws it.

- **Controls.** Drag anywhere, or use the arrow keys or WASD, to move the spaceship. Fire while dragging, or while
  holding the space bar. A click on the game takes the keys back from Widgetbook's knobs.
- **Play.** Waves of enemies fall from the top: two kinds of spaceships, rockets, and robots that swing as they fall,
  in random colours. A missile that hits an enemy blows it up and scores. An enemy that hits the spaceship takes some
  of its health, which comes back after a while without a hit. When the health runs out, the game is over, and a tap
  starts a new one.
- **The rest.** The stars are sprites, and the explosions are particles, as in the original.

Its knobs pick:

- **Renderer**: as above, with the same hitboxes for all.
- **Zoom**: the camera's zoom on the play area. A drag moves the player as far as the finger, at any zoom.
- **Speed**: as above.
- **Cache mode** and **Cache size**: as in Collidable Svgs.

The health, the score and the number of components are at the bottom right. Things to look at: the runs.
flame_rasterizer draws all the SVGs in one run, as the explosions draw above them all.

## Games ▸ Tube Shooter

A tube shooter in vector lines, inspired by Atari's Tempest (1981) (`stories/games/tube_shooter/`, a file per
component). It draws no SVGs: every line in it, text included, is a path, drawn by a `RasterizerPathComponent`, or with
the Flame entry, by Flame's `PathComponent`.

- **Controls.** Move the ship round the rim of the tube with the arrow keys or A and D, by dragging left and right, or
  by a lane per scroll of the mouse wheel. On Android and iOS, a finger that circles round the tube's centre moves it
  instead. Fire down the ship's lane with the space bar, or while dragging. Enter, or a double tap, destroys all the
  enemies in the tube, once a round. A tap or a key starts each round, and goes on after a lost ship.
- **Play.** Five kinds of enemies climb the tube. Once they're all gone, the ship drops down its lane, and a spike left
  in that lane destroys it. The ship then flies down Tube Runner's endless tube while the round's enemies come again,
  and flies out onto the rim of the next of ten tubes. Each round is 5% faster than the last.
- **Paths.** The game makes some paths again every frame, such as the tube's during the zoom. It shares others among
  many components, such as the enemies' shapes, which move by their transforms with no new import. Fading and tinting
  cost no import either.

Its knobs pick:

- **Renderer**: GPU (mesh), GPU (atlas) and Canvas draw with `RasterizerPathComponent`s, and Flame with Flame's
  `PathComponent`s. Flame is the Flame SVG entry of the other use cases. On web, the GPU entries are inactive, as
  Flutter GPU isn't available there, and the canvas renderer draws the paths.
- **Level**: the level a new game starts at, by its tube's name, so that the player can see any tube without playing
  up to it. It also shows the current round's level.
- **Glow**: off by default. It makes the lines glow. The mesh renderer draws the glow with the lines, and the other
  renderers draw it with a shader over the world.
- **Sound**: on by default. It changes the running game, which loads its sounds the first time it's on.
- **Zoom**: the camera's zoom on the tube, whose lines keep their widths in device pixels, as the game makes its paths
  and strokes again for it.
- **Speed**: as above.

The status bar shows the paths made a second, after the renderer's numbers. Things to look at:

- the runs: one with flame_rasterizer;
- the paths made a second: one a frame during the zoom and the drop, while seeders climb, and while zappers pulse, and
  the frame times then;
- the dots, the stars and the texts, which make no paths.

## Games ▸ Revolute Pinball

A pinball with Revolute Joint Svgs' bodies, wheel and walls, in a `Forge2DGame` at 10 pixels a meter. The table fits the
window, and is built again when the window is resized.

- **Controls.** A key or a tap starts the game. Left, A or Left Shift kicks the left flipper, and Right, D or Right
  Shift the right one. So does a touch in the left or right half of the bottom third.
- **Play.** Each drop puts 10 bodies over the wheel. Once each is in a bucket, has drained, or is at rest, the wheel
  turns the other way and the next 10 drop, up to 200 bodies. A body scores once, when it comes to rest in a bucket:
  the bigger the body and the fuller the bucket, the more it scores. Each drained body takes energy by its area. A full
  bucket gives back energy, empties, and kicks the bodies in the other bucket up and out. When the energy runs out, the
  game is over.
- **Drawing.** The flippers, guides and buckets draw their outlines and glows as paths, imported once. Most SVG bodies
  draw as their outlines' paths too. The flame draws as its SVG, and the spaceship and the robot as their wireframes.

Its knobs pick:

- **Renderer**: as above. The new game goes on from where the old one was.
- **Pieces**: as in Revolute Joint Svgs.
- **Drops**: Mixed by default, balls and SVGs in turn. Balls or SVGs drop only that kind. It applies from the next drop.
- **Sound**: as in Tube Shooter.
- **Zoom** and **Speed**: as in Revolute Joint Svgs.
- **Cache mode** and **Cache size**: as in Revolute Joint Svgs.

## Tests

`flutter test` runs the unit tests, in `test/`:

- `example_test.dart`: the Widgetbook builds, and each use case's knobs fit in its sheet and side panel, in windows of
  several widths. Knobs show only where they apply, and the Renderer knob's GPU entries are inactive without Impeller.
  The Svg Renderers game loads with each renderer, and its knobs change it in place.
- `cache_knobs_test.dart`: the other use cases' flame_svg knobs show only with Flame SVG, and in Multiple Shapes only
  with SVGs. It's a file of its own, because these games load random SVGs with flame_svg, whose loads the tests in a
  file share.
- `status_bar_test.dart`: the status bar keeps the game's size, leaves blank the times it has no frames for, and shows
  one flame_svg cache total for all the SVGs.
- `removed_while_loading_test.dart`: a game removed while it loads stops loading.
- `game_story_test.dart`: a new renderer or cache goes on from a snapshot of the old game, and the game pauses while
  its ticker is off.
- `standalone_game_test.dart` and `standalone_test.dart`: the games that run on their own, and their settings dialog.
- `collidable_test.dart`, `multiple_shapes_test.dart`, `forge2d_test.dart`, `svg_shooter_test.dart`,
  `tube_shooter_test.dart`, `tube_shooter_run_test.dart` (Tube Shooter's flights down Tube Runner's tube),
  `tube_runner_test.dart` and `revolute_pinball_test.dart`: each game loads with each renderer, follows its rules, and
  goes on from where it was with a new renderer.

The integration tests, in `integration_test/`, run on a device, with
`flutter test integration_test/<file> -d <macos | an iPhone's UDID | emulator-5554>`:

- `knobs_test.dart`, on a phone: the Svg menu reaches its last SVG, above the system's bars. The app sits in the safe
  area, because Flutter's menus can be as tall as the screen, but are placed in its safe area. The Renderer knob's GPU
  entries are active where their renderers are supported, and then show the graphics API, such as Metal (mesh). The
  knob picks the first active one, but keeps the Canvas of a link. Tube Shooter's Glow knob shows with the first
  active renderer.
- `renderers_test.dart`: each renderer draws all 27 SVGs, every other one faded, with 100 in the ring, and
  flame_rasterizer draws them in one run. Then the test changes the other knobs in place, and switches between
  renderers.
- `collidable_test.dart`: Collidable Svgs with each renderer, with 4 and 50 SVGs, for about two seconds.
  flame_rasterizer draws them in one run, and they stay in the arena.
- `multiple_shapes_test.dart`: Multiple Shapes with each renderer and both kinds of shapes, 15 of them, for about two
  seconds. flame_rasterizer draws them in one run while some are tinted.
- `forge2d_test.dart`: Revolute Joint Svgs with each renderer. Three drops give 45 bodies, which stay inside the walls,
  and flame_rasterizer draws all the bodies in one run, with Pieces on.
- `svg_shooter_test.dart`: Svg Shooter with each renderer, firing for about two seconds. flame_rasterizer draws the SVGs
  in one run, and the game scores.
- `tube_shooter_test.dart`: after a warm-up, Tube Shooter with the mesh renderer on three tubes: the octagon, closed,
  the horseshoe, open, and the star, concave. Each plays a round with its glow on and off: its zoom, two seconds of
  fire round the rim without zappers, and its drop. flame_rasterizer draws the paths in one run, and the game makes the
  tube's path again each frame of the zoom and the drop. Then, except on web, it plays a whole game with each GPU
  renderer, with the glow on, and none of its frames may fall back to the canvas renderer.
- `app_icons_test.dart`, on macOS: captures the standalone games' app icons, for `tool/make_icons.py`, which runs it.

Each test but `app_icons_test.dart` prints `RASTERIZER_EXAMPLE` lines with its results: each game's status, and for Svg
Shooter and Tube Shooter, the score. On web, these tests run with `flutter drive`, through the repository's
`tool/device_tests.py`, with device `chrome`.

From a clean checkout, build the app once (`flutter build macos`, `flutter build ios`, `flutter build linux`,
`flutter build windows`, or `flutter build apk --debug --target-platform android-arm64`) before `flutter test`.
Otherwise `flutter test` checks the assets before rasterizer_gpu's build hook has written its shader bundle.

## Android

The app leaves Impeller's backend to Flutter, which picks OpenGL ES on the emulator and on devices whose Vulkan can't
work. A debug or profile build made with the environment variable `IMPELLER_BACKEND=vulkan` or
`IMPELLER_BACKEND=opengles` asks for that backend in its manifest. Release builds ignore it. The app crashes at launch
where the backend it asks for can't start: Vulkan on some older GPUs, and any backend below API 29, where Flutter
renders with Skia.

On the emulator's Vulkan with its host GPU, the canvas renderer can't draw the heaviest frames (see rasterizer_gpu's
README). That Vulkan has other problems too:

- With KosmicKrisp, the emulator's default where the Mac supports Metal 4, 100 tigers take seconds per frame and never
  reach the screen, and opening the Svg dropdown over 100 SVGs can make the emulator quit.
- With MoltenVK, 100 SVGs hang the app with Flutter 3.47.9, and come out empty or wrong with Flutter 3.50.0.
  Widgetbook's Navigation, Addons and Knobs panels don't show either: the screen dims, but nothing draws above the
  dimming, even in a plain Flutter app with Flutter 3.50.0
  ([flutter#196603](https://github.com/flutter/flutter/issues/196603)).

On that Vulkan, run `renderers_test.dart` with `--name "^(GPU|Flame SVG)"`, which leaves out Canvas's games and the
switching test. On OpenGL ES, it runs in full.

## The SVGs' licences

The SVGs come from [flame_extended_svg](https://github.com/adario/flame_extended_svg), under this repository's MIT
licence, with three exceptions (see `assets/README.md`):

- Svg Shooter's `rocket_ship.svg`, `missile.svg` and `spaceship_game.svg` are CC0, from SVG Repo;
- the wireframes are under their originals' terms;
- `tiger.svg` is AGPL. It stays out of flame_rasterizer's pub.dev package (`assets/.pubignore`), so the example in that
  package can't load it, and says so.
