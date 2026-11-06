#!/usr/bin/env python3
"""Writes plain xbrz-freescale-multipass from the xBRZ crisp shaders.

The crisp passes are xbrz-freescale-multipass with a minimum contrast (XBRZ_MINC 20 instead of 0).
Everything between a "//#crisp{" line and a "//#crisp}" line is crisp only and is dropped; a line
starting with "//#plain" is only in the plain shader and is turned on. The output uses the libretro layout,
with the resolve pass between pass 0 and pass 1, and the two xbrz-freescale-multipass presets
(the libretro ones have no resolve pass yet).

Pass 0 is written twice: xbrz-freescale-pass0 for plain xBRZ, with XBRZ_MINC fixed at 0 so the
compiler leaves the crisp rules out (RetroArch passes the parameters as uniforms, so a menu value of 0
would still compile them in), and xbrz-crisp-pass0 with every rule, used by the xbrz-crisp presets.

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
STOCK = 'shader0 = ../../stock.slang\nalias0 = xbrz_fs_refpass\n\n'
PRESETS = {
    'glsl-shaders/xbrz/xbrz-freescale-multipass.glslp': ('', 'xbrz-freescale-pass0', ''),
    'slang-shaders/edge-smoothing/xbrz/xbrz-freescale-multipass.slangp': (STOCK, 'xbrz-freescale-pass0', ''),
    'glsl-shaders/xbrz/xbrz-crisp.glslp': ('', 'xbrz-crisp-pass0', 'xbrz-crisp'),
    'slang-shaders/edge-smoothing/xbrz/xbrz-crisp.slangp': (STOCK, 'xbrz-crisp-pass0', 'xbrz-crisp'),
}
CRISP_PARAMS = '\nparameters = "XBRZ_MINC;XBRZ_DIAG"\nXBRZ_MINC = "20.000000"\nXBRZ_DIAG = "100.000000"\n'


def sub1(text, old, new, name):
    if text.count(old) != 1: sys.exit('%s: %r found %d times' % (name, old, text.count(old)))
    return text.replace(old, new)


HEAD = '// above 0; the xbrz-crisp preset sets it to 20, so low-contrast shading and textures keep their pixels.\n'


def pure_pass0(text, name):
    """plain xBRZ pass 0: XBRZ_MINC is the constant 0, so the crisp rules compile away"""
    text = sub1(text, HEAD,
                '// above 0; here XBRZ_MINC is fixed at 0, so they compile away. The xbrz-crisp preset uses\n'
                '// xbrz-crisp-pass0, which has them, with XBRZ_MINC 20, so low-contrast shading and textures\n'
                '// keep their pixels.\n', name)
    text = sub1(text, '(XBRZ_MINC and XBRZ_DIAG are in the menu)', '(XBRZ_DIAG is in the menu, XBRZ_MINC is 0)', name)
    text = re.sub(r'^#pragma parameter XBRZ_MINC .*\n', '', text, flags=re.M)
    if name.endswith('.glsl'):
        text = sub1(text, 'uniform COMPAT_PRECISION float XBRZ_MINC;\n', '#define XBRZ_MINC 0.0\n', name)
    else:
        text = sub1(text, '\tfloat XBRZ_MINC;\n', '', name)
        text = sub1(text, '#define XBRZ_MINC global.XBRZ_MINC', '#define XBRZ_MINC 0.0', name)
    return text


def crisp_pass0(text, name):
    """xbrz-crisp pass 0: every rule, XBRZ_MINC in the menu (20 by default)"""
    text = sub1(text, HEAD, HEAD + '// Plain xBRZ uses xbrz-freescale-pass0, the same pass with XBRZ_MINC fixed at 0, which is lighter.\n', name)
    text = sub1(text, '// Pass 0 of xbrz-freescale-multipass (', '// Pass 0 of xbrz-freescale-multipass with the crisp rules, for xbrz-crisp (', name)
    text, n = re.subn(r'(#pragma parameter XBRZ_MINC "[^"]*" )0 ', r'\g<1>20 ', text)
    if n != 1: sys.exit('%s: XBRZ_MINC pragma' % name)
    text, n = re.subn(r'^#define XBRZ_MINC 0\.0$', '#define XBRZ_MINC 20.0', text, flags=re.M)
    if n != (1 if name.endswith('.glsl') else 0): sys.exit('%s: XBRZ_MINC define' % name)
    return text


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
        outs = [(d, text)]
        if p == 'pass0':
            outs = [(d, pure_pass0(text, d)), (d.replace('xbrz-freescale-pass0', 'xbrz-crisp-pass0'), crisp_pass0(text, d))]
        for d_, t in outs:
            with open(d_, 'w') as f: f.write(t)
            print(d_)

for dst, (head, p0, crisp) in PRESETS.items():
    ext = dst.rsplit('.', 1)[1][:-1]
    first = 1 if head else 0
    text = 'shaders = %d\n\n' % (len(PASSES) + first) + head
    for i, p in enumerate(PASSES, first):
        f = p0 if p == 'pass0' else 'xbrz-freescale-' + p
        text += ('shader%d = shaders/xbrz-freescale-multipass/%s.%s\nfilter_linear%d = false\n'
                 'scale_type%d = %s\nscale%d = 1.0\n' % (i, f, ext, i, i, 'viewport' if p == 'pass1' else 'source', i))
        if p != PASSES[-1]: text += '\n'
    if crisp: text += CRISP_PARAMS
    d = os.path.join(OUT, dst)
    with open(d, 'w') as f: f.write(text)
    print(d)
