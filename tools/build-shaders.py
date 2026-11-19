#!/usr/bin/env python3
"""Generates Slang and GLSL shaders for xBRZ Crisp from the single-source templates in tools/src/.

Usage:
    python3 tools/build-shaders.py [outdir]   (default: shaders)
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
PASSES = ("point", "pass0", "resolve", "match", "pass1")

PRAGMAS_5 = """#pragma parameter XBRZ_TOL "xBRZ: equal color tolerance (x/255)" 15 1 80 1
#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.8 1 8 0.05
#pragma parameter XBRZ_STEEP "xBRZ: steep/shallow line threshold" 3.2 1 6 0.1
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
//#plain-default XBRZ_MINC 0
#pragma parameter XBRZ_DIAG "xBRZ: max color distance on the diagonal (0 = off)" 100 0 160 4"""

PRAGMAS_POINT = """#pragma parameter XBRZ_DOM "xBRZ: dominant direction threshold" 3.8 1 8 0.05
//#crisp{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
#pragma parameter XBRZ_DIAG "xBRZ: max color distance on the diagonal (0 = off)" 100 0 160 4
//#crisp}"""


def glsl_vertex(uv_expr: str) -> str:
    return f"""#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
precision highp float;
#define COMPAT_PRECISION highp
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;

uniform mat4 MVPMatrix;

void main()
{{
    gl_Position = MVPMatrix * VertexCoord;
    TEX0.xy = {uv_expr};
}}

#elif defined(FRAGMENT)

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#define COMPAT_PRECISION highp
#else
precision mediump float;
#define COMPAT_PRECISION mediump
#endif
#else
#define COMPAT_PRECISION
#endif

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out COMPAT_PRECISION vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor"""


def slang_vertex(uv_expr: str) -> str:
    return f"""#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{{
   gl_Position = global.MVP * Position;
   vTexCoord = {uv_expr};
}}"""


def glsl_pass1_vertex() -> str:
    return """#if defined(VERTEX)

#if __VERSION__ >= 130
#define COMPAT_VARYING out
#define COMPAT_ATTRIBUTE in
#define COMPAT_TEXTURE texture
#else
#define COMPAT_VARYING varying
#define COMPAT_ATTRIBUTE attribute
#define COMPAT_TEXTURE texture2D
#endif

#ifdef GL_ES
precision highp float;
#define COMPAT_PRECISION highp
#else
#define COMPAT_PRECISION
#endif

COMPAT_ATTRIBUTE vec4 VertexCoord;
COMPAT_ATTRIBUTE vec4 TexCoord;
COMPAT_VARYING vec4 TEX0;

uniform mat4 MVPMatrix;
uniform COMPAT_PRECISION vec2 OutputSize;
//#crisp{
uniform COMPAT_PRECISION vec2 PassPrev4InputSize;
//#crisp}
//#plain uniform COMPAT_PRECISION vec2 PassPrev3InputSize;

void main()
{
    gl_Position = MVPMatrix * VertexCoord;
    TEX0.xy = TexCoord.xy;
//#crisp{
    TEX0.zw = OutputSize / PassPrev4InputSize;
//#crisp}
//#plain     TEX0.zw = OutputSize / PassPrev3InputSize;
}

#elif defined(FRAGMENT)

#ifdef GL_ES
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#define COMPAT_PRECISION highp
#else
precision mediump float;
#define COMPAT_PRECISION mediump
#endif
#else
#define COMPAT_PRECISION
#endif

#if __VERSION__ >= 130
#define COMPAT_VARYING in
#define COMPAT_TEXTURE texture
out COMPAT_PRECISION vec4 FragColor;
#else
#define COMPAT_VARYING varying
#define FragColor gl_FragColor
#define COMPAT_TEXTURE texture2D
#endif

uniform COMPAT_PRECISION vec2 OutputSize;
uniform COMPAT_PRECISION vec2 TextureSize;
uniform COMPAT_PRECISION vec2 InputSize;
uniform sampler2D Texture;
COMPAT_VARYING vec4 TEX0;
#define vTexCoord TEX0.xy
#define FRAG_OUT FragColor"""


def slang_pass1_vertex() -> str:
    return """#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out vec2 vScale;

void main()
{
   gl_Position = global.MVP * Position;
   vTexCoord = TexCoord;
//#crisp{
   vScale = params.OutputSize.xy / params.xbrz_crisp_refpassSize.xy;
//#crisp}
//#plain    vScale = params.OutputSize.xy / params.xbrz_fs_refpassSize.xy;
}"""


