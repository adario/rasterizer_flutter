import 'dart:math' as math;
import 'dart:typed_data';

/// Groups a GPU run's entries into parts by their rectangles.
///
/// Entries whose rectangles overlap share a part, and so do chains of such
/// entries, so entries in different parts never touch. A part's rectangle is
/// the union of its entries' rectangles. A new entry joins every part its
/// rectangle overlaps, then every part that the grown rectangle overlaps.
///
/// A sweep over the entries' left edges compares each entry only with the
/// parts still open at that edge, and union-find tracks which parts were
/// joined. Two parts' rectangles may still overlap. That's harmless, because
/// each part's rectangle in the atlas holds only its own entries.
///
/// Overlapping parts can add up to more area than their bounding box, as
/// when a run's entries spread over the viewport. The entries then become one
/// part, that box. It takes no more of the atlas, and it packs into a smaller
/// page than the parts would side by side on the page's shelves (rows).
class AtlasParts() {
  // Indexed by an entry's position in the sorted ids: its union-find parent
  // and, after the parts are added, the part index of a root entry.
  Int32List _parents = Int32List(256), _parts = Int32List(256);

  // The open and the finished parts, 5 ints each: the rectangle (lx, ly, ux,
  // uy), then the position of one of the part's entries in the sorted ids.
  final List<int> _active = [], _done = [];

  /// Groups the entries [ids] into parts.
  ///
  /// [rects] holds each entry's rectangle by id, 4 ints each: lx, ly, ux, uy.
  /// No rectangle may be empty. This sorts [ids] in place by left edge. It
  /// passes each part's rectangle to [addPart], which returns the part's
  /// index, then each entry's id and part index to [setPart].
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
      // overlaps, until no part overlaps it.
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
    if (_oneBox(done, n, ids, addPart, setPart)) {
      return;
    }
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

  /// Makes the [n] entries [ids] one part, the bounding box of [parts], if
  /// that box's area is less than the parts' total area.
  ///
  /// Returns whether it did.
  static bool _oneBox(
    List<int> parts,
    int n,
    List<int> ids,
    int Function(int lx, int ly, int ux, int uy) addPart,
    void Function(int id, int part) setPart,
  ) {
    if (parts.length <= 5) {
      return false;
    }
    var lx = parts[0], ly = parts[1], ux = parts[2], uy = parts[3], area = 0;
    for (var m = 0; m < parts.length; m += 5) {
      lx = math.min(lx, parts[m]);
      ly = math.min(ly, parts[m + 1]);
      ux = math.max(ux, parts[m + 2]);
      uy = math.max(uy, parts[m + 3]);
      area += (parts[m + 2] - parts[m]) * (parts[m + 3] - parts[m + 1]);
    }
    if ((ux - lx) * (uy - ly) >= area) {
      return false;
    }
    final part = addPart(lx, ly, ux, uy);
    for (var k = 0; k < n; k++) {
      setPart(ids[k], part);
    }
    return true;
  }
}
