import 'dart:math' as math;

import '../rasterizer_gpu.dart' show RasterizerRenderer;

/// The sizes of a renderer's pages, without their textures.
///
/// The GPU renderer keeps the textures of its atlas pages alongside. The mesh
/// renderer has a page per run, the size of the run's target, the same in
/// every frame in flight.
///
/// Pages are sized in multiples of [step]. They grow at once to what a frame
/// needs. They shrink rarely, as reallocating their textures stalls. On the
/// Android emulator's Vulkan, reallocating them back and forth frame by frame
/// also garbled frames or hung the GPU.
///
/// So a page shrinks at most once every [window] frames. At the end of each
/// window, it shrinks to the largest size those frames needed, if that's
/// below [shrinkBelow] of its area. If the viewport changed size during the
/// window, as with a rotation or a window resize, it shrinks to that size
/// whatever it is. [trim] shrinks the pages to the last frame's needs at once.
///
/// A page that no frame needed for [window] frames is released. Pages are
/// released from the last one down.
class AtlasPages(
  final int maxSize, {
  final int window = 120,
  final int step = RasterizerRenderer.atlasStep,
  final double shrinkBelow = 0.5,
}) {
  /// How many times pages have changed size, new pages included.
  ///
  /// Each change reallocates the page's textures.
  int resizes = 0;

  final List<int> _widths = [], _heights = [], _idle = [];

  // The viewport's size, the window's frames so far, whether the viewport
  // changed during the window, and per page, the largest extents those frames
  // needed. Then the last frame's needs, for [trim].
  (int, int)? _viewport;
  int _windowFrames = 0;
  bool _changed = false;
  final List<(int, int)> _windowNeeds = [];
  List<(int, int)> _lastNeeds = const [];

  /// The number of pages.
  int get length => _widths.length;

  /// Page [p]'s size.
  (int, int) operator [](int p) => (_widths[p], _heights[p]);

  /// Grows page [p] to fit [w] x [h], and returns its size.
  ///
  /// [p] equal to [length] adds a new page, at that size.
  (int, int) fit(int p, int w, int h) {
    if (p == length) {
      _widths.add(0);
      _heights.add(0);
      _idle.add(0);
    }
    if (w > _widths[p] || h > _heights[p]) {
      _widths[p] = math.max(_widths[p], _up(w));
      _heights[p] = math.max(_heights[p], _up(h));
      resizes++;
    }
    return (_widths[p], _heights[p]);
  }

  /// Ends a frame for a [width] x [height] viewport, whose runs, packed
  /// together, needed pages of the [needs] extents.
  ///
  /// At the end of a window, this shrinks the pages. It also releases the
  /// pages that no frame needed for [window] frames.
  void endFrame(int width, int height, List<(int, int)> needs) {
    _lastNeeds = needs;
    final viewport = (width, height);
    if (viewport != _viewport) {
      // The first frame's viewport isn't a change, as there was none before.
      if (_viewport != null) {
        _windowFrames = 0;
        _windowNeeds.clear();
        _changed = true;
      }
      _viewport = viewport;
    }
    for (var p = 0; p < needs.length; p++) {
      final (w, h) = needs[p];
      if (p == _windowNeeds.length) {
        _windowNeeds.add((w, h));
      } else {
        final (ww, wh) = _windowNeeds[p];
        _windowNeeds[p] = (math.max(w, ww), math.max(h, wh));
      }
    }
    if (++_windowFrames == window) {
      _shrink(_windowNeeds, rarely: !_changed);
      _windowFrames = 0;
      _windowNeeds.clear();
      _changed = false;
    }
    for (var p = 0; p < length; p++) {
      _idle[p] = p < needs.length ? 0 : _idle[p] + 1;
    }
    while (length > 0 && _idle.last >= window) {
      _removeLast();
    }
  }

  /// Shrinks the pages to the last frame's needs, and releases the pages it
  /// didn't need.
  void trim() {
    _shrink(_lastNeeds);
    while (length > _lastNeeds.length) {
      _removeLast();
    }
  }

  /// Shrinks the pages to [needs].
  ///
  /// With [rarely], it shrinks only the pages whose new area would be below
  /// [shrinkBelow] of their area.
  void _shrink(List<(int, int)> needs, {bool rarely = false}) {
    for (var p = 0; p < length && p < needs.length; p++) {
      final w = math.min(_widths[p], _up(needs[p].$1)),
          h = math.min(_heights[p], _up(needs[p].$2));
      if (w == _widths[p] && h == _heights[p]) {
        continue;
      }
      if (rarely && w * h >= shrinkBelow * _widths[p] * _heights[p]) {
        continue;
      }
      _widths[p] = w;
      _heights[p] = h;
      resizes++;
    }
  }

  void _removeLast() {
    _widths.removeLast();
    _heights.removeLast();
    _idle.removeLast();
  }

  /// [v] rounded up to a multiple of [step], from [step] to [maxSize].
  int _up(int v) => ((v + step - 1) ~/ step * step).clamp(step, maxSize);
}