def stage_blocks(backend: str) -> dict[str, str]:
    if backend == "slang":
        vtx = slang_vertex("TexCoord")
        # Pass 1 uses exact TexCoord (no * 1.0001 spatial drift) and computes scale once per vertex
        vtx_out = slang_pass1_vertex()
        return {
            "@BACKEND_LABEL@": "Vulkan / slang",
            "@STAGE_POINT@": f"""layout(push_constant) uniform Push
{{
\tvec4 SourceSize;
\tvec4 OutputSize;
}} params;

layout(std140, set = 0, binding = 0) uniform UBO
{{
\tmat4 MVP;
\tfloat XBRZ_DOM;
//#crisp{{
\tfloat XBRZ_MINC;
\tfloat XBRZ_DIAG;
//#crisp}}
}} global;

{PRAGMAS_POINT}
#define XBRZ_DOM global.XBRZ_DOM
//#crisp{{
#define XBRZ_MINC global.XBRZ_MINC
#define XBRZ_DIAG global.XBRZ_DIAG
//#crisp}}

{vtx}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
#define SRC_SIZE params.SourceSize
#define P(x,y) texture(Source, coord + SRC_SIZE.zw * vec2(x, y)).rgb""",
            "@POINT_COORDS@": """  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;""",
            "@STAGE_PASS0@": f"""
layout(push_constant) uniform Push
{{
\tvec4 SourceSize;
\tvec4 OutputSize;
}} params;

layout(std140, set = 0, binding = 0) uniform UBO
{{
\tmat4 MVP;
\tfloat XBRZ_TOL;
\tfloat XBRZ_DOM;
\tfloat XBRZ_STEEP;
\tfloat XBRZ_MINC;
\tfloat XBRZ_DIAG;
}} global;

{PRAGMAS_5}
#define XBRZ_TOL global.XBRZ_TOL
#define XBRZ_DOM global.XBRZ_DOM
#define XBRZ_STEEP global.XBRZ_STEEP
#define XBRZ_MINC global.XBRZ_MINC
#define XBRZ_DIAG global.XBRZ_DIAG

{vtx}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
#define SRC_SIZE params.SourceSize
#define P4(x,y) texture(Source, coord + SRC_SIZE.zw * vec2(x, y))
#define P(x,y) P4(x, y).rgb""",
            "@PASS0_COORDS@": """  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;""",
            "@STAGE_RESOLVE@": f"""
layout(push_constant) uniform Push
{{
\tvec4 SourceSize;
//#crisp{{
\tvec4 xbrz_crisp_refpassSize;
//#crisp}}
//#plain\tvec4 xbrz_fs_refpassSize;
\tvec4 OutputSize;
}} params;

layout(std140, set = 0, binding = 0) uniform UBO
{{
\tmat4 MVP;
//#crisp{{
\tfloat XBRZ_MINC;
//#crisp}}
}} global;
//#crisp{{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
#define XBRZ_MINC global.XBRZ_MINC
//#crisp}}

{vtx}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
// the input of the first pass (the preset's reference pass), which is the original image unless
// other shaders run before xBRZ
//#crisp{{
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P(x,y) texture(xbrz_crisp_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
//#crisp}}
//#plain layout(set = 0, binding = 3) uniform sampler2D xbrz_fs_refpass;
//#plain #define ORIG_SIZE params.xbrz_fs_refpassSize
//#plain #define P(x,y) texture(xbrz_fs_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define OUT_SIZE params.OutputSize
#define ORIG_INPUT_SIZE ORIG_SIZE
#define INFO(uv) texture(Source, uv)
#define INFO_STEP ORIG_SIZE.zw""",
            "@RESOLVE_GLOBALS@": "vec2 coord = vec2(0.0);",
            "@RESOLVE_COORDS@": """  vec2 pos = fract(vTexCoord * ORIG_SIZE.xy) - vec2(0.5, 0.5);
//#crisp{
  coord = vTexCoord - pos * ORIG_SIZE.zw;
//#crisp}
//#plain   vec2 coord = vTexCoord - pos * ORIG_SIZE.zw;""",
            "@STAGE_MATCH@": f"""
layout(push_constant) uniform Push
{{
\tvec4 SourceSize;
\tvec4 xbrz_crisp_refpassSize;
\tvec4 OutputSize;
}} params;

layout(std140, set = 0, binding = 0) uniform UBO
{{
\tmat4 MVP;
\tfloat XBRZ_MINC;
}} global;
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
#define XBRZ_MINC global.XBRZ_MINC

{vtx}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
// the resolve pass's decisions
layout(set = 0, binding = 2) uniform sampler2D Source;
// the input of the first pass (the preset's reference pass), which is the original image unless
// other shaders run before xBRZ
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P(x,y) texture(xbrz_crisp_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define OUT_SIZE params.OutputSize
#define INFO(uv) texture(Source, uv)
#define INFO_STEP ORIG_SIZE.zw
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)

// pass 0's decisions, before the resolve pass changed them
layout(set = 0, binding = 4) uniform sampler2D xbrz_crisp_pass0;
#define W0_AT(x, y) floor(texture(xbrz_crisp_pass0, coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)

// the center of the pixel in the original, set in main (the functions read P)
vec2 coord = vec2(0.0);""",
            "@MATCH_COORDS@": """  vec2 pos = fract(vTexCoord * ORIG_SIZE.xy) - vec2(0.5, 0.5);
  coord = vTexCoord - pos * ORIG_SIZE.zw;""",
            "@STAGE_PASS1@": f"""
layout(push_constant) uniform Push
{{
\tvec4 SourceSize;
//#crisp{{
\tvec4 xbrz_crisp_refpassSize;
//#crisp}}
//#plain\tvec4 xbrz_fs_refpassSize;
\tvec4 OutputSize;
}} params;

layout(std140, set = 0, binding = 0) uniform UBO
{{
\tmat4 MVP;
}} global;

{vtx_out}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec2 vScale;
layout(location = 0) out vec4 FragColor;
#define FRAG_OUT FragColor
layout(set = 0, binding = 2) uniform sampler2D Source;
// the input of the first pass (the preset's reference pass), which is the original image unless
// other shaders run before xBRZ
//#crisp{{
layout(set = 0, binding = 3) uniform sampler2D xbrz_crisp_refpass;
#define ORIG_SIZE params.xbrz_crisp_refpassSize
#define P(x,y) texture(xbrz_crisp_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
//#crisp}}
//#plain layout(set = 0, binding = 3) uniform sampler2D xbrz_fs_refpass;
//#plain #define ORIG_SIZE params.xbrz_fs_refpassSize
//#plain #define P(x,y) texture(xbrz_fs_refpass, coord + ORIG_SIZE.zw * vec2(x, y)).rgb
#define OUT_SIZE params.OutputSize
#define INFO(uv) texture(Source, uv)
#define INFO_STEP ORIG_SIZE.zw""",
            "@PASS1_COORDS@": """  vec2 scale = vScale;
  vec2 pos = fract(vTexCoord * ORIG_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * ORIG_SIZE.zw;""",
        }

    vtx = glsl_vertex("TexCoord.xy")
    vtx_out = glsl_pass1_vertex()
    return {
        "@BACKEND_LABEL@": "OpenGL / GLES",
        "@POINT_COORDS@": """  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;""",
        "@PASS0_COORDS@": """  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;""",
        "@STAGE_POINT@": f"""{PRAGMAS_POINT}

{vtx}
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_DOM;
//#crisp{{
uniform COMPAT_PRECISION float XBRZ_MINC;
uniform COMPAT_PRECISION float XBRZ_DIAG;
//#crisp}}
#else
#define XBRZ_DOM 3.8
//#crisp{{
#define XBRZ_MINC 20.0
#define XBRZ_DIAG 100.0
//#crisp}}
#endif

#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
// Clamp to valid InputSize texels so POT-padded GL/GLES FBOs never sample black/stale padding
#define CLAMP_SRC(uv) clamp((uv), 0.5 * SRC_SIZE.zw, (InputSize - 0.5) * SRC_SIZE.zw)
#define P(x,y) COMPAT_TEXTURE(Texture, CLAMP_SRC(coord + SRC_SIZE.zw * vec2(x, y))).rgb""",
        "@STAGE_PASS0@": f"""
{PRAGMAS_5}

{vtx}
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_TOL;
uniform COMPAT_PRECISION float XBRZ_DOM;
uniform COMPAT_PRECISION float XBRZ_STEEP;
uniform COMPAT_PRECISION float XBRZ_MINC;
uniform COMPAT_PRECISION float XBRZ_DIAG;
#else
#define XBRZ_TOL 15.0
#define XBRZ_DOM 3.8
#define XBRZ_STEEP 3.2
#define XBRZ_MINC 20.0
#define XBRZ_DIAG 100.0
#endif

#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define CLAMP_SRC(uv) clamp((uv), 0.5 * SRC_SIZE.zw, (InputSize - 0.5) * SRC_SIZE.zw)
#define P4(x,y) COMPAT_TEXTURE(Texture, CLAMP_SRC(coord + SRC_SIZE.zw * vec2(x, y)))
#define P(x,y) P4(x, y).rgb""",
        "@STAGE_RESOLVE@": f"""
//#crisp{{
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
//#crisp}}
{vtx}
//#crisp{{
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_MINC;
#else
#define XBRZ_MINC 20.0
#endif
//#crisp}}

// the point pass (two passes back), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev2Texture;
uniform COMPAT_PRECISION vec2 PassPrev2TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev2InputSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(PassPrev2TextureSize, 1.0 / PassPrev2TextureSize)
#define ORIG_INPUT_SIZE PassPrev2InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define CLAMP_ORIG(uv) clamp((uv), 0.5 * ORIG_SIZE.zw, (ORIG_INPUT_SIZE - 0.5) * ORIG_SIZE.zw)
#define CLAMP_SRC(uv) clamp((uv), 0.5 * SRC_SIZE.zw, (InputSize - 0.5) * SRC_SIZE.zw)
#define P(x,y) COMPAT_TEXTURE(PassPrev2Texture, CLAMP_ORIG(ocoord + ORIG_SIZE.zw * vec2(x, y))).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, CLAMP_SRC(uv))
#define INFO_STEP SRC_SIZE.zw""",
        "@RESOLVE_GLOBALS@": "vec2 ocoord = vec2(0.0);",
        "@RESOLVE_COORDS@": """  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;
//#crisp{
  ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;
//#crisp}
//#plain   vec2 ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;""",
        "@STAGE_MATCH@": f"""
#pragma parameter XBRZ_MINC "xBRZ: minimum contrast to round a corner (x/255, 0 = off)" 20 0 80 2
{vtx}
#ifdef PARAMETER_UNIFORM
uniform COMPAT_PRECISION float XBRZ_MINC;
#else
#define XBRZ_MINC 20.0
#endif

// the point pass (three passes back), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev3Texture;
uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev3InputSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(PassPrev3TextureSize, 1.0 / PassPrev3TextureSize)
#define ORIG_INPUT_SIZE PassPrev3InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define CLAMP_ORIG(uv) clamp((uv), 0.5 * ORIG_SIZE.zw, (ORIG_INPUT_SIZE - 0.5) * ORIG_SIZE.zw)
#define CLAMP_SRC(uv) clamp((uv), 0.5 * SRC_SIZE.zw, (InputSize - 0.5) * SRC_SIZE.zw)
#define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, CLAMP_ORIG(ocoord + ORIG_SIZE.zw * vec2(x, y))).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, CLAMP_SRC(uv))
#define INFO_STEP SRC_SIZE.zw
#define INFO_AT(x, y) floor(INFO(coord + vec2(x, y) * INFO_STEP) * 255.0 + 0.5)

// pass 0's decisions (two passes back), before the resolve pass changed them
uniform sampler2D PassPrev2Texture;
uniform COMPAT_PRECISION vec2 PassPrev2TextureSize;
#define P0_SIZE vec4(PassPrev2TextureSize, 1.0 / PassPrev2TextureSize)
#define CLAMP_P0(uv) clamp((uv), 0.5 * P0_SIZE.zw, (InputSize - 0.5) * P0_SIZE.zw)
#define W0_AT(x, y) floor(COMPAT_TEXTURE(PassPrev2Texture, CLAMP_P0(c0 + vec2(x, y) * P0_SIZE.zw)) * 255.0 + 0.5)
vec2 coord = vec2(0.0), ocoord = vec2(0.0), c0 = vec2(0.0);""",
        "@MATCH_COORDS@": """  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  coord = vTexCoord - pos * SRC_SIZE.zw;
  ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;
  c0 = coord * SRC_SIZE.xy * P0_SIZE.zw;""",
        "@STAGE_PASS1@": f"""
{vtx_out}

//#crisp{{
// the point pass (four passes back: pass 0, the resolve pass and the match pass come between), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
uniform sampler2D PassPrev4Texture;
uniform COMPAT_PRECISION vec2 PassPrev4TextureSize;
uniform COMPAT_PRECISION vec2 PassPrev4InputSize;
#define OUT_SIZE OutputSize
#define ORIG_SIZE vec4(PassPrev4TextureSize, 1.0 / PassPrev4TextureSize)
#define ORIG_INPUT_SIZE PassPrev4InputSize
//#crisp}}
//#plain // the point pass (three passes back: pass 0 and the resolve pass come between), whose color is xBRZ's input: the original image unless other shaders run before xBRZ
//#plain uniform sampler2D PassPrev3Texture;
//#plain uniform COMPAT_PRECISION vec2 PassPrev3TextureSize;
//#plain uniform COMPAT_PRECISION vec2 PassPrev3InputSize;
//#plain #define OUT_SIZE OutputSize
//#plain #define ORIG_SIZE vec4(PassPrev3TextureSize, 1.0 / PassPrev3TextureSize)
//#plain #define ORIG_INPUT_SIZE PassPrev3InputSize
// the first pass's texture and the original's can have different sizes (RetroArch rounds each one
// up to a power of two on its own, e.g. 256 and 512 with snes9x), so each one is read with its own
#define SRC_SIZE vec4(TextureSize, 1.0 / TextureSize)
#define CLAMP_ORIG(uv) clamp((uv), 0.5 * ORIG_SIZE.zw, (ORIG_INPUT_SIZE - 0.5) * ORIG_SIZE.zw)
//#crisp{{
#define P(x,y) COMPAT_TEXTURE(PassPrev4Texture, CLAMP_ORIG(ocoord + ORIG_SIZE.zw * vec2(x, y))).rgb
//#crisp}}
//#plain #define P(x,y) COMPAT_TEXTURE(PassPrev3Texture, CLAMP_ORIG(ocoord + ORIG_SIZE.zw * vec2(x, y))).rgb
#define INFO(uv) COMPAT_TEXTURE(Texture, uv)
#define INFO_STEP SRC_SIZE.zw""",
        "@PASS1_COORDS@": """  vec2 scale = TEX0.zw;
  vec2 pos = fract(vTexCoord * SRC_SIZE.xy) - vec2(0.5, 0.5);
  vec2 coord = vTexCoord - pos * SRC_SIZE.zw;
  vec2 ocoord = coord * SRC_SIZE.xy * ORIG_SIZE.zw;""",
    }


