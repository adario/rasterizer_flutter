part of 'revolute_pinball_example.dart';

/// What a game for another renderer goes on from: the wheel, the bodies with
/// how long the last ones dropped have been at rest and whether they've
/// scored, the next body's color, and the HUD's values.
///
/// It leaves out the trails, the kicks, and the bodies that a bucket empties.
/// The bodies in a bucket are at rest in the new game.
typedef RevolutePinballSnapshot = ({
  WheelSnapshot? wheel,
  List<({BallSnapshot ball, double? rest, bool scored})> balls,
  List<({SvgBodySnapshot svgBody, double? rest, bool scored})> svgBodies,
  int tint,
  int score,
  int drops,
  double drainedArea,
  bool started,
  bool over,
  bool queued,
});

/// Takes a [RevolutePinballExample]'s snapshot, and goes on from one.
extension RevolutePinballSnapshots on RevolutePinballExample {
  RevolutePinballSnapshot get snapshot {
    bool kept(BodyComponent body) =>
        body.isLoaded && !_buckets.any((bucket) => bucket.empties(body));
    return (
      wheel: switch (_wheel) {
        final wheel? when wheel.isLoaded => wheel.snapshot,
        _ => null,
      },
      balls: [
        for (final ball in balls)
          if (kept(ball))
            (
              ball: ball.snapshot,
              rest: _current[ball],
              scored: scored.contains(ball),
            ),
      ],
      svgBodies: [
        for (final svgBody in svgBodies)
          if (kept(svgBody))
            (
              svgBody: svgBody.snapshot,
              rest: _current[svgBody],
              scored: scored.contains(svgBody),
            ),
      ],
      tint: tint,
      score: score,
      drops: _drops,
      drainedArea: drainedArea,
      started: _started,
      over: _over,
      queued: _queued,
    );
  }

  /// Adds the snapshot's bodies again, and its values. Call it once the table
  /// is built.
  void _goOnFrom(RevolutePinballSnapshot from) {
    void add(
      BodyComponent body,
      BodySnapshot snapshot,
      double? rest, {
      required bool hasScored,
    }) {
      addBody(body);
      if (rest != null) {
        _current[body] = rest;
      }
      if (hasScored) {
        scored.add(body);
      }
      final position = snapshot.position.toOffset();
      if (_buckets.any((bucket) => bucket.holds(position))) {
        settled.add(body);
      }
    }

    for (final (:ball, :rest, :scored) in from.balls) {
      add(Ball.from(ball), ball.body, rest, hasScored: scored);
    }
    for (final (:svgBody, :rest, :scored) in from.svgBodies) {
      add(svgBodyFrom(svgBody), svgBody.body, rest, hasScored: scored);
    }
    tint = from.tint;
    score = from.score;
    _drops = from.drops;
    drainedArea = from.drainedArea;
    _started = from.started;
    _queued = from.queued;
    if (from.over) {
      _endGame();
    }
  }
}
