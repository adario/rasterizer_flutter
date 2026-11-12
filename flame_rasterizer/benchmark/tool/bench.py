"""Runs the benchmark: the demo app in profile mode, once per engine, vector count, separator count and zoom, each until it
logs its `FLAME_RASTERIZER bench` line, which is printed and appended to the output file. rasterizer runs once per backend:
mesh (rasterizer_gpu's mesh renderer, flame_rasterizer's default), atlas (its GPU renderer, which rasterizes the SVGs into an
atlas each frame), canvas (its canvas renderer, forced, drawing each SVG as a picture), or canvas_paths (drawing its paths).
--paints 1 has each component fade at its own rate, so with its own opacity (folded into its paints, so runs don't split), and
--paints 2 tinted by a ColorEffect of its own (a color filter per component, new each frame). --svgs tiger draws the
tiger for every component, rather than 50 small generated SVGs: many entries of one 301 path scene.
A run fails after --timeout seconds, or as soon as the app, once started, logs nothing for --stall seconds: it logs its
progress every 60 frames. On macOS a stalled app is sampled first, into <output file>.stall<n>.txt, and the app is killed
after each run, so that none outlives it into the next. A failed run's line says why, and the tool's last 30 lines go
to <output file>.fail<n>.txt, so that the output file has a line a run.
usage: python3 -I tool/bench.py <device> <output file> [--counts 100,1000] [--separators 0,2,9] [--engines rasterizer,flame_svg]
       [--zooms 1,0] [--frames 600] [--backends mesh,atlas,canvas,canvas_paths] [--paints 0,1,2] [--svgs generated,tiger]
       [--timeout 900] [--stall 15]"""
import argparse
import os
import queue
import re
import subprocess
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument('device')
parser.add_argument('output')
parser.add_argument('--counts', default='100,1000')
parser.add_argument('--separators', default='0,2,9')
parser.add_argument('--engines', default='rasterizer,flame_svg')
parser.add_argument('--zooms', default='1,0')
parser.add_argument('--frames', default='600')
parser.add_argument('--backends', default='mesh')
parser.add_argument('--paints', default='0')
parser.add_argument('--svgs', default='generated')
parser.add_argument('--timeout', type=float, default=900)
parser.add_argument('--stall', type=float, default=15)
args = parser.parse_args()
app = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failure = re.compile(r'FAILED|Error:|Lost connection|BUILD FAILED')
# The macOS app's process name.
process = 'flame_rasterizer_benchmark'
stalls = 0
failures = 0


def run(defines):
    global stalls, failures
    command = ['flutter', 'run', '--profile', '-d', args.device, *[f'--dart-define={k}={v}' for k, v in defines.items()]]
    p = subprocess.Popen(command, cwd=app, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         bufsize=1)
    # A reader thread, so silence is noticed while no line comes.
    lines = queue.Queue()
    threading.Thread(target=lambda: [*map(lines.put, p.stdout), lines.put(None)], daemon=True).start()
    start = last = time.time()
    started, result, problem, tail = False, None, None, []
    while True:
        try:
            line = lines.get(timeout=min(1, args.stall / 4))
        except queue.Empty:
            line = ''
        now = time.time()
        if line is None:
            problem = 'flutter run ended'
            break
        if line:
            last = now
            tail = (tail + [line.rstrip()])[-30:]
            started = started or 'Dart VM Service' in line
            if 'FLAME_RASTERIZER bench' in line:
                result = line[line.index('FLAME_RASTERIZER'):].rstrip()
                break
            if failure.search(line):
                problem = 'failed: ' + line.strip()[:200]
                break
        if now - start > args.timeout:
            problem = f'timed out after {args.timeout:g} s'
            break
        if started and now - last > args.stall:
            problem = f'STALLED: no output for {args.stall:g} s'
            if args.device == 'macos':
                stalls += 1
                sample = f'{args.output}.stall{stalls}.txt'
                subprocess.run(['sample', process, '3', '-file', sample], stdout=subprocess.DEVNULL,
                               stderr=subprocess.STDOUT)
                problem += f', sampled into {sample}'
            break
    try:
        p.stdin.write('q\n')
        p.stdin.flush()
        p.wait(20 if problem else 60)
    except Exception:
        p.kill()
    if args.device == 'macos':
        subprocess.run(['pkill', '-x', process])
    if result:
        return result
    failures += 1
    log = f'{args.output}.fail{failures}.txt'
    with open(log, 'w', encoding='utf-8') as f:
        f.write('\n'.join(tail) + '\n')
    return (f'FLAME_RASTERIZER bench FAILED ({problem or "the tool exited"}) '
            + ' '.join(f'{k}={v}' for k, v in defines.items()) + f', its output in {log}')


for svg in args.svgs.split(','):
    for zoom in args.zooms.split(','):
        for count in args.counts.split(','):
            for separators in args.separators.split(','):
                for paints in args.paints.split(','):
                    for engine in args.engines.split(','):
                        for backend in args.backends.split(',') if engine == 'rasterizer' else ['']:
                            defines = {'MODE': 'bench', 'ENGINE': engine, 'COUNT': count, 'SEPARATORS': separators,
                                       'ZOOM': zoom, 'FRAMES': args.frames, 'PAINTS': paints, 'SVG': svg}
                            if backend == 'atlas':
                                defines['BACKEND'] = 'atlas'
                            if backend.startswith('canvas'):
                                defines['BACKEND'] = 'canvas'
                            if backend == 'canvas_paths':
                                defines['CANVAS_PICTURES'] = 'false'
                            line = run(defines)
                            print(line, flush=True)
                            with open(args.output, 'a', encoding='utf-8') as f:
                                f.write(line + '\n')
