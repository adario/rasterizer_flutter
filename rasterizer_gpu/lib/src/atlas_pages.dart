import 'dart:math' as math;

import '../rasterizer_gpu.dart' show RasterizerPixelSize, RasterizerRenderer;

/// The sizes of a renderer's pages, without their textures.
///
/// The GPU renderer keeps the textures of its atlas pages itself. The mesh
/// renderer uses one page per run: the size of the run's target, which is the
/// same in every frame in flight.
///
/// Page sizes are multiples of [step]. A page grows at once to what a frame
/// needs. It shrinks rarely, because reallocating its textures stalls. On the
/// Android emulator's Vulkan, reallocating them back and forth every frame
/// also garbled frames or hung the GPU.
///
/// So a page shrinks at most once every [window] frames. At the end of each
/// window, it shrinks to the largest size those frames needed, if that size
/// is below [shrinkBelow] of its area. When the viewport changes size, as
/// with a rotation or a window resize, a new window starts. At its end, the
/// page shrinks to what that window's frames needed, however little that
/// saves. [trim] shrinks the pages to the last frame's needs at once.
///
/// It releases the last page once no frame has needed it for [window]
/// frames, then the page before it, and so on.
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

  // The viewport's size, the number of frames in the current window, and
  // whether a viewport change started that window. Per page, the largest
  // extents the window's frames needed, and the last frame's needs, for
  // [trim].
  RasterizerPixelSize? _viewport;
  int _windowFrames = 0;
  bool _changed = false;
  final List<RasterizerPixelSize> _windowNeeds = [];
  List<RasterizerPixelSize> _lastNeeds = const [];

  /// The number of pages.
  int get length => _widths.length;

  /// Returns page [p]'s size.
  RasterizerPixelSize operator [](int p) =>
      (width: _widths[p], height: _heights[p]);

  /// Grows page [p] to fit [w] x [h], and returns its size.
  ///
  /// When [p] equals [length], this adds a new page of that size.
  RasterizerPixelSize fit(int p, int w, int h) {
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
    return this[p];
  }

  /// Ends a frame for a [width] x [height] viewport.
  ///
  /// [needs] holds the extents of the pages that the frame's runs needed,
  /// packed together. At the end of a window, this shrinks the pages. It
  /// also releases the last pages that no frame needed for [window] frames.
  void endFrame(int width, int height, List<RasterizerPixelSize> needs) {
    _lastNeeds = needs;
    final viewport = (width: width, height: height);
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
      final need = needs[p];
      if (p == _windowNeeds.length) {
        _windowNeeds.add(need);
      } else {
        final largest = _windowNeeds[p];
        _windowNeeds[p] = (
          width: math.max(need.width, largest.width),
          height: math.max(need.height, largest.height),
        );
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
  void _shrink(List<RasterizerPixelSize> needs, {bool rarely = false}) {
    for (var p = 0; p < length && p < needs.length; p++) {
      final w = math.min(_widths[p], _up(needs[p].width)),
          h = math.min(_heights[p], _up(needs[p].height));
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

  /// Returns [v] rounded up to a multiple of [step], clamped from [step] to
  /// [maxSize].
  int _up(int v) => ((v + step - 1) ~/ step * step).clamp(step, maxSize);
}
