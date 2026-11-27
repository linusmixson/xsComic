#pragma once

#include "XSCBase.h"
#include "XSCImageStore.h"

#include <SDL2/SDL_opengl.h>

typedef struct XSCGLProcs {
    PFNGLGENVERTEXARRAYSPROC genVertexArrays;
    PFNGLDELETEVERTEXARRAYSPROC deleteVertexArrays;
    PFNGLBINDVERTEXARRAYPROC bindVertexArray;
    PFNGLCREATESHADERPROC createShader;
    PFNGLSHADERSOURCEPROC shaderSource;
    PFNGLCOMPILESHADERPROC compileShader;
    PFNGLGETSHADERIVPROC getShaderiv;
    PFNGLGETSHADERINFOLOGPROC getShaderInfoLog;
    PFNGLDELETESHADERPROC deleteShader;
    PFNGLCREATEPROGRAMPROC createProgram;
    PFNGLATTACHSHADERPROC attachShader;
    PFNGLLINKPROGRAMPROC linkProgram;
    PFNGLGETPROGRAMIVPROC getProgramiv;
    PFNGLGETPROGRAMINFOLOGPROC getProgramInfoLog;
    PFNGLDELETEPROGRAMPROC deleteProgram;
    PFNGLUSEPROGRAMPROC useProgram;
    PFNGLGETUNIFORMLOCATIONPROC getUniformLocation;
    PFNGLUNIFORM1IPROC uniform1i;
    PFNGLUNIFORM1FPROC uniform1f;
    PFNGLUNIFORM2FPROC uniform2f;
    PFNGLUNIFORM4FPROC uniform4f;
    PFNGLACTIVETEXTUREPROC activeTexture;
    PFNGLGENERATEMIPMAPPROC generateMipmap;
    PFNGLBLENDFUNCSEPARATEPROC blendFuncSeparate;
} XSCGLProcs;

/// Loads required OpenGL 3.3 Core entry points via SDL_GL_GetProcAddress.
bool xsc_gl_load_procs(XSCGLProcs *gl);

/// Compiles and links an OpenGL 3.3 vertex/fragment shader pair, freeing intermediates on every path.
GLuint xsc_gl_build_program(const XSCGLProcs *gl,
                            const char *vsSrc,
                            const char *fsSrc,
                            const char *label,
                            int baseErrCode) throws(XSCError *);

typedef enum XSCZoomMode {
    XSCZoomModeFit = 0,
    XSCZoomModeCustom = 1,
} XSCZoomMode;

typedef struct XSCRectF {
    float x;
    float y;
    float width;
    float height;
} XSCRectF;

typedef void (^XSCZoomChangedBlock)(XSCZoomMode mode, float effectiveScale);

/*
 XSCGLCanvas renders comic pages directly through OpenGL 3.3 Core with hybrid
 Lanczos-3 (1.05x-3x) and lazy trilinear mipmap (>3x) downscaling, an EXIF 1..8
 orientation transform, .rrr1 grayscale swizzling for GL_R8 manga textures, 1 px
 hairline page borders, focal-point zooming, drag panning, and multi-frame GIF
 playback.
 */
@interface XSCGLCanvas : XSCObject

@property (nonatomic, readonly) XSCZoomMode zoomMode;
@property (nonatomic, readonly) float zoomScale;
@property (nonatomic, readonly) bool showEmptyCTA;
@property (nonatomic, readonly) bool isLoading;
@property (nonatomic, readonly) XSCOptString statusText;
@property (nonatomic, strong) XSCZoomChangedBlock onZoomChanged;

- (instancetype)init;

/// Compiles the inline GLSL 330 shader and allocates GPU resources. Requires an active GL context.
- (void)initializeGL throws(XSCError *);
- (void)shutdownGL;

/// Updates the canvas viewport (in logical window coordinates, top-left origin) and drawable size.
- (void)setViewportRect:(XSCRectF)viewport
          drawableWidth:(int)drawableW
         drawableHeight:(int)drawableH
           backingScale:(float)scale;

/// Synchronously updates displayed pages and uploads textures on change.
- (void)displayLeftPage:(XSCOptDecodedPage)leftPage
              rightPage:(XSCOptDecodedPage)rightPage
           showEmptyCTA:(bool)showEmptyCTA
              isLoading:(bool)isLoading
             statusText:(XSCOptString)statusText;

- (void)setFitMode;
- (void)setCustomScale:(float)scale;
- (void)adjustZoomByFactor:(float)factor;
/// Zooms around a point in canvas-local coordinates (top-left origin).
- (void)zoomAroundPointX:(float)px y:(float)py factor:(float)factor;
- (void)panByDeltaX:(float)dx deltaY:(float)dy;
- (void)resetPan;

/// Advances animated GIF frames if due; returns true if a texture changed and needs redraw.
- (bool)tickAnimationAtMs:(uint64_t)nowMs;

/// Monotonic deadline for either visible GIF, or UINT64_MAX when neither is advancing.
- (uint64_t)nextAnimationDeadlineMs;

/// Renders the visible pages over the caller's cleared background.
- (void)render;

@end
