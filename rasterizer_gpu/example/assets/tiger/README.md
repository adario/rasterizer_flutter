# tiger.svg: separately licensed test data

`tiger.svg` is the Ghostscript tiger: an SVG conversion of Ghostscript's `examples/tiger.eps`. Its licence isn't this
package's. Wikimedia Commons lists the artwork as **AGPL-3.0-or-later**, as a Ghostscript example:
https://commons.wikimedia.org/wiki/File:Ghostscript_Tiger.svg. The AGPL's text is at
https://www.gnu.org/licenses/agpl-3.0.html.

This copy comes from Rasterizer's test files (https://github.com/mindbrix/Rasterizer, `TestFiles/tiger.svg`, commit
`2be4bc16`), unchanged.

It's only test data for this example app: its golden tests and its default page. The `goldens/*/*tiger*.png` images
are renders of it. Neither ships in the rasterizer_gpu package: the `.pubignore` files in `assets/` and `goldens/` keep
them out of what pub publishes, so a published copy's SVG page says it couldn't load the tiger. An app that bundles
them, as this example does, must comply with that licence.
