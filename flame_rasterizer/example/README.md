# flame_rasterizer_example

[flame_rasterizer](..)'s example app. It shows flame_rasterizer's SVGs next to flame_svg's, in a
[Widgetbook](https://pub.dev/packages/widgetbook) laid out as Flame's own examples are. Run it with
`flutter run -d <macos | chrome | an iPhone | emulator-5554 | linux>`. On an iPhone, pick your development team in Xcode
first (Runner ▸ Signing & Capabilities), as the project has none.

The example runs on Flame's main: flame 2.0.0-dev, flame_svg 3.0.0-dev and flame_forge2d 0.21.0-dev, through the
workspace's dependency overrides (the root `pubspec.yaml`), as Flame's examples do. On web, flame_rasterizer draws with
the canvas renderer.

## Shared knobs and SVGs

Every use case has a Renderer knob (see [Svg Renderers](#svg--svg-renderers)) and a status bar under the game. They also
share these knobs:

- **Zoom**: the camera's zoom, from 0.25× to 5×.
- **Speed**: the game's speed, from 0, which stands still, to 2×.
- **Cache mode** and **Cache size**: flame_svg's image cache, shown with Flame SVG only. Tube Shooter, which draws no
  SVGs, doesn't have them.

Zoom and Speed are continuous sliders, which show their values to two decimals. A new renderer makes a new game. So does
a new cache, except in Svg Renderers, which loads its SVG again in the running game. The other knobs change the running
game.

The use cases other than Svg Renderers, Svg Shooter and Tube Shooter pick their SVGs at random from 14 of the 27
(`randomSvgNames`, in `commons/svg_renderers.dart`). They leave out:

- setup_merge and recycle_merge, which pair with setup and recycle in Svg Renderers;
- prism and spaceship_2, which stay in Svg Renderers;
- Svg Shooter's rocket_ship, missile, spaceship_game and wireframes (`wireframe/`);
- tiger, until the cost of its hitboxes and Box2D pieces is measured.

Collidable Svgs and Revolute Joint Svgs follow [flame_path_shapes](https://github.com/adario/flame_path_shapes), a Flame
examples app with path shapes, which isn't part of Flame. Multiple Shapes follows Flame's own
[`MultipleShapesExample`](https://github.com/flame-engine/flame/blob/main/examples/lib/stories/collision_detection/multiple_shapes_example.dart).

## Svg ▸ Svg Renderers

One SVG rotates in the centre, inside a ring of more. Each SVG in the ring is smaller than the one before, and rotates
a little later. Its knobs, in Widgetbook's panel, pick:

- **Renderer**, one of:
  - GPU (mesh): flame_rasterizer with rasterizer_gpu's mesh renderer, its default, which imports each SVG once into
    triangles;
  - GPU (atlas): flame_rasterizer with rasterizer_gpu's atlas renderer, which rasterizes the SVGs into an atlas each
    frame;
  - Canvas: flame_rasterizer with the canvas renderer everywhere (`RasterizerGpu.forceCanvas`);
  - Flame SVG: flame_svg.

  A GPU entry is inactive where its renderer isn't supported: on web, off Impeller, and on OpenGL ES until its
  self-test passes. The example starts the self-tests, the mesh renderer's first. GPU (mesh) is the first choice, or
  Canvas where GPU (mesh) is inactive. Widgetbook's dropdown can't make an entry inactive, so this knob is the
  example's own (`commons/renderer_knob.dart`).
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
- the tiger, the heaviest SVG. With GPU (atlas), its build time is the core's work and the atlas' upload, every frame.
  With GPU (mesh), it's imported once, and a frame costs the CPU what a light SVG's does, but its tens of thousands of
  triangles cost the GPU at every zoom;
- alien, invader_1, invader_2, recycle, recycle_merge, setup and setup_merge, which use clip paths. flame_rasterizer
  doesn't support clip paths, so it draws these SVGs unclipped.

## Svg ▸ Collidable Svgs

After flame_path_shapes' `CollidableSvgPathsExample`. SVGs picked at random, as above, move and spin in an arena the
size of the game at a zoom of 1. Their hitboxes are flame_rasterizer's `SvgHitbox`es, in the shape of their paths,
whatever draws them. Two SVGs that collide swap their velocities, and one that hits a wall bounces off it.

Collisions are checked once a frame, after the moves. So on a long frame, a small, fast SVG can cross a wall without
touching it. One whose centre went past a wall comes back to it, moving away from it.

Its knobs pick:

- **Renderer**: as above, with the same hitboxes for all.
- **SVG Number**: 2 to 50, 4 by default, in the running game. New SVGs come in where there's room, or the last ones go.
  All the SVGs shrink again when too many wouldn't fit.
- **Zoom**: the camera's zoom on the arena, whose walls stay put.
- **Speed**: as above.
- **Cache mode** and **Cache size**: as above. A new cache makes a new game.

The status bar adds the collisions so far. Hitboxes aren't drawn.

## Collision Detection ▸ Multiple Shapes

After Flame's `MultipleShapesExample`. Shapes made from SVGs picked at random, as above, 50 to 150 wide, fill the arena
in rows, with a snowman of three `CircleHitbox`es. They move, spin, and wrap around the arena's walls. Their hitboxes
are `SvgHitbox`es of the SVGs' outlines, whatever draws them. While a shape collides with another, Flame's `tint` turns
it green, and on a wall, purple. The snowman's circles take their own colours. Drag a shape to throw it.

Its knobs pick:

- **Renderer**: as above.
- **Shapes**: Paths, by default, or SVGs, drawn as they are. A path shape is its SVG's outline (`SvgOutline.path`) as
  one path, with two paint layers: a fill in a colour of its own at an alpha of 0.8, and a round stroke in a lighter
  colour, 1/50 of the outline's longer side wide. flame_rasterizer draws paths with `RasterizerPathComponent`, and
  Flame SVG with Flame's `PathComponent`. The shapes of one SVG share one path, sized by their components' scale, so
  with flame_rasterizer they share one scene, tinted or not. New shapes make a new game, as a new renderer does.
- **Shape Number**: 2 to 50, 15 by default, not counting the snowman, in the running game. As in Collidable Svgs, new
  shapes come in where there's room, or the last ones go. The rows' widths, gap and height share one scale: the
  largest, up to 1, at which the rows hold that many shapes. It's 1 up to about 20 shapes in a 1280×692 game, and 0.62
  at 50. In the emulator's 411×851, it's 0.66 at 15 and 0.40 at 50. All the shapes are resized to it. The snowman keeps
  the size it has in Flame's example.
- **Zoom** and **Speed**: as in Collidable Svgs.
- **Cache mode** and **Cache size**: as in Collidable Svgs, with SVGs only, as paths use no flame_svg cache.

The status bar adds the shapes, and the ones colliding now.

Things to look at:

- the runs. flame_rasterizer draws one, however many shapes are tinted, SVGs or paths, as it folds a tint into each
  SVG's or path's paints rather than drawing a layer per tint;
- the raster time and the targets' or atlas' size, while shapes are tinted and while none are;
- with Paths, Flame's `PathComponent`, which draws each path with the canvas, against flame_rasterizer's.

## Forge2D ▸ Revolute Joint Svgs

After flame_path_shapes' `RevoluteJointWithMotorExample`, which extends Flame's Forge2D example. In a `Forge2DGame` at
10 pixels a meter, a motor turns a wheel of five circles under a funnel of two ramps. Walls run along the game's edges
at a zoom of 1. Each tap drops 15 bodies, half balls and half SVGs picked at random as above, 3 to 3.5 m at their
longer side. They fall through the funnel into the wheel.

The SVG bodies collide as the convex pieces of their outlines, made once for each SVG and size
(`commons/forge2d.dart`). An `SvgHitbox` of the SVG's `outline`, sampled every 0.1 m, gives polygons, and Flame's
`convexPieces` cuts them into polygons of at most 8 vertices, as Box2D takes them. Pieces under 0.1 m across, about a
pixel, are left out, as flame_forge2d warns about them: a few of robot's and spaceship's at their smallest sizes.

Its knobs pick:

- **Renderer**: as above.
- **Pieces**: off by default. It draws the SVG bodies' convex pieces over them, those dropped before too, to show how
  closely the bodies follow the SVGs.
- **Zoom**: the camera's zoom, on top of the world's 10 pixels a meter. The walls stay put.
- **Speed**: the physics' speed.
- **Cache mode** and **Cache size**: as in Collidable Svgs.

The status bar adds the balls and SVGs dropped. As in flame_path_shapes, the number of bodies, the walls, ramps and
wheel included, is at the top right.

Things to look at: the runs. flame_rasterizer draws one, however many bodies fall. The SVG bodies have a higher priority
than the balls, walls, ramps and wheel, which the canvas draws, so they draw above them, all in one run. In the
component tree's order, the balls between them would end a run at nearly every SVG body, and with the mesh renderer,
each run has a target of its own. Bodies don't overlap, so the game looks the same. A Forge2D game can do the same: give
its vector bodies a priority above its canvas-drawn ones. Pieces draws after all the bodies, which keeps the SVGs in one
run too.

The game destroys its Box2D world as it's removed: Box2D has room for 128 worlds at once, and Flame's `Forge2DWorld`
doesn't destroy its own.

flame_forge2d's forge2d binds Box2D's C library. Its build hook compiles the library with the platform's C toolchain, as
rasterizer_gpu's hook does its core. On web, forge2d loads Box2D's WebAssembly build, bundled as an asset.

## Games ▸ Svg Shooter

After Rogue Shooter, one of Flame's example games, with SVGs for its sprites, as wireframes in colour
(`stories/games/svg_shooter/`, a file per component). The world uses the original's coordinates: the game's, at a zoom
of 1.

- **Controls.** Drag anywhere, or use the arrow keys or WASD, to move the player's spaceship, spaceship_game. Drag, or
  hold the space bar, to fire. The keys move the player at 400 world units a second, as fast diagonally, within the
  play area. From outside it, where a drag can take the player, the keys only move it toward the play area. The keys
  work wherever there's a keyboard. A click on the game takes them back from Widgetbook's knobs.
- **Missiles.** Each volley is three missiles, the original's five without the outermost two, every 0.15 s. The first
  volley fires at once, but never sooner than 0.15 s after the last.
- **Enemies.** They come in waves of five every 1/15 s, 75 a second, a quarter fewer than the original's 100. Each is
  the wireframe of spaceship, spaceship_2 or rocket_ship, turned to face down, or of robot, picked at random. A
  wireframe, in `assets/svgs/wireframe/`, is its SVG's silhouette and a few of its shapes. Its lines are as wide on
  screen as the player's, about 1.2 at a zoom of 1.
  - Robots fall straight down at 135 a second, 10% slower than the original's 150. They swing as pendulums around their
    centres, hitboxes included: from upright to one side, then to the other, and back, 2 s a swing. Each swings by a
    whole number of degrees from 5 to 15, picked at random.
  - Spaceships and rockets are tilted by a whole number of degrees from −15 to 15, and fly where they point, at 135 a
    second give or take 10%, both picked at random. They fly until they're out of the bottom or a side.
  - A game starts with a first wave, as if the waves had been coming for a while. Its rows go from the top down to 20%
    of the game's height, well above the player, and the robots' swings are as far along as their fall.
- **Colours.** The player is in its SVG's orange, `#F09050`, and its missiles are filled in a lighter one, `#F5B58A`.
  The enemies are stroked in white, each tinted with one of Revolute Joint Svgs' six colours, picked at random. The GPU
  renderers draw a tint in the same run.
- **Sizes.** The player is 64 wide, about 15% smaller than the original's 75, and 42 high: its SVG's viewBox is cropped
  to the ship. The enemies are squares of 29, about 15% larger than the original's 25. The missiles are squares of 17,
  in the same ratio to the player's width as the original's 20 to its 75. Each has an `SvgHitbox` in the shape of its
  paths, whatever draws it. The enemies' hitboxes are passive.
- **Hits.** A missile on an enemy blows it up once, and scores. The explosion is the Explosion of Flame's particles
  example: a flash and 250 debris. Its distances are scaled so that it's twice an enemy across, 58, as the original's
  is 50, with dots of the same size. An enemy on the player blows up too, in reds rather than yellows, scores nothing,
  and takes 2% of the player's health. The health comes back, 2% a second, after 3 s without a hit.
- **Game over.** At 0%, the player blows up in red, twice its width across, 128. It turns red in 0.25 s and fades out
  over 2 s, while the world goes on. It neither moves, fires nor gets hit. Then the game is over: the world stops,
  whatever the Speed knob says, and drags neither move nor fire. Game Over shows until a tap starts a new game, in
  place.
- **Stars.** They're sprites of one pale yellow circle, `#FDE68A`, fading out from its centre, 3 to 15 across at
  random. They fall at 15 a second, half again as fast as the original's 10.

Its knobs pick:

- **Renderer**: as above, with the same hitboxes for all.
- **Zoom**: the camera's zoom on the play area. A drag moves the player as far as the finger, at any zoom.
- **Speed**: as above.
- **Cache mode** and **Cache size**: as in Collidable Svgs.

As in the original, the score and the number of components are at the bottom right, here under the health. With no
batching nor animations, the top left shows only the frame rate. Things to look at: the runs. flame_rasterizer draws
two while explosions are on screen, as their particles draw between the missiles and enemies, and the player.

## Games ▸ Tube Shooter

Inspired by Atari's Tempest (1981): a tube shooter with a tube, enemies, colours and numbers of its own
(`stories/games/tube_shooter/`, a file per component). It draws no SVGs: every line in it is a path, drawn by a
`RasterizerPathComponent`, or with Flame SVG, by Flame's `PathComponent`.

- **The tube.** A tube is the outline of lanes all as wide. The first is a hexagon, its corners 1 from its axis, with
  two lanes a side, 12 in all. Each tube is 2.8 deep, seen from an eye on its axis 1 before its rim, so that its far
  end is 3.8 times smaller. Its rim fits in 90% of the game's shorter side.
- **Line widths.** The lines are 4 device pixels wide at the rim, and thinner with depth, down to 1.05 at the far end.
  They're never under one device pixel, whatever the screen and the zoom, and neither are the shapes' strokes. The
  lines sit a sixteenth of a device pixel off the axis. So the two edges of a spoke along an axis cross the rows of
  samples of 4× MSAA in turn, and its width moves in steps of a quarter of a pixel, not half.
- **The tube's paths.** The tube's lines, its spokes, rim and far end, 25 to 60 of them, are filled quads, tapered by
  depth and squared off. They're one path in the level's colour, with a component of its own. flame_rasterizer takes a
  path as immutable, so the game makes this path again every frame of the zoom and of the drop, and as the window or
  the zoom changes. Over it:
  - the ship's lane, the same in sky, `#38BDF8`, made again as the ship changes lanes;
  - the spikes, periwinkle, `#7C9CFF`, one path for all of them, made again every frame that one grows or is shot;
  - the zappers' bolts, emerald, `#34D399`, which zigzag down their lanes, one path for all of them, made again every
    frame of a pulse.
- **The shapes.** The ship, a manta on the rim, the enemies, the shots and the explosions are each one stroked path, in
  lane units, which all their components share. Each component is a Flame transform that follows the projection: in
  its lane, at its depth, at the lane's angle, and scaled to the lane's width there. So the shapes move with no import.
  An enemy flips onto a neighbouring lane by turning about their shared corner, through the tube. An edge-walker walks
  the lanes' edges rather than their middles, spinning.
- **Controls.** The ship moves round the rim, up to an open tube's ends, 16 steps a lane. The arrow keys, or A and D,
  move it from 3 lanes a second up to 10, and a drag moves it a lane every 40 logical pixels. The ship fires down its
  lane with the space bar, or while dragging: a shot every 0.1 s, 8 at most, each crossing the tube in 0.5 s. Enter, or
  a double tap, purges the tube of its enemies and their shots, once a round.
- **Enemies.** A round's enemies, 12 on the first level, wait at the far end, as dots of their colours wandering round
  it. One comes every 2.5 s, with 4 at most in the tube or coming. The next one goes to its lane's middle, flashes white
  for 0.3 s, and comes up that lane. On the first level, they are:
  - 6 amber climbers, `#FBBF24`. They climb in 8 s, and flip to a neighbouring lane every 2 to 4 s. They fire up their
    lane every 3 to 5 s, with 2 enemy shots at most, each crossing in 3 s. At the rim, they flip toward the ship every
    0.8 s.
  - 2 rose splitters, `#FB7185`. They climb in 12 s. A splitter that's shot, or reaches the rim, splits into two
    climbers, which flip onto its neighbouring lanes.
  - 2 periwinkle seeders. They climb to 40% of the depth in 6 s, growing their lane's spike behind them, then go back
    down and climb another lane.
  - an emerald zapper, `#34D399`. It climbs in 10 s, flips to a neighbouring lane every 3 to 6 s, and doesn't fire.
    Every 3 s, after a 0.5 s white flash, it pulses for 0.6 s: a bolt down its lane, from it to the rim. At the rim, it
    flips toward the ship every 1.5 s.
  - a fuchsia edge-walker, `#E879F9`. It climbs an edge in 9 s, and every 1 to 2.5 s crosses a neighbouring lane to its
    other edge, in 0.4 s. Only then is it within a shot's reach. At the rim, it crosses toward the ship every 1.2 s.
- **Hits.** A shot meets what's in its lane within 4% of the depth, or what it passes in a frame. It destroys an enemy,
  and it and an enemy shot destroy each other. On a spike, it takes 6% of the spike's length off. Scores: a climber
  100, a splitter 150, a seeder 50, a zapper 200, an edge-walker 250, and a hit on a spike 2.
- **Losing the ship.** An enemy shot or a climber at the rim in the ship's lane, a pulse in its lane, or an edge-walker
  at the rim crossing its lane or on one of its edges destroys the ship. It blows up and fades out, and a life is lost.
  The enemies in the tube go back to the far end of their lanes, as dots, and the ship comes back 1.5 s later. After
  its 3 lives, Game Over shows and the game stands still, until a tap, or Enter, starts a new one.
- **READY.** At the end of each zoom, and once a lost ship is back, READY shows in the middle and nothing comes. A tap,
  counted only once READY is up, or any key but a modifier alone, begins the level. It does nothing else: no shot, no
  move of the ship, no purge.
- **Levels.** A round on each level in turn, then again from the first: the hexagon, floor, ridge, horseshoe, octagon,
  cog, star and diamond, from the easiest to the hardest, by an estimate of what each enemy asks of the ship. The eight
  tubes have 8 to 20 lanes. All of a tube's lanes are as wide, so that a shape's stroke is one number and a flip is a
  rigid turn.
  - Closed tubes: the octagon, hexagon, diamond, star and cog. The star and the cog are concave, and their flips round
    an inner corner turn by more than half a turn.
  - Open tubes: the floor, horseshoe and ridge, the ridge concave. There, the ship stops at the ends, an enemy that
    would leave the tube turns back, and the camera looks at the tube's middle, moving there during the zoom.

  Each level has about an enemy a lane, at least 12, of every kind. Its lines are violet, `#A78BFA`, orange, `#F97316`,
  lime, `#A3E635`, or slate, `#94A3B8`, in turn. A new tube imports each shape once, as its lanes' width changes the
  strokes, which are in lane units. The ship starts on its bottom lane.
- **Rounds.** Once a round's enemies are gone, the ship drops down its lane to the far end in 2 s, speeding up. The eye
  goes with it, so that the tube widens past the screen, its lines clipped before the eye. A spike in the ship's lane
  taller than its depth destroys it. Then the next round, 5% faster, zooms in from afar in 1 s, on the next level's
  tube, its spikes gone and its purge ready. Stars fly by on the drop and the zoom, and drift between them: the cut from
  the drop's end to the next tube is in mid-flight.
- **Explosions.** Each is a burst of 8 rays, which grows to twice its size in 0.5 s while it fades out. Unless the
  explosion is past 85% of the tube's depth, 8 more rays, between those, fly out from its middle for 1 s, fading out
  over the last 0.5 s. They're tinted to the colour of what blew up. They share one path, each ray a component of its
  own, and a tint costs no import. Everything that fades out does so by its opacity, which costs no import, so that it
  never hides the lines under it.
- **Dots.** The enemies to come, 3 device pixels across, and the stars are dots of one filled path, a regular octagon,
  each dot a component under a transform. A filled path's width is its transform's, so the dots cost no import as they
  move, whatever their sizes and the zoom: dots of one colour share one imported path. Tints, which cost none either,
  flash the dots, and opacity fades the stars.
- **Stars.** 200 white dots around the tube, never in it, up to 10 tube units from the eye. As the eye goes deeper,
  they come as much closer, so that they stream outward. They're twice as wide as the tube's lines at their distance,
  2 to 8 device pixels, and stretched into streaks from where they were the frame before. They're unseen at the
  farthest, and at their brightest from 4 tube units in.
  - While the eye goes slower than a tenth of its top speed on the drop, the stars come at that speed instead, 5%
    faster each round, as the game is. They drift, with streaks no longer than they're wide, plus a logical pixel. A
    star wholly past the screen's edge comes back as a new one, at the farthest, elsewhere.
  - In play, as the ship moves round the rim, the stars turn about the axis the other way, easing in over about 0.2 s,
    nearer ones more, as with parallax. A star 4 tube units from the eye turns half the ship's turn round a closed tube,
    and one elsewhere 4 over its distance times that. So their moves sideways grow with nearness, as their moves outward
    do. The stars' places turn, not their distances.
  - They fade in over 0.3 s as the game starts, and stay, still once it's over. With the Drifting stars knob off, they
    fade out over 0.3 s as the zoom ends, and are gone once the game is over.
- **Texts.** The game has its own font, `TubeFont`: capitals, digits, a space, a colon, a period and a dash. Each
  glyph is 1 to 3 straight polylines on a grid 4 wide and 6 tall, stroked an eighth of its height wide, with miter
  joins, none sharper than 60°, and square ends, as the shapes are. Each glyph is a path, which all its components
  share, so that a text set again, such as the score, only imports the glyphs that no other text shows. Each text is a
  component with a child per glyph, in the camera's viewport, in white:
  - the round, the lives, the purge and the score, at the bottom right, their capitals 12 logical pixels high;
  - the round's number in the middle during each zoom, READY, and Game Over, 40 high.

  They draw before the FPS, in the world's run.

Its knobs pick:

- **Renderer**: GPU (mesh), GPU (atlas) and Canvas draw with `RasterizerPathComponent`s, Flame SVG with Flame's
  `PathComponent`s. On web, the GPU entries are inactive, as Flutter GPU isn't available there, and the canvas renderer
  draws the paths.
- **Level**: the level a new game starts at, by its number and its tube's name, so that any tube can be seen without
  playing up to it.
- **Drifting stars**: on by default. On, the stars stay between the zoom and the drop. Off, they only show on those,
  and the mesh renderer's targets, which the stars spread over the window, can shrink in play. It changes the running
  game.
- **Glow**: shown with GPU (mesh) only, the one renderer that draws glows, and off by default. It makes the lines glow,
  thinner with depth, as they are: the shapes' glows 3 times as wide as their lines, and those of the tube, the ship's
  lane, the spikes and the bolts 2 times. It changes the running game, whose lines are imported again.
- **Zoom**: the camera's zoom on the tube, whose lines keep their widths in device pixels, as the game makes its paths
  and strokes again for it.
- **Speed**: as above.

The status bar shows the paths made a second, after the renderer's numbers. Things to look at:

- the runs: one with flame_rasterizer;
- the paths made a second: one a frame during the zoom and the drop, while seeders climb, and while zappers pulse, and
  the frame times then;
- the dots, the stars and the texts, which make no paths.

## Tests

`flutter test` runs the unit tests, in `test/`:

- `example_test.dart`: the Widgetbook builds. Each use case's knobs fit in windows 800, 840 and 1280 wide, in
  Widgetbook's sheet and side panel. flame_svg's knobs show only with Flame SVG, and Tube Shooter's Glow knob only with
  GPU (mesh). Zoom and Speed are continuous, shown to two decimals in tabular figures. Off Impeller, the GPU entries
  are inactive in the Renderer knob. With each renderer, faded or not, the Svg Renderers game loads, zooms and slows
  down in place, takes a new SVG, SVG number and fade in place, and shows a missing SVG's error.
- `cache_knobs_test.dart`: the other use cases' flame_svg knobs show only with Flame SVG, and in Multiple Shapes only
  with SVGs. It's a file of its own, as these games load SVGs at random with flame_svg, whose loads a file's tests
  share.
- `status_bar_test.dart`: the status bar keeps the game's size in windows 360 and 1600 wide, leaves blank the times it
  has no frames for, and shows one flame_svg cache total for all the SVGs.
- `removed_while_loading_test.dart`: a game removed while it loads stops loading.
- `collidable_test.dart`: Collidable Svgs loads with each renderer, with a hitbox for each SVG. Two SVGs that collide
  swap velocities. One that hits a wall bounces off it, one in a corner moves away from both walls, and one past a wall
  comes back. 50 stay in the arena. A new SVG number adds SVGs to the running game or removes some. At speed 0, the
  SVGs stand still. A resize while the game loads resizes the arena.
- `multiple_shapes_test.dart`: Multiple Shapes loads with each renderer and both shapes, with 15 shapes and a hitbox
  for each. An SVG's shapes share its path and one scene. A shape is tinted green on another and purple on a wall, all
  in one run, with both shapes. A new shape number adds shapes to the running game or removes some, resized. New shapes
  make a new game, as does a new cache with Flame SVG. At speed 0, the shapes stand still. A shape wholly outside the
  arena comes back in on the other side.
- `forge2d_test.dart`: each SVG's convex pieces fit Box2D at each size. A tap drops 15 bodies, which stay inside the
  walls, the SVG bodies in one run, with Pieces on too. 130 games, one after another, have room for their Box2D worlds.
- `svg_shooter_test.dart`: Svg Shooter loads with each renderer, with the player and each enemy hitboxed, and the
  health, the score and the number of components at the bottom right. Its waves, their first wave, the robots' swings,
  the tilted enemies, the player's drags, keys and volleys, its colours, the hits, the health, Game Over and the stars
  each have a test, with the numbers above.
- `tube_shooter_test.dart`: the octagon's tube has 16 lanes as wide, 1 from its axis, and is 3.8 times smaller at its
  far end. Its lines are 4 device pixels wide at the rim and 1.05 at the far end, never under a device pixel, and
  clipped before the eye on the drop. Every tube has lanes as wide, round its axis, and flips land on the neighbouring
  lane through the tube. The game loads with flame_rasterizer and with Flame's `PathComponent`, and zooms in, the
  tube's path made again each frame, in one run. The ship's moves and shots, each enemy, the dots, the stars, the glow,
  READY, the purge, the rounds, the drop, the texts and Game Over each have a test, with the numbers above. A whole
  game on each level draws no path with the canvas fallback.

The integration tests, in `integration_test/`, run on a device, with
`flutter test integration_test/<file> -d <macos | an iPhone's UDID | emulator-5554>`:

- `knobs_test.dart`, on a phone: the Svg menu reaches its last SVG, above the system's bars. The app sits in the safe
  area, as Flutter's menus can be as tall as the screen, but are placed in its safe area. The Renderer knob's GPU
  entries are active where their renderers are supported: GPU (mesh) is the first choice if it's supported from the
  start, else once the OpenGL ES self-tests pass, with Canvas kept. Tube Shooter's Glow knob shows with GPU (mesh).
- `renderers_test.dart`: each renderer draws all 27 SVGs, every other one faded, with 100 in the ring, and
  flame_rasterizer draws them in one run. Then the test switches between renderers.
- `collidable_test.dart`: Collidable Svgs with each renderer, with 4 and 50 SVGs, for about two seconds.
  flame_rasterizer draws them in one run, and they stay in the arena.
- `multiple_shapes_test.dart`: Multiple Shapes with each renderer and both shapes, 15 of them, for about two seconds.
  flame_rasterizer draws them in one run while some are tinted, with an entry for each shape. With the mesh renderer,
  there can be fewer, as it leaves out the entries outside the viewport, where a shape goes before it wraps around.
- `forge2d_test.dart`: Revolute Joint Svgs with each renderer. A tap and two drops give 45 bodies, which stay inside the
  walls, and flame_rasterizer draws the SVG bodies in one run, with Pieces on.
- `svg_shooter_test.dart`: Svg Shooter with each renderer, firing for about two seconds. flame_rasterizer draws the SVGs
  in at most two runs, and the game scores.
- `tube_shooter_test.dart`: after a warm-up, Tube Shooter with the mesh renderer on three tubes: the octagon, closed,
  the horseshoe, open, and the star, concave. Each runs with its glow on and off, six games in all, through its zoom,
  two seconds of fire sweeping round the rim, without zappers, and its drop, with their stars. flame_rasterizer draws
  the paths in one run, and the tube's path is made again each frame of the zoom and the drop. Then, except on web, it
  plays a whole game with each GPU renderer, none of whose frames may fall back to the canvas renderer or
  `Canvas.drawPath`.

Each test but `knobs_test.dart` prints a `RASTERIZER_EXAMPLE` line per game, with its status, and Svg Shooter's and
Tube Shooter's with the score, and Svg Shooter's with the health. On web, these tests run with `flutter drive`, through
the repository's `tool/device_tests.py`, with device `chrome`.

From a clean checkout, build the app once (`flutter build macos`, `flutter build ios`, `flutter build linux`, or
`flutter build apk --debug --target-platform android-arm64`) before `flutter test`. Otherwise `flutter test` checks the
assets before rasterizer_gpu's build hook has written its shader bundle.

The Android manifest asks for Impeller's Vulkan backend, as the emulator otherwise gets OpenGL ES. A build with
`IMPELLER_BACKEND=opengles` asks for OpenGL ES instead. Only debug and profile builds read the manifest's choice. Below
API 29, build with `IMPELLER_BACKEND=auto`. On the emulator's Vulkan with its host GPU, the canvas renderer hangs with
100 SVGs, as any frame of more than about 800 draws does there (see rasterizer_gpu's README). There,
`renderers_test.dart` runs with `--name "^(GPU|Flame SVG)"`, without Canvas's games and the switching test, and in full
with `IMPELLER_BACKEND=opengles`.

## The SVGs' licences

The SVGs come from [flame_extended_svg](https://github.com/adario/flame_extended_svg), under this repository's MIT
licence, with three exceptions (see `assets/README.md`):

- Svg Shooter's `rocket_ship.svg`, `missile.svg` and `spaceship_game.svg` are CC0, from SVG Repo;
- the wireframes are under their originals' terms;
- `tiger.svg` is AGPL. It stays out of flame_rasterizer's pub.dev package (`assets/.pubignore`), where the example says
  it couldn't load it.
