"""Compares two frames byte for byte, except for the struct fields the core leaves unwritten and the shaders don't read.

The core copies opaques and instances from per-thread rows it doesn't zero, so those fields hold leftover heap bytes, which
differ between processes:
- An opaque cell's ox, oy and the rest of its union (bytes 12-27). Rasterizer.hpp writes only lx, ly, ux, uy, and the
  opaques shader reads only those. Opaque outlines use the whole union, and are compared.
- An instance's padding after cover (bytes 18-19).
- An edge fill instance's biid and molsbase (bytes 24-31), which only molecule fills set, and only molecule shaders read.

With --entries-only, only the entries' structs are compared, not the header: its colors and paths of paths the core culls are
unwritten too, so they hold whatever an earlier frame wrote into a reused buffer.

Such as two golden test runs' frames, recorded with GOLDEN_RECORD (see example/integration_test/golden_test.dart): where a
render differs from its golden, a different frame means it's the core's run-to-run variation, not a rendering change.

usage: python3 -I compare_frames.py a.bin b.bin entries.txt [--entries-only]
"""
import re
import struct
import sys
from collections import Counter

K_OUTLINES, K_MOLECULE, K_EDGE = 1 << 29, 1 << 25, 1 << 27
SIZES = {'quadEdges': 8, 'fastEdges': 8, 'fastMolecules': 8, 'quadMolecules': 8, 'opaques': 28, 'instances': 32,
         'blendInstances': 32, 'segmentsBase': 16}


def kind_of(name, iz):
    if name == 'opaques':
        return 'opaque outline' if iz & K_OUTLINES else 'opaque cell'
    if name in ('instances', 'blendInstances'):
        if iz & K_OUTLINES:
            return 'outline'
        return 'molecule fill' if iz & K_MOLECULE else 'edge fill' if iz & K_EDGE else 'solid fill'
    return name


UNREAD = {
    'opaque cell': set(range(12, 28)),
    'molecule fill': {18, 19},
    'edge fill': {18, 19} | set(range(24, 32)),
}


def main(a_path, b_path, entries_path, entries_only=False):
    a, b = open(a_path, 'rb').read(), open(b_path, 'rb').read()
    n = min(len(a), len(b))
    ignored = bytearray([entries_only] * n)      # 1 where a byte may differ
    structs = Counter()
    for line in open(entries_path):
        m = re.match(r'(\w+)\((\d+), (\d+)', line)
        if not m or m.group(1) not in SIZES:
            continue
        name, begin, end, size = m.group(1), int(m.group(2)), int(m.group(3)), SIZES[m.group(1)]
        for at in range(begin, min(end, n), size):
            kind = kind_of(name, struct.unpack_from('<I', a, at)[0])
            structs[kind] += 1
            if entries_only:
                ignored[at:at + size] = bytes(len(ignored[at:at + size]))
            for offset in UNREAD.get(kind, ()):
                ignored[at + offset] = 1
    differ = [i for i in range(n) if a[i] != b[i]]
    unexplained = [i for i in differ if not ignored[i]]
    print(f'{n} bytes compared, {len(differ)} differ, {len(differ) - len(unexplained)} of them in unread fields')
    print('structs: ' + ', '.join(f'{count} {kind}' for kind, count in sorted(structs.items())))
    if len(a) != len(b):
        print(f'sizes differ: {len(a)} and {len(b)}, compared the first {n}')
    if unexplained:
        print(f'bytes: DIFFERENT, {len(unexplained)} in read fields, the first at {unexplained[0]}')
        return 1
    print('bytes: identical, except for unread fields')
    return 0


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:4], entries_only='--entries-only' in sys.argv[4:]))
