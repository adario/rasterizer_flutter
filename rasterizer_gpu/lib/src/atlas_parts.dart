import 'dart:typed_data';

/// Groups a GPU run's entries into parts, by their rectangles.
///
/// Entries whose rectangles overlap share a part, and so do chains of such
/// entries. So entries in different parts never touch. A part's rectangle is
/// the union of its entries' rectangles. A new entry joins every part its
/// rectangle overlaps, then every part that the grown rectangle overlaps.
///
/// A sweep over the entries' left edges compares each entry only with the
/// parts still open there, and union-find tracks which parts were joined.
/// Two parts' rectangles may still overlap. That's harmless, as each part's
/// rectangle in the atlas holds only its own entries.
class AtlasParts() {
  // Per entry, by its position in the sorted ids: its union-find parent, and
  // once the parts are added, the part index of its root.
  Int32List _parents = Int32List(256), _parts = Int32List(256);

  // The open and the done parts, 5 ints each: their rectangle (lx, ly, ux,
  // uy) and the position of one of their entries in the sorted ids.
  final List<int> _active = [], _done = [];

  /// Groups the entries [ids] into parts.
  ///
  /// [rects] holds each entry's rectangle by id, 4 ints each: lx, ly, ux, uy.
  /// None may be empty. This sorts [ids] in place by left edge. It passes
  /// each part's rectangle to [addPart], which returns the part's index, then
  /// each entry's id and part index to [setPart].
  void group(
    Int32List rects,
    List<int> ids,
    int Function(int lx, int ly, int ux, int uy) addPart,
    void Function(int id, int part) setPart,
  ) {
    final n = ids.length;
    if (n == 0) {
      return;
    }
    ids.sort((a, b) => rects[4 * a] - rects[4 * b]);
    if (n > _parents.length) {
      _parents = Int32List(n * 2);
      _parts = Int32List(n * 2);
    }
    final parents = _parents;
    int find(int k) {
      while (parents[k] != k) {
        k = parents[k] = parents[parents[k]];
      }
      return k;
    }

    final active = _active..clear(), done = _done..clear();
    for (var k = 0; k < n; k++) {
      parents[k] = k;
      final e = 4 * ids[k];
      var lx = rects[e], ly = rects[e + 1], ux = rects[e + 2];
      var uy = rects[e + 3];
      // Parts that end at or left of this entry's left edge are done: no
      // later entry starts further left, so none can overlap them.
      var j = 0;
      for (var m = 0; m < active.length; m += 5) {
        if (active[m + 2] <= lx) {
          done.addAll(active.getRange(m, m + 5));
        } else {
          for (var c = 0; c < 5; c++) {
            active[j + c] = active[m + c];
          }
          j += 5;
        }
      }
      active.length = j;
      // Joins the parts the entry overlaps, then those its grown rectangle
      // overlaps, until there are none.
      for (var merged = true; merged;) {
        merged = false;
        for (var m = 0; m < active.length; m += 5) {
          if (active[m] < ux &&
              lx < active[m + 2] &&
              active[m + 1] < uy &&
              ly < active[m + 3]) {
            if (active[m] < lx) {
              lx = active[m];
            }
            if (active[m + 1] < ly) {
              ly = active[m + 1];
            }
            if (active[m + 2] > ux) {
              ux = active[m + 2];
            }
            if (active[m + 3] > uy) {
              uy = active[m + 3];
            }
            parents[find(active[m + 4])] = k;
            active.removeRange(m, m + 5);
            m -= 5;
            merged = true;
          }
        }
      }
      active.addAll([lx, ly, ux, uy, k]);
    }
    done.addAll(active);
    for (var m = 0; m < done.length; m += 5) {
      _parts[find(done[m + 4])] = addPart(
        done[m],
        done[m + 1],
        done[m + 2],
        done[m + 3],
      );
    }
    for (var k = 0; k < n; k++) {
      setPart(ids[k], _parts[find(k)]);
    }
  }
}