def expand_includes(text: str) -> str:
    pattern = re.compile(r'^@include\s+"([^"]+)"\s*$', flags=re.M)

    def repl(m: re.Match) -> str:
        inc_path = os.path.join(SRC_DIR, m.group(1))
        with open(inc_path, "r", encoding="utf-8") as f:
            return f.read().rstrip("\n")

    for _ in range(16):
        if not pattern.search(text):
            break
        text = pattern.sub(repl, text)
    return text


def render_pass(pass_name: str, backend: str) -> str:
    src_path = os.path.join(SRC_DIR, f"{pass_name}.inc")
    with open(src_path, "r", encoding="utf-8") as f:
        text = f.read()
    text = expand_includes(text)

    subs = stage_blocks(backend)
    for k, v in subs.items():
        text = text.replace(k, v)

    leftover = re.findall(r"@[A-Z0-9_]+@|^@include\b", text, flags=re.M)
    if leftover:
        sys.exit(f"{pass_name} ({backend}): unresolved placeholders {leftover}")

    if backend == "slang":
        return "#version 450\n" + text
    else:
        return text.rstrip("\n") + "\n\n#endif\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("outdir", nargs="?", default=os.path.join(ROOT, "shaders"), help="Output shaders directory")
    args = ap.parse_args()

    slang_dir = os.path.join(args.outdir, "shaders_slang", "edge-smoothing", "xbrz", "shaders", "xbrz-crisp")
    glsl_dir = os.path.join(args.outdir, "shaders_glsl", "xbrz", "shaders", "xbrz-crisp")
    os.makedirs(slang_dir, exist_ok=True)
    os.makedirs(glsl_dir, exist_ok=True)

    for p in PASSES:
        sp = os.path.join(slang_dir, f"xbrz-crisp-{p}.slang")
        gp = os.path.join(glsl_dir, f"xbrz-crisp-{p}.glsl")
        with open(sp, "w", encoding="utf-8") as f:
            f.write(render_pass(p, "slang"))
        with open(gp, "w", encoding="utf-8") as f:
            f.write(render_pass(p, "glsl"))
        print(sp)
        print(gp)


if __name__ == "__main__":
    main()
