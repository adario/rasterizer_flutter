part of 'revolute_pinball_example.dart';

/// What a game for another renderer goes on from: the wheel, the bodies with
/// how long the last ones dropped have been at rest, the next body's color,
/// and the HUD's values.
///
/// It leaves out the trails, the kicks, and the bodies that a bucket empties.
/// The bodies in a bucket are at rest in the new game.
typedef RevolutePinballSnapshot = ({
  BodySnapshot? wheel,
  List<({BallSnapshot ball, double? rest})> balls,
  List<({SvgBodySnapshot svgBody, double? rest})> svgBodies,
  int tint,
  int score,
  int drops,
  double drainedArea,
  bool started,
  bool over,
});

/// Takes a [RevolutePinballExample]'s snapshot, and goes on from one.
extension RevolutePinballSnapshots on RevolutePinballExample {
  RevolutePinballSnapshot get snapshot {
    bool kept(BodyComponent body) =>
        body.isLoaded && !_buckets.any((bucket) => bucket.empties(body));
    return (
      wheel: switch (_wheel) {
        final wheel? when wheel.isLoaded => wheel.body.snapshot,
        _ => null,
      },
      balls: [
        for (final ball in balls)
          if (kept(ball)) (ball: ball.snapshot, rest: _current[ball]),
      ],
      svgBodies: [
        for (final svgBody in svgBodies)
          if (kept(svgBody))
            (svgBody: svgBody.snapshot, rest: _current[svgBody]),
      ],
      tint: tint,
      score: score,
      drops: _drops,
      drainedArea: drainedArea,
      started: _started,
      over: _over,
    );
  }

  /// Adds the snapshot's bodies again, and its values. Call it once the table
  /// is built.
  void _goOnFrom(RevolutePinballSnapshot from) {
    void add(BodyComponent body, BodySnapshot snapshot, double? rest) {
      addBody(body);
      if (rest != null) {
        _current[body] = rest;
      }
      final position = snapshot.position.toOffset();
      if (_buckets.any((bucket) => bucket.holds(position))) {
        settled.add(body);
      }
    }

    for (final (:ball, :rest) in from.balls) {
      add(Ball.from(ball), ball.body, rest);
    }
    for (final (:svgBody, :rest) in from.svgBodies) {
      add(svgBodyFrom(svgBody), svgBody.body, rest);
    }
    tint = from.tint;
    score = from.score;
    _drops = from.drops;
    drainedArea = from.drainedArea;
    _started = from.started;
    if (from.over) {
      _endGame();
    }
  }
}
