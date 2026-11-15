import 'package:material_ui/material_ui.dart';
import 'package:rasterizer_gpu/rasterizer_gpu.dart';

import 'pages/atlas_page.dart';
import 'pages/svg_page.dart';
import 'startup_log.dart';

// The page that --dart-define=PAGE picks: svg, the default, shows an SVG asset
// to pan and zoom, and atlas runs the atlas benchmark.
const String kPage = String.fromEnvironment('PAGE', defaultValue: 'svg');

// Settings for the svg page. SVG names the asset, and CURVES=false draws
// curves as line segments. SWEEP=true runs the sweep and logs its timings.
// GRID=n draws the SVG n x n times, and SLOTS sets the renderer's frames in
// flight.
const String kSvg = String.fromEnvironment(
  'SVG',
  defaultValue: 'assets/tiger/tiger.svg',
);
const bool kCurves = bool.fromEnvironment('CURVES', defaultValue: true);
const bool kSweep = bool.fromEnvironment('SWEEP');
const int kGrid = int.fromEnvironment('GRID', defaultValue: 1);
const int kSlots = int.fromEnvironment('SLOTS', defaultValue: 3);

// Settings for the atlas page: it draws ENTRIES entries in RUNS runs, and logs
// timings after FRAMES frames.
const int kEntries = int.fromEnvironment('ENTRIES', defaultValue: 1000);
const int kRuns = int.fromEnvironment('RUNS', defaultValue: 4);
const int kFrames = int.fromEnvironment('FRAMES', defaultValue: 300);

// BACKEND=canvas uses the canvas renderer even where a GPU renderer is
// supported. BACKEND=mesh uses the mesh renderer where it's supported, instead
// of the GPU renderer, also called the atlas renderer.
const String kBackend = String.fromEnvironment('BACKEND');
const RasterizerBackend kGpu = kBackend == 'mesh'
    ? RasterizerBackend.mesh
    : RasterizerBackend.gpu;

// DEFER_FIRST_FRAME=n holds back the first frame for n seconds, as a splash
// screen would.
const int kDeferFirstFrame = int.fromEnvironment('DEFER_FIRST_FRAME');

void main() {
  RasterizerGpu.forceCanvas = kBackend == 'canvas';
  StartupLog.begin();
  if (kDeferFirstFrame > 0) {
    WidgetsBinding.instance.deferFirstFrame();
    Future.delayed(const Duration(seconds: kDeferFirstFrame), () {
      StartupLog.mark('first frame allowed');
      WidgetsBinding.instance.allowFirstFrame();
    });
  }
  final gpu = RasterizerGpu.of(kGpu), detail = gpu.supportDetail;
  debugPrint(
    'RASTERIZER_EXAMPLE support '
    '${gpu.support.name}${detail == null ? '' : ': $detail'}, '
    'backend ${gpu.backend.name}',
  );
  runApp(const ExampleApp());
}

/// The example app, which shows the page that [kPage] picks.
class const ExampleApp({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: kPage == 'atlas'
          ? const AtlasPage(
              entries: kEntries,
              runs: kRuns,
              frames: kFrames,
              gpu: kGpu,
            )
          : const SvgPage(
              asset: kSvg,
              gpu: kGpu,
              useCurves: kCurves,
              sweep: kSweep,
              slots: kSlots,
              grid: kGrid,
            ),
    );
  }
}
