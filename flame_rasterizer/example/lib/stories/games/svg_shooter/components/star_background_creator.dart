import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/components/star_component.dart';
import 'package:flame_rasterizer_example/stories/games/svg_shooter/svg_shooter_example.dart';

/// Adds Rogue Shooter's stars: rows of falling stars, with a new row at the
/// top each time they've fallen by a row's gap.
///
/// Each star is a sprite of [image], which [starImage] makes, at a random
/// size.
class StarBackgroundCreator(final Image image)
    extends Component
    with HasGameRef<SvgShooterExample> {
  /// The rows of stars at the start, spread over the game's height.
  static const rows = 12;

  /// The stars in a row.
  static const starsInRow = 6;

  /// The width of the smallest stars. Rogue Shooter's stars are all 20 wide,
  /// while these are 3 to 15 wide, at random.
  static const minSize = 3.0;

  /// The width of the largest stars.
  static const maxSize = 15.0;

  /// Pale yellow: a lighter amber than ExampleColors', so that no star looks
  /// like an amber enemy.
  static const color = Color(0xFFFDE68A);

  /// The image's width and height, in pixels. It's larger than the stars, to
  /// stay sharp on screens with several pixels per logical pixel.
  static const _imageSize = 64;

  late final _sprite = Sprite(image);

  @override
  void onLoad() {
    final starGapTime = (gameRef.size.y / rows) / StarComponent.speed;

    add(
      TimerComponent(
        period: starGapTime,
        repeat: true,
        onTick: () => _createRowOfStars(0),
      ),
    );

    _createInitialStars();
  }

  /// Creates the stars' image: a circle of [color] that fades out from its
  /// center to its edge, like the soft circles of Flame's
  /// `CircleParticleRenderer`.
  static Future<Image> starImage() {
    const radius = _imageSize / 2;
    const center = Offset(radius, radius);
    final paint = Paint()
      ..shader = Gradient.radial(center, radius, [
        color,
        color.withValues(alpha: 0),
      ]);
    final recorder = PictureRecorder();
    Canvas(recorder).drawCircle(center, radius, paint);
    // toImageSafe also disposes of the picture.
    return recorder.endRecording().toImageSafe(_imageSize, _imageSize);
  }

  void _createStarAt(double x, double y) {
    final random = gameRef.random;
    final size = minSize + (maxSize - minSize) * random.nextDouble();
    gameRef.starGroup.add(
      StarComponent(
        sprite: _sprite,
        position: Vector2(x, y),
        size: Vector2.all(size),
      )..paint.filterQuality = FilterQuality.medium,
    );
  }

  void _createRowOfStars(double y) {
    final random = gameRef.random;
    final starGap = gameRef.size.x / starsInRow;

    for (var i = 0; i < starsInRow; i++) {
      _createStarAt(
        starGap * i + (random.nextDouble() * starGap),
        y + (random.nextDouble() * 20),
      );
    }
  }

  void _createInitialStars() {
    final rowGap = gameRef.size.y / rows;

    for (var i = 0; i < rows; i++) {
      _createRowOfStars(i * rowGap);
    }
  }
}
