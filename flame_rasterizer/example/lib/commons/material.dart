// The example uses Flutter's own Material library, because Widgetbook builds
// its panels with it. package:material_ui is a separate copy of the library:
// its widgets fail inside Widgetbook's panels, such as the knobs' fields, and
// the web build would include both copies. Export
// package:material_ui/material_ui.dart instead when Widgetbook switches to it.
// ignore: deprecated_member_use
export 'package:flutter/material.dart';
