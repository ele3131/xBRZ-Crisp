#!/usr/bin/env python3
"""Headless validator, multi-profile GLSL ES compiler, static linter, and pixel-diff runner.

Requires zero external packages beyond Python 3 + Pillow/NumPy + system libEGL/libGLESv2.

Usage:
    python3 tools/verify.py                        # Sync check + lint + ES 1.00 / ES 3.00 compile + multipass
    python3 tools/verify.py --diff                 # Pixel-diff 12 GBA scenes in docs/img/ vs docs/img/*-crisp20.png
    python3 tools/verify.py --save-baseline DIR    # Save 6x reference renders into DIR before refactoring
    python3 tools/verify.py --diff-baseline DIR    # Assert 0 pixel changes (or inspect deltas) vs DIR
"""
import argparse
import ctypes
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS_DIR = os.path.join(ROOT, "tools")
SRC_DIR = os.path.join(TOOLS_DIR, "src")
SHADERS_DIR = os.path.join(ROOT, "shaders")
DOCS_IMG_DIR = os.path.join(ROOT, "docs", "img")

os.environ.setdefault("LP_NATIVE_VECTOR_WIDTH", "128")


class HeadlessGLES:
    """Zero-dependency ctypes wrapper over surfaceless EGL + OpenGL ES 2/3."""

    EGL_DEFAULT_DISPLAY = None
    EGL_NO_CONTEXT = None
    EGL_NO_SURFACE = None
    EGL_NO_DISPLAY = None
    EGL_PLATFORM_SURFACELESS_MESA = 0x31DD
    EGL_SURFACE_TYPE = 0x3033
    EGL_RENDERABLE_TYPE = 0x3040
    EGL_OPENGL_ES2_BIT = 0x0004
    EGL_RED_SIZE = 0x3024
    EGL_GREEN_SIZE = 0x3023
    EGL_BLUE_SIZE = 0x3022
    EGL_ALPHA_SIZE = 0x3021
    EGL_NONE = 0x3038
    EGL_OPENGL_ES_API = 0x30A0
    EGL_CONTEXT_CLIENT_VERSION = 0x3098

    GL_VERTEX_SHADER = 0x8B31
    GL_FRAGMENT_SHADER = 0x8B30
    GL_COMPILE_STATUS = 0x8B81
    GL_LINK_STATUS = 0x8B82
    GL_ARRAY_BUFFER = 0x8892
    GL_STATIC_DRAW = 0x88E4
    GL_FLOAT = 0x1406
    GL_FALSE = 0
    GL_TEXTURE_2D = 0x0DE1
    GL_TEXTURE_MIN_FILTER = 0x2801
    GL_TEXTURE_MAG_FILTER = 0x2800
    GL_TEXTURE_WRAP_S = 0x2802
    GL_TEXTURE_WRAP_T = 0x2803
    GL_NEAREST = 0x2600
    GL_CLAMP_TO_EDGE = 0x812F
    GL_RGBA = 0x1908
    GL_UNSIGNED_BYTE = 0x1401
    GL_UNPACK_ALIGNMENT = 0x0CF5
    GL_PACK_ALIGNMENT = 0x0D05
    GL_FRAMEBUFFER = 0x8D40
    GL_COLOR_ATTACHMENT0 = 0x8CE0
    GL_TEXTURE0 = 0x84C0
    GL_TRIANGLE_STRIP = 0x0005

    def __init__(self) -> None:
        self.egl = ctypes.CDLL("libEGL.so.1")
        self.gl = ctypes.CDLL("libGLESv2.so.2")
        self._bind_prototypes()
        self.dpy = self._init_display()
        self.ctx = self._init_context()
        self.vbo = self._init_quad()

    def _bind_prototypes(self) -> None:
        self.egl.eglGetProcAddress.argtypes = [ctypes.c_char_p]
        self.egl.eglGetProcAddress.restype = ctypes.c_void_p
        self.egl.eglInitialize.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
        self.egl.eglInitialize.restype = ctypes.c_uint
        self.egl.eglChooseConfig.argtypes = [
            ctypes.c_void_p, ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_int, ctypes.POINTER(ctypes.c_int),
        ]
        self.egl.eglChooseConfig.restype = ctypes.c_uint
        self.egl.eglBindAPI.argtypes = [ctypes.c_uint]
        self.egl.eglBindAPI.restype = ctypes.c_uint
        self.egl.eglCreateContext.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_int)]
        self.egl.eglCreateContext.restype = ctypes.c_void_p
        self.egl.eglMakeCurrent.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
        self.egl.eglMakeCurrent.restype = ctypes.c_uint
        self.egl.eglDestroyContext.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        self.egl.eglTerminate.argtypes = [ctypes.c_void_p]

        self.gl.glCreateShader.argtypes = [ctypes.c_uint]
        self.gl.glCreateShader.restype = ctypes.c_uint
        self.gl.glShaderSource.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.POINTER(ctypes.c_char_p), ctypes.c_void_p]
        self.gl.glCompileShader.argtypes = [ctypes.c_uint]
        self.gl.glGetShaderiv.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(ctypes.c_int)]
        self.gl.glGetShaderInfoLog.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_char_p]
        self.gl.glDeleteShader.argtypes = [ctypes.c_uint]
        self.gl.glCreateProgram.restype = ctypes.c_uint
        self.gl.glBindAttribLocation.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_char_p]
        self.gl.glAttachShader.argtypes = [ctypes.c_uint, ctypes.c_uint]
        self.gl.glLinkProgram.argtypes = [ctypes.c_uint]
        self.gl.glGetProgramiv.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(ctypes.c_int)]
        self.gl.glGetProgramInfoLog.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_void_p, ctypes.c_char_p]
        self.gl.glDeleteProgram.argtypes = [ctypes.c_uint]
        self.gl.glUseProgram.argtypes = [ctypes.c_uint]
        self.gl.glGetUniformLocation.argtypes = [ctypes.c_uint, ctypes.c_char_p]
        self.gl.glGetUniformLocation.restype = ctypes.c_int
        self.gl.glUniform1f.argtypes = [ctypes.c_int, ctypes.c_float]
        self.gl.glUniform2f.argtypes = [ctypes.c_int, ctypes.c_float, ctypes.c_float]
        self.gl.glUniform1i.argtypes = [ctypes.c_int, ctypes.c_int]
        self.gl.glUniformMatrix4fv.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_ubyte, ctypes.POINTER(ctypes.c_float)]
        self.gl.glGenBuffers.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)]
        self.gl.glBindBuffer.argtypes = [ctypes.c_uint, ctypes.c_uint]
        self.gl.glBufferData.argtypes = [ctypes.c_uint, ctypes.c_ssize_t, ctypes.c_void_p, ctypes.c_uint]
        self.gl.glDeleteBuffers.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)]
        self.gl.glEnableVertexAttribArray.argtypes = [ctypes.c_uint]
        self.gl.glVertexAttribPointer.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_uint, ctypes.c_ubyte, ctypes.c_int, ctypes.c_void_p]
        self.gl.glGenTextures.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)]
        self.gl.glDeleteTextures.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)]
        self.gl.glBindTexture.argtypes = [ctypes.c_uint, ctypes.c_uint]
        self.gl.glActiveTexture.argtypes = [ctypes.c_uint]
        self.gl.glTexParameteri.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_int]
        self.gl.glPixelStorei.argtypes = [ctypes.c_uint, ctypes.c_int]
        self.gl.glTexImage2D.argtypes = [
            ctypes.c_uint, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            ctypes.c_int, ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p,
        ]
        self.gl.glGenFramebuffers.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)]
        self.gl.glDeleteFramebuffers.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint)]
        self.gl.glBindFramebuffer.argtypes = [ctypes.c_uint, ctypes.c_uint]
        self.gl.glFramebufferTexture2D.argtypes = [ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint, ctypes.c_int]
        self.gl.glViewport.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        self.gl.glDrawArrays.argtypes = [ctypes.c_uint, ctypes.c_int, ctypes.c_int]
        self.gl.glReadPixels.argtypes = [
            ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p
        ]

    def _init_display(self) -> int:
        gpd_addr = self.egl.eglGetProcAddress(b"eglGetPlatformDisplayEXT")
        if not gpd_addr:
            raise RuntimeError("eglGetPlatformDisplayEXT unavailable")
        gpd_fn = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p)(gpd_addr)
        dpy = gpd_fn(self.EGL_PLATFORM_SURFACELESS_MESA, None, None)
        maj, mn = ctypes.c_int(0), ctypes.c_int(0)
        if not dpy or not self.egl.eglInitialize(dpy, ctypes.byref(maj), ctypes.byref(mn)):
            raise RuntimeError("eglInitialize failed")
        return dpy

    def _init_context(self) -> int:
        att = (ctypes.c_int * 13)(
            self.EGL_SURFACE_TYPE, 0,
            self.EGL_RENDERABLE_TYPE, self.EGL_OPENGL_ES2_BIT,
            self.EGL_RED_SIZE, 8, self.EGL_GREEN_SIZE, 8, self.EGL_BLUE_SIZE, 8, self.EGL_ALPHA_SIZE, 8,
            self.EGL_NONE,
        )
        cfg = ctypes.c_void_p()
        ncfg = ctypes.c_int(0)
        if not self.egl.eglChooseConfig(self.dpy, att, ctypes.byref(cfg), 1, ctypes.byref(ncfg)) or ncfg.value < 1:
            raise RuntimeError("eglChooseConfig failed")
        self.egl.eglBindAPI(self.EGL_OPENGL_ES_API)
        ctx_att = (ctypes.c_int * 3)(self.EGL_CONTEXT_CLIENT_VERSION, 3, self.EGL_NONE)
        ctx = self.egl.eglCreateContext(self.dpy, cfg, None, ctx_att)
        if not ctx or not self.egl.eglMakeCurrent(self.dpy, None, None, ctx):
            raise RuntimeError("eglCreateContext / eglMakeCurrent failed")
        return ctx

    def _init_quad(self) -> ctypes.c_uint:
        quad = (ctypes.c_float * 32)(
            -1.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
             1.0, -1.0, 0.0, 1.0, 1.0, 0.0, 0.0, 0.0,
            -1.0,  1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0,
             1.0,  1.0, 0.0, 1.0, 1.0, 1.0, 0.0, 0.0,
        )
        vbo = ctypes.c_uint(0)
        self.gl.glGenBuffers(1, ctypes.byref(vbo))
        self.gl.glBindBuffer(self.GL_ARRAY_BUFFER, vbo)
        self.gl.glBufferData(self.GL_ARRAY_BUFFER, ctypes.sizeof(quad), quad, self.GL_STATIC_DRAW)
        return vbo

    @staticmethod
    def preprocess_retroarch_glsl(raw_src: str, is_vertex: bool, version_hdr: str, param_uniform: bool = True) -> bytes:
        stage_def = "#define VERTEX" if is_vertex else "#define FRAGMENT"
        param_def = "\n#define PARAMETER_UNIFORM" if param_uniform else ""
        lines = [
            "" if (ln.startswith("#pragma ") or ln.startswith("#version ")) else ln
            for ln in raw_src.splitlines()
        ]
        return f"{version_hdr}\n{stage_def}{param_def}\n" .encode("utf-8") + "\n".join(lines).encode("utf-8")

    def compile_program(self, glsl_path: str, version_hdr: str = "#version 300 es", param_uniform: bool = True) -> int:
        with open(glsl_path, "r", encoding="utf-8") as f:
            raw = f.read()

        def _comp(stype: int, src_bytes: bytes) -> int:
            sh = self.gl.glCreateShader(stype)
            ptr = ctypes.c_char_p(src_bytes)
            self.gl.glShaderSource(sh, 1, ctypes.byref(ptr), None)
            self.gl.glCompileShader(sh)
            ok = ctypes.c_int(0)
            self.gl.glGetShaderiv(sh, self.GL_COMPILE_STATUS, ctypes.byref(ok))
            if not ok.value:
                buf = ctypes.create_string_buffer(4096)
                self.gl.glGetShaderInfoLog(sh, 4096, None, buf)
                self.gl.glDeleteShader(sh)
                raise RuntimeError(f"Compile error in {glsl_path} ({version_hdr}):\n{buf.value.decode('utf-8', 'replace')}")
            return sh

        vs = _comp(self.GL_VERTEX_SHADER, self.preprocess_retroarch_glsl(raw, True, version_hdr, param_uniform))
        fs = _comp(self.GL_FRAGMENT_SHADER, self.preprocess_retroarch_glsl(raw, False, version_hdr, param_uniform))
        prog = self.gl.glCreateProgram()
        self.gl.glBindAttribLocation(prog, 0, b"VertexCoord")
        self.gl.glBindAttribLocation(prog, 1, b"TexCoord")
        self.gl.glAttachShader(prog, vs)
        self.gl.glAttachShader(prog, fs)
        self.gl.glLinkProgram(prog)
        self.gl.glDeleteShader(vs)
        self.gl.glDeleteShader(fs)
        ok = ctypes.c_int(0)
        self.gl.glGetProgramiv(prog, self.GL_LINK_STATUS, ctypes.byref(ok))
        if not ok.value:
            buf = ctypes.create_string_buffer(4096)
            self.gl.glGetProgramInfoLog(prog, 4096, None, buf)
            self.gl.glDeleteProgram(prog)
            raise RuntimeError(f"Link error in {glsl_path} ({version_hdr}):\n{buf.value.decode('utf-8', 'replace')}")
        return prog

    def _make_tex(self, w: int, h: int, data_ptr: ctypes.c_void_p = None) -> ctypes.c_uint:
        t = ctypes.c_uint(0)
        self.gl.glGenTextures(1, ctypes.byref(t))
        self.gl.glBindTexture(self.GL_TEXTURE_2D, t)
        self.gl.glTexParameteri(self.GL_TEXTURE_2D, self.GL_TEXTURE_MIN_FILTER, self.GL_NEAREST)
        self.gl.glTexParameteri(self.GL_TEXTURE_2D, self.GL_TEXTURE_MAG_FILTER, self.GL_NEAREST)
        self.gl.glTexParameteri(self.GL_TEXTURE_2D, self.GL_TEXTURE_WRAP_S, self.GL_CLAMP_TO_EDGE)
        self.gl.glTexParameteri(self.GL_TEXTURE_2D, self.GL_TEXTURE_WRAP_T, self.GL_CLAMP_TO_EDGE)
        self.gl.glPixelStorei(self.GL_UNPACK_ALIGNMENT, 1)
        self.gl.glTexImage2D(self.GL_TEXTURE_2D, 0, self.GL_RGBA, w, h, 0, self.GL_RGBA, self.GL_UNSIGNED_BYTE, data_ptr)
        return t

    def render_pipeline(
        self, progs: list[int], in_rgba, scale: int = 6,
        minc: float = 20.0, diag: float = 100.0, tol: float = 15.0, steep: float = 3.2, dom: float = 3.8
    ):
        import numpy as np
        h, w, _ = in_rgba.shape
        ow, oh = w * scale, h * scale
        n = len(progs)
        ident = (ctypes.c_float * 16)(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

        tex_orig = self._make_tex(w, h, ctypes.c_void_p(in_rgba.ctypes.data))
        tex_pass = (ctypes.c_uint * n)()
        fbos = (ctypes.c_uint * n)()
        self.gl.glGenFramebuffers(n, fbos)
        for i in range(n):
            pw, ph = (ow, oh) if i == n - 1 else (w, h)
            tex_pass[i] = self._make_tex(pw, ph, None).value
            self.gl.glBindFramebuffer(self.GL_FRAMEBUFFER, fbos[i])
            self.gl.glFramebufferTexture2D(self.GL_FRAMEBUFFER, self.GL_COLOR_ATTACHMENT0, self.GL_TEXTURE_2D, tex_pass[i], 0)

        self.gl.glBindBuffer(self.GL_ARRAY_BUFFER, self.vbo)
        self.gl.glEnableVertexAttribArray(0)
        self.gl.glVertexAttribPointer(0, 4, self.GL_FLOAT, self.GL_FALSE, 32, ctypes.c_void_p(0))
        self.gl.glEnableVertexAttribArray(1)
        self.gl.glVertexAttribPointer(1, 4, self.GL_FLOAT, self.GL_FALSE, 32, ctypes.c_void_p(16))

        def u1f(p: int, name: bytes, v: float) -> None:
            loc = self.gl.glGetUniformLocation(p, name)
            if loc >= 0:
                self.gl.glUniform1f(loc, v)

        def u2f(p: int, name: bytes, x: float, y: float) -> None:
            loc = self.gl.glGetUniformLocation(p, name)
            if loc >= 0:
                self.gl.glUniform2f(loc, x, y)

        def utex(p: int, name: bytes, unit: int, tex: int) -> None:
            loc = self.gl.glGetUniformLocation(p, name)
            if loc >= 0:
                self.gl.glActiveTexture(self.GL_TEXTURE0 + unit)
                self.gl.glBindTexture(self.GL_TEXTURE_2D, tex)
                self.gl.glUniform1i(loc, unit)

        for i, p in enumerate(progs):
            pw, ph = (ow, oh) if i == n - 1 else (w, h)
            self.gl.glBindFramebuffer(self.GL_FRAMEBUFFER, fbos[i])
            self.gl.glViewport(0, 0, pw, ph)
            self.gl.glUseProgram(p)
            mvp = self.gl.glGetUniformLocation(p, b"MVPMatrix")
            if mvp >= 0:
                self.gl.glUniformMatrix4fv(mvp, 1, self.GL_FALSE, ident)
            u2f(p, b"TextureSize", float(w), float(h))
            u2f(p, b"InputSize", float(w), float(h))
            u2f(p, b"OutputSize", float(pw), float(ph))
            u1f(p, b"XBRZ_MINC", minc)
            u1f(p, b"XBRZ_DIAG", diag)
            u1f(p, b"XBRZ_TOL", tol)
            u1f(p, b"XBRZ_STEEP", steep)
            u1f(p, b"XBRZ_DOM", dom)
            utex(p, b"Texture", 0, tex_orig.value if i == 0 else tex_pass[i - 1])
            if n == 5:
                if i == 2:
                    utex(p, b"PassPrev2Texture", 1, tex_pass[0])
                    u2f(p, b"PassPrev2TextureSize", float(w), float(h))
                    u2f(p, b"PassPrev2InputSize", float(w), float(h))
                elif i == 3:
                    utex(p, b"PassPrev2Texture", 1, tex_pass[1])
                    u2f(p, b"PassPrev2TextureSize", float(w), float(h))
                    utex(p, b"PassPrev3Texture", 2, tex_pass[0])
                    u2f(p, b"PassPrev3TextureSize", float(w), float(h))
                    u2f(p, b"PassPrev3InputSize", float(w), float(h))
                elif i == 4:
                    utex(p, b"PassPrev4Texture", 1, tex_pass[0])
                    u2f(p, b"PassPrev4TextureSize", float(w), float(h))
                    u2f(p, b"PassPrev4InputSize", float(w), float(h))
            elif n == 4:
                if i == 2:
                    utex(p, b"PassPrev2Texture", 1, tex_pass[0])
                    u2f(p, b"PassPrev2TextureSize", float(w), float(h))
                    u2f(p, b"PassPrev2InputSize", float(w), float(h))
                elif i == 3:
                    utex(p, b"PassPrev3Texture", 1, tex_pass[0])
                    u2f(p, b"PassPrev3TextureSize", float(w), float(h))
                    u2f(p, b"PassPrev3InputSize", float(w), float(h))
            self.gl.glDrawArrays(self.GL_TRIANGLE_STRIP, 0, 4)

        out = np.empty((oh, ow, 4), dtype=np.uint8)
        self.gl.glBindFramebuffer(self.GL_FRAMEBUFFER, fbos[n - 1])
        self.gl.glPixelStorei(self.GL_PACK_ALIGNMENT, 1)
        self.gl.glReadPixels(0, 0, ow, oh, self.GL_RGBA, self.GL_UNSIGNED_BYTE, ctypes.c_void_p(out.ctypes.data))
        self.gl.glDeleteFramebuffers(n, fbos)
        self.gl.glDeleteTextures(n, tex_pass)
        self.gl.glDeleteTextures(1, ctypes.byref(tex_orig))
        return out[:, :, :3]

    def close(self) -> None:
        self.gl.glDeleteBuffers(1, ctypes.byref(self.vbo))
        self.egl.eglMakeCurrent(self.dpy, None, None, None)
        self.egl.eglDestroyContext(self.dpy, self.ctx)
        self.egl.eglTerminate(self.dpy)


def check_static_lint() -> None:
    bad_p = re.compile(r"\b(?:vec[234]|ivec[234]|bvec[234]|float|int|bool)\s+P\b")
    fn_macro_def = re.compile(r"^\s*#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)\(")
    ubo_syms = ("XBRZ_TOL", "XBRZ_DOM", "XBRZ_STEEP", "XBRZ_MINC", "XBRZ_DIAG", "TOL_E", "DOM_E", "STEEP_E")
    fn_macros = set()
    inc_files = sorted(fn for fn in os.listdir(SRC_DIR) if fn.endswith(".inc"))
    for fn in inc_files:
        with open(os.path.join(SRC_DIR, fn), "r", encoding="utf-8") as f:
            for line in f:
                m = fn_macro_def.match(line)
                if m:
                    fn_macros.add(m.group(1))
    bad_ubo_arg = (
        re.compile(r"\b(?:" + "|".join(sorted(fn_macros)) + r")\s*\([^;\n]*\b(?:" + "|".join(ubo_syms) + r")\b")
        if fn_macros
        else None
    )
    for fn in inc_files:
        p = os.path.join(SRC_DIR, fn)
        with open(p, "r", encoding="utf-8") as f:
            for lineno, line in enumerate(f, 1):
                code = line.split("//", 1)[0]
                if bad_p.search(code):
                    raise RuntimeError(f"Macro shadowing `P` variable/param in {fn}:{lineno}: {line.strip()}")
                if bad_ubo_arg and not code.lstrip().startswith("#") and bad_ubo_arg.search(code):
                    raise RuntimeError(
                        f"UBO parameter macro passed to function-like macro in {fn}:{lineno} "
                        f"(breaks older RetroArch Vulkan glslang): {line.strip()}"
                    )


def check_single_source_sync() -> str:
    tmp = tempfile.mkdtemp(prefix="xbrz_verify_")
    out_sh = os.path.join(tmp, "shaders")
    out_mp = os.path.join(tmp, "multipass")
    subprocess.check_call([sys.executable, os.path.join(TOOLS_DIR, "build-shaders.py"), out_sh], stdout=subprocess.DEVNULL)
    for root, _, files in os.walk(out_sh):
        for fn in files:
            gen_p = os.path.join(root, fn)
            rel = os.path.relpath(gen_p, out_sh)
            repo_p = os.path.join(SHADERS_DIR, rel)
            if not os.path.isfile(repo_p):
                shutil.rmtree(tmp)
                raise RuntimeError(f"Missing generated shader in shaders/: {rel} (run tools/build-shaders.py)")
            with open(gen_p, "rb") as f1, open(repo_p, "rb") as f2:
                if f1.read() != f2.read():
                    shutil.rmtree(tmp)
                    raise RuntimeError(f"Out-of-sync generated shader: shaders/{rel} (run tools/build-shaders.py)")
    subprocess.check_call([sys.executable, os.path.join(TOOLS_DIR, "make-multipass.py"), out_mp], stdout=subprocess.DEVNULL)
    return tmp


def _slang_to_essl310(src: str) -> bytes:
    """Translate Vulkan-GLSL binding/push_constant decorators to plain ESSL 3.10 for Mesa validation."""
    src = re.sub(r"layout\s*\(\s*push_constant\s*\)\s*uniform\s+", "layout(std140) uniform ", src)
    src = re.sub(r"layout\s*\(\s*std140\s*,\s*set\s*=\s*\d+\s*,\s*binding\s*=\s*\d+\s*\)", "layout(std140)", src)
    src = re.sub(r"layout\s*\(\s*set\s*=\s*\d+\s*,\s*binding\s*=\s*\d+\s*\)\s*", "", src)
    return src.encode("utf-8")


def check_slang_validator(slang_dir: str, gles: HeadlessGLES) -> tuple[int, int]:
    validator = shutil.which("glslangValidator")
    checked_spv = 0
    checked_es31 = 0
    with tempfile.TemporaryDirectory(prefix="xbrz_slang_") as td:
        for fn in sorted(os.listdir(slang_dir)):
            if not fn.endswith(".slang"):
                continue
            with open(os.path.join(slang_dir, fn), "r", encoding="utf-8") as f:
                raw = f.read()
            clean_lines = [ln for ln in raw.splitlines() if not ln.startswith("#pragma parameter")]
            text = "\n".join(clean_lines)
            v_idx = text.index("#pragma stage vertex")
            f_idx = text.index("#pragma stage fragment")
            hdr = text[:v_idx]
            v_src = hdr + text[v_idx + len("#pragma stage vertex") : f_idx]
            f_src = hdr + text[f_idx + len("#pragma stage fragment") :]
            if validator:
                for ext, src in (("vert", v_src), ("frag", f_src)):
                    sp = os.path.join(td, f"{fn}.{ext}")
                    spv = sp + ".spv"
                    with open(sp, "w", encoding="utf-8") as out:
                        out.write(src)
                    subprocess.check_call([validator, "-V", "-S", ext, sp, "-o", spv], stdout=subprocess.DEVNULL)
                    checked_spv += 1
            for stype, src in ((gles.GL_VERTEX_SHADER, v_src), (gles.GL_FRAGMENT_SHADER, f_src)):
                sh = gles.gl.glCreateShader(stype)
                ptr = ctypes.c_char_p(_slang_to_essl310(src))
                gles.gl.glShaderSource(sh, 1, ctypes.byref(ptr), None)
                gles.gl.glCompileShader(sh)
                ok = ctypes.c_int(0)
                gles.gl.glGetShaderiv(sh, gles.GL_COMPILE_STATUS, ctypes.byref(ok))
                if not ok.value:
                    buf = ctypes.create_string_buffer(4096)
                    gles.gl.glGetShaderInfoLog(sh, 4096, None, buf)
                    gles.gl.glDeleteShader(sh)
                    raise RuntimeError(f"Slang ESSL 3.10 compile error in {fn}:\n{buf.value.decode('utf-8', 'replace')}")
                gles.gl.glDeleteShader(sh)
                checked_es31 += 1
    return checked_spv, checked_es31


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--diff", action="store_true", help="Compare 12 GBA scenes against docs/img/*-crisp20.png")
    ap.add_argument("--save-baseline", metavar="DIR", help="Render 12 GBA scenes at 6x into DIR")
    ap.add_argument("--diff-baseline", metavar="DIR", help="Compare 12 GBA scenes at 6x against DIR")
    args = ap.parse_args()

    check_static_lint()
    print("[verify] Static lint OK (zero macro shadowing)")

    tmp = check_single_source_sync()
    try:
        print("[verify] Single-source sync & make-multipass OK")
        crisp_glsl = os.path.join(SHADERS_DIR, "shaders_glsl", "xbrz", "shaders", "xbrz-crisp")
        crisp_slang = os.path.join(SHADERS_DIR, "shaders_slang", "edge-smoothing", "xbrz", "shaders", "xbrz-crisp")
        mp_glsl = os.path.join(tmp, "multipass", "glsl-shaders", "xbrz", "shaders", "xbrz-freescale-multipass")
        mp_slang = os.path.join(tmp, "multipass", "slang-shaders", "edge-smoothing", "xbrz", "shaders", "xbrz-freescale-multipass")

        gles = HeadlessGLES()
        try:
            for hdr, puni in (("#version 100", True), ("#version 100", False), ("#version 300 es", True), ("#version 310 es", True)):
                for p in ("point", "pass0", "resolve", "match", "pass1"):
                    prog = gles.compile_program(os.path.join(crisp_glsl, f"xbrz-crisp-{p}.glsl"), hdr, puni)
                    gles.gl.glDeleteProgram(prog)
                for p in ("point", "pass0", "resolve", "pass1"):
                    prog = gles.compile_program(os.path.join(mp_glsl, f"xbrz-freescale-{p}.glsl"), hdr, puni)
                    gles.gl.glDeleteProgram(prog)
            print("[verify] GLSL compilation OK (#version 100 default/uniform + #version 300 es + #version 310 es, 5-pass Crisp & 4-pass Multipass)")

            n_spv1, n_es1 = check_slang_validator(crisp_slang, gles)
            n_spv2, n_es2 = check_slang_validator(mp_slang, gles)
            print(f"[verify] Slang ESSL 3.10 validation OK ({n_es1 + n_es2} stages across Crisp & Multipass)")
            if n_spv1 + n_spv2:
                print(f"[verify] Vulkan SPIR-V validation OK ({n_spv1 + n_spv2} stages via glslangValidator)")

            if args.save_baseline or args.diff or args.diff_baseline:
                import numpy as np
                from PIL import Image

                progs = [
                    gles.compile_program(os.path.join(crisp_glsl, f"xbrz-crisp-{p}.glsl"), "#version 300 es", True)
                    for p in ("point", "pass0", "resolve", "match", "pass1")
                ]
                scenes = sorted(glob.glob(os.path.join(DOCS_IMG_DIR, "*-original.png")))
                if args.save_baseline:
                    os.makedirs(args.save_baseline, exist_ok=True)
                total_changed = 0
                compared = 0
                for sp in scenes:
                    sid = os.path.basename(sp).replace("-original.png", "")
                    inp = np.ascontiguousarray(np.array(Image.open(sp).convert("RGBA"), dtype=np.uint8))
                    rgb = gles.render_pipeline(progs, inp, scale=6, minc=20.0, diag=100.0, tol=15.0, steep=3.2, dom=3.8)
                    if args.save_baseline:
                        Image.fromarray(rgb, "RGB").save(os.path.join(args.save_baseline, f"{sid}.png"))
                    ref_path = None
                    if args.diff_baseline:
                        ref_path = os.path.join(args.diff_baseline, f"{sid}.png")
                    elif args.diff:
                        ref_path = os.path.join(DOCS_IMG_DIR, f"{sid}-crisp20.png")
                    if ref_path and os.path.isfile(ref_path):
                        compared += 1
                        ref = np.array(Image.open(ref_path).convert("RGB"), dtype=np.uint8)
                        diff = np.max(np.abs(rgb.astype(np.int16) - ref.astype(np.int16)), axis=2)
                        tol_lsb = 0 if args.diff_baseline else 1
                        ch = int(np.sum(diff > tol_lsb))
                        total_changed += ch
                        pct = ch / (rgb.shape[0] * rgb.shape[1]) * 100.0
                        print(f"  {sid:16s}: changed={ch:6d} px ({pct:6.3f}%), max_delta={int(np.max(diff)):3d}")
                for prog in progs:
                    gles.gl.glDeleteProgram(prog)
                if args.save_baseline:
                    print(f"[verify] Saved {len(scenes)} baseline 6x PNGs to {args.save_baseline}")
                if (args.diff or args.diff_baseline) and compared == 0:
                    print("[verify] No local reference PNGs found (run `python3 tools/render-docs.py` or `--save-baseline DIR` first).")
                if args.diff_baseline and total_changed > 0:
                    sys.exit(f"[verify] Baseline diff detected {total_changed} changed pixels!")
        finally:
            gles.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
