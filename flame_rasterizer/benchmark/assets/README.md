# The benchmark's asset

## tiger.svg: separately licensed

`tiger.svg` is the Ghostscript tiger, which `--dart-define=SVG=tiger` draws. It's an SVG conversion of Ghostscript's
`examples/tiger.eps`. It's the same file as `flame_rasterizer/example/assets/svgs/tiger.svg` and
`rasterizer_gpu/example/assets/tiger/tiger.svg`, copied here because a Flutter package's assets must be its own files.

Its licence isn't this repository's. Wikimedia Commons lists the artwork as **AGPL-3.0-or-later**, as a Ghostscript
example: https://commons.wikimedia.org/wiki/File:Ghostscript_Tiger.svg. The AGPL's text is at
https://www.gnu.org/licenses/agpl-3.0.html. An app that bundles the file, as this benchmark does, must comply with that
licence. See also the repository's `THIRD_PARTY_NOTICES.md`.
