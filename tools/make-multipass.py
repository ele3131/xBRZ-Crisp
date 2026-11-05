#!/usr/bin/env python3
"""Writes plain xbrz-freescale-multipass from the xBRZ crisp shaders.

The crisp passes are xbrz-freescale-multipass with a minimum contrast (XBRZ_MINC 20 instead of 0).
Everything between a "//#crisp{" line and a "//#crisp}" line is crisp only and is dropped; a line
starting with "//#plain" is only in the plain shader and is turned on. The output uses the libretro layout,
with the resolve pass between pass 0 and pass 1, and the two xbrz-freescale-multipass presets
(the libretro ones have no resolve pass yet).

usage: tools/make-multipass.py [outdir]   (default: build/multipass)
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build', 'multipass')
JOBS = [
    ('shaders/shaders_glsl/xbrz/shaders/xbrz-crisp/xbrz-crisp-%s.glsl',
     'glsl-shaders/xbrz/shaders/xbrz-freescale-multipass/xbrz-freescale-%s.glsl'),
    ('shaders/shaders_slang/edge-smoothing/xbrz/shaders/xbrz-crisp/xbrz-crisp-%s.slang',
     'slang-shaders/edge-smoothing/xbrz/shaders/xbrz-freescale-multipass/xbrz-freescale-%s.slang'),
]
PASSES = ('pass0', 'resolve', 'pass1')
PRESETS = {
    'glsl-shaders/xbrz/xbrz-freescale-multipass.glslp': '',
    'slang-shaders/edge-smoothing/xbrz/xbrz-freescale-multipass.slangp':
        'shader0 = ../../stock.slang\nalias0 = xbrz_fs_refpass\n\n',
}


def plain(text, name):
    out, crisp, defaults = [], False, {}
    for n, line in enumerate(text.split('\n'), 1):
        mark = line.strip()
        if mark == '//#crisp{':
            if crisp: sys.exit('%s:%d: nested //#crisp{' % (name, n))
            crisp = True
        elif mark == '//#crisp}':
            if not crisp: sys.exit('%s:%d: //#crisp} without //#crisp{' % (name, n))
            crisp = False
        elif mark.startswith('//#plain-default '):
            if not crisp:
                k, v = mark.split()[1:]
                defaults[k] = v
        elif not crisp:
            out.append(re.sub(r'^//#plain ?', '', line))
    if crisp: sys.exit('%s: //#crisp{ is not closed' % name)
    text = '\n'.join(out)
    for k, v in defaults.items():
        text, n = re.subn(r'(#pragma parameter %s "[^"]*" )\S+' % k, r'\g<1>' + v, text)
        if n != 1: sys.exit('%s: no #pragma parameter %s' % (name, k))
        text = re.sub(r'(#define %s )[-\d.]+$' % k, r'\g<1>' + (v if '.' in v else v + '.0'), text, flags=re.M)
    if re.search(r'//#|xbrz_crisp|xBRZ crisp', text): sys.exit('%s: crisp text left in the plain shader' % name)
    return text


for src, dst in JOBS:
    for p in PASSES:
        s, d = os.path.join(ROOT, src % p), os.path.join(OUT, dst % p)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        with open(s) as f: text = plain(f.read(), src % p)
        with open(d, 'w') as f: f.write(text)
        print(d)

for dst, head in PRESETS.items():
    ext = dst.rsplit('.', 1)[1][:-1]
    first = 1 if head else 0
    text = 'shaders = %d\n\n' % (len(PASSES) + first) + head
    for i, p in enumerate(PASSES, first):
        text += ('shader%d = shaders/xbrz-freescale-multipass/xbrz-freescale-%s.%s\nfilter_linear%d = false\n'
                 'scale_type%d = %s\nscale%d = 1.0\n' % (i, p, ext, i, i, 'viewport' if p == 'pass1' else 'source', i))
        if p != PASSES[-1]: text += '\n'
    d = os.path.join(OUT, dst)
    with open(d, 'w') as f: f.write(text)
    print(d)
