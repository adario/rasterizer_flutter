import 'dart:ui';

// Shared by the package's files, and not exported.

/// The canvas of a game whose renderer isn't ready yet, while the game draws
/// its tree.
///
/// Vector content drawn into this canvas draws nothing. Otherwise it would
/// draw its paths with dart:ui, and the game's first frames would parse each
/// SVG a second time.
Canvas? unreadyCanvas;
