"""Rewrites src/core/upstream.patch: the unified diff from the upstream files to the core's copy, apart from each copied
file's first comment lines (`// From Rasterizer ...`).

The upstream files are Package/Sources/RasterizerCpp in a checkout of https://github.com/mindbrix/Rasterizer at the commit
src/core/README.md names, so the patch shows every change made here since the copy.

usage: python3 -I make_patch.py RASTERIZER_CHECKOUT
"""
import difflib
import os
import sys

UPSTREAM = 'Package/Sources/RasterizerCpp'
FILES = [('include/Rasterizer.h', 'Rasterizer.h'), ('include/Rasterizer.hpp', 'Rasterizer.hpp'),
         ('include/RasterizerSVG.hpp', 'RasterizerSVG.hpp'), ('include/nanosvg.h', 'nanosvg.h'),
         ('include/xxhash.h', 'xxhash.h'), ('nanosvg.cc', 'nanosvg.cc'), ('xxhash.c', 'xxhash.c')]


def main(checkout):
    core = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'src', 'core')
    out = []
    for up, mine in FILES:
        a = open(os.path.join(checkout, UPSTREAM, up), encoding='utf-8').read().splitlines(keepends=True)
        b = open(os.path.join(core, mine), encoding='utf-8').read().splitlines(keepends=True)
        while b and b[0].startswith('// '):
            b.pop(0)
        out += difflib.unified_diff(a, b, f'a/{UPSTREAM}/{up}', f'b/src/core/{mine}', n=3)
    text = ''.join(out)
    open(os.path.join(core, 'upstream.patch'), 'w', encoding='utf-8').write(text)
    print(len(text.splitlines()), 'lines')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
