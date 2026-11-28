import 'dart:ui';

// Shared by the package's files, and not exported.

/// The canvas of a game that draws its tree before its renderer is ready.
///
/// Vector content drawn into this canvas draws nothing. Otherwise it would
/// draw its paths with dart:ui, and the game's first frames would parse each
/// SVG a second time.
Canvas? unreadyCanvas;
