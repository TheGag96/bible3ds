/**
 * @file base.h
 * @brief Basic citro2d initialization and drawing API
 */

module citro2d.base;

import ctru.allocator;
import ctru.gfx;
import ctru.gpu;
import ctru.services.gspgpu;
import ctru.types;
import citro3d;
import citro2d.internal;

extern (C): nothrow: @nogc:

enum C2D_DEFAULT_MAX_OBJECTS = 4096;

enum C2DShader {
  normal,
  scanline_offset,
}

enum C2D_NUM_SHADERS = C2DShader.max + 1;

__gshared C2Di_Context[C2D_NUM_SHADERS] __C2Di_Contexts;
__gshared C3D_Mtx s_projTop, s_projBot;
__gshared C2DShader __C2Di_CurrentShader;

enum SHADER_GET(string name) = cast(immutable(ubyte)[]) import(name ~ ".shbin");

static immutable RENDER2D_SHBIN = SHADER_GET!("render2d");
static immutable RENDER2G_SHBIN = SHADER_GET!("render2g");

struct C2D_DrawParams
{
    struct _Anonymous_0
    {
        float x = 0;
        float y = 0;
        float w = 0;
        float h = 0;
    }

    _Anonymous_0 pos;

    struct _Anonymous_1
    {
        float x = 0;
        float y = 0;
    }

    _Anonymous_1 center;

    float depth = 0;
    float angle = 0;
}

struct C2D_Tint
{
    uint color; ///< RGB tint color and Alpha transparency
    float blend = 0; ///< Blending strength of the tint color (0.0~1.0)
}

enum C2DCorner : ubyte
{
    top_left     = 0, ///< Top left corner
    top_right    = 1, ///< Top right corner
    bottom_left  = 2, ///< Bottom left corner
    bottom_right = 3  ///< Bottom right corner
}

struct C2D_Image
{
    C3D_Tex* tex;
    const(Tex3DS_SubTexture)* subtex;
}

struct C2D_ImageTint
{
    C2D_Tint[4] corners;
}

/** @defgroup Helper Helper functions
 *  @{
 */

pragma(inline, true)
C2Di_Context* C2Di_GetContext()
{
    return &__C2Di_Contexts[__C2Di_CurrentShader];
}

/** @brief Clamps a value between bounds
 *  @param[in] x The value to clamp
 *  @param[in] min The lower bound
 *  @param[in] max The upper bound
 *  @returns The clamped value
 */
pragma(inline, true)
float C2D_Clamp(float x, float min, float max)
{
    return x <= min ? min : x >= max ? max : x;
}

/** @brief Converts a float to ubyte
 *  @param[in] x Input value (0.0~1.0)
 *  @returns Output value (0~255)
 */
pragma(inline, true)
ubyte C2D_FloatToU8(float x)
{
    return cast(ubyte)(255.0f*C2D_Clamp(x, 0.0f, 1.0f)+0.5f);
}

/** @brief Builds a 32-bit RGBA color value
 *  @param[in] r Red component (0~255)
 *  @param[in] g Green component (0~255)
 *  @param[in] b Blue component (0~255)
 *  @param[in] a Alpha component (0~255)
 *  @returns The 32-bit RGBA color value
 */
pragma(inline, true)
uint C2D_Color32(ubyte r, ubyte g, ubyte b, ubyte a)
{
    return r | (g << cast(uint)8) | (b << cast(uint)16) | (a << cast(uint)24);
}

/** @brief Builds a 32-bit RGBA color value from float values
 *  @param[in] r Red component (0.0~1.0)
 *  @param[in] g Green component (0.0~1.0)
 *  @param[in] b Blue component (0.0~1.0)
 *  @param[in] a Alpha component (0.0~1.0)
 *  @returns The 32-bit RGBA color value
 */
pragma(inline, true)
uint C2D_Color32f(float r, float g, float b, float a)
{
    return C2D_Color32(C2D_FloatToU8(r),C2D_FloatToU8(g),C2D_FloatToU8(b),C2D_FloatToU8(a));
}

/** @brief Configures one corner of an image tint structure
 *  @param[in] tint Image tint structure
 *  @param[in] corner The corner of the image to tint
 *  @param[in] color RGB tint color and Alpha transparency
 *  @param[in] blend Blending strength of the tint color (0.0~1.0)
 */
pragma(inline, true)
void C2D_SetImageTint(C2D_ImageTint* tint, C2DCorner corner, uint color, float blend)
{
    tint.corners[corner].color = color;
    tint.corners[corner].blend = blend;
}

/** @brief Configures an image tint structure with the specified tint parameters applied to all corners
 *  @param[in] tint Image tint structure
 *  @param[in] color RGB tint color and Alpha transparency
 *  @param[in] blend Blending strength of the tint color (0.0~1.0)
 */
pragma(inline, true)
void C2D_PlainImageTint(C2D_ImageTint* tint, uint color, float blend)
{
    C2D_SetImageTint(tint, C2DCorner.top_left,  color, blend);
    C2D_SetImageTint(tint, C2DCorner.top_right, color, blend);
    C2D_SetImageTint(tint, C2DCorner.bottom_left,  color, blend);
    C2D_SetImageTint(tint, C2DCorner.bottom_right, color, blend);
}

/** @brief Configures an image tint structure to just apply transparency to the image
 *  @param[in] tint Image tint structure
 *  @param[in] alpha Alpha transparency value to apply to the image
 */
pragma(inline, true)
void C2D_AlphaImageTint(C2D_ImageTint* tint, float alpha)
{
    C2D_PlainImageTint(tint, C2D_Color32f(0.0f, 0.0f, 0.0f, alpha), 0.0f);
}

/** @brief Configures an image tint structure with the specified tint parameters applied to the top side (e.g. for gradients)
 *  @param[in] tint Image tint structure
 *  @param[in] color RGB tint color and Alpha transparency
 *  @param[in] blend Blending strength of the tint color (0.0~1.0)
 */
pragma(inline, true)
void C2D_TopImageTint(C2D_ImageTint* tint, uint color, float blend)
{
    C2D_SetImageTint(tint, C2DCorner.top_left,  color, blend);
    C2D_SetImageTint(tint, C2DCorner.top_right, color, blend);
}

/** @brief Configures an image tint structure with the specified tint parameters applied to the bottom side (e.g. for gradients)
 *  @param[in] tint Image tint structure
 *  @param[in] color RGB tint color and Alpha transparency
 *  @param[in] blend Blending strength of the tint color (0.0~1.0)
 */
pragma(inline, true)
void C2D_BottomImageTint(C2D_ImageTint* tint, uint color, float blend)
{
    C2D_SetImageTint(tint, C2DCorner.bottom_left,  color, blend);
    C2D_SetImageTint(tint, C2DCorner.bottom_right, color, blend);
}

/** @brief Configures an image tint structure with the specified tint parameters applied to the left side (e.g. for gradients)
 *  @param[in] tint Image tint structure
 *  @param[in] color RGB tint color and Alpha transparency
 *  @param[in] blend Blending strength of the tint color (0.0~1.0)
 */
pragma(inline, true)
void C2D_LeftImageTint(C2D_ImageTint* tint, uint color, float blend)
{
    C2D_SetImageTint(tint, C2DCorner.top_left, color, blend);
    C2D_SetImageTint(tint, C2DCorner.bottom_left, color, blend);
}

/** @brief Configures an image tint structure with the specified tint parameters applied to the right side (e.g. for gradients)
 *  @param[in] tint Image tint structure
 *  @param[in] color RGB tint color and Alpha transparency
 *  @param[in] blend Blending strength of the tint color (0.0~1.0)
 */
pragma(inline, true)
void C2D_RightImageTint(C2D_ImageTint* tint, uint color, float blend)
{
    C2D_SetImageTint(tint, C2DCorner.top_right, color, blend);
    C2D_SetImageTint(tint, C2DCorner.bottom_right, color, blend);
}

/** @} */

/** @defgroup Base Basic functions
 *  @{
 */

/** @brief Configures the size of the 2D scene to match that of the specified render target.
 *  @param[in] target Render target
 */
pragma(inline, true)
void C2D_SceneTarget(C3D_RenderTarget* target)
{
    C2D_SceneSize(target.frameBuf.width, target.frameBuf.height, target.linked);
}

/** @brief Helper function to begin drawing a 2D scene on a render target
 *  @param[in] target Render target to draw the 2D scene to
 */
pragma(inline, true)
void C2D_SceneBegin(C3D_RenderTarget* target)
{
    C2D_Flush();
    C3D_FrameDrawOn(target);
    C2D_SceneTarget(target);
}

/** @} */

/** @defgroup Env Drawing environment functions
 *  @{
 */

/** @} */

/** @defgroup Drawing Drawing functions
 *  @{
 */

/** @brief Draws an image using the GPU (variant accepting C2D_DrawParams)
 *  @param[in] img Handle of the image to draw
 *  @param[in] params Parameters with which to draw the image
 *  @param[in] tint Tint parameters to apply to the image (optional, can be null)
 *  @returns true on success, false on failure
 */
//bool C2D_DrawImage(C2D_Image img, const(C2D_DrawParams)* params, const(C2D_ImageTint)* tint);

/** @brief Draws an image using the GPU (variant accepting position/scaling)
 *  @param[in] img Handle of the image to draw
 *  @param[in] x X coordinate at which to place the top left corner of the image
 *  @param[in] y Y coordinate at which to place the top left corner of the image
 *  @param[in] depth Depth value to draw the image with
 *  @param[in] tint Tint parameters to apply to the image (optional, can be null)
 *  @param[in] scaleX Horizontal scaling factor to apply to the image (optional, by default 1.0f); negative values apply a horizontal flip
 *  @param[in] scaleY Vertical scaling factor to apply to the image (optional, by default 1.0f); negative values apply a vertical flip
 */
pragma(inline, true)
bool C2D_DrawImageAt(C2D_Image img, float x, float y, float depth,
    const(C2D_ImageTint)* tint = null,
    float scaleX = 1.0f, float scaleY = 1.0f)
{
    C2D_DrawParams params = C2D_DrawParams
    (
        C2D_DrawParams._Anonymous_0( x, y, scaleX*img.subtex.width, scaleY*img.subtex.height ),
        C2D_DrawParams._Anonymous_1( 0.0f, 0.0f ),
        depth, 0.0f
    );
    return C2D_DrawImage(img, &params, tint);
}

/** @brief Draws an image using the GPU (variant accepting position/scaling/rotation)
 *  @param[in] img Handle of the image to draw
 *  @param[in] x X coordinate at which to place the center of the image
 *  @param[in] y Y coordinate at which to place the center of the image
 *  @param[in] depth Depth value to draw the image with
 *  @param[in] angle Angle (in radians) to rotate the image by, counter-clockwise
 *  @param[in] tint Tint parameters to apply to the image (optional, can be null)
 *  @param[in] scaleX Horizontal scaling factor to apply to the image (optional, by default 1.0f); negative values apply a horizontal flip
 *  @param[in] scaleY Vertical scaling factor to apply to the image (optional, by default 1.0f); negative values apply a vertical flip
 */
pragma(inline, true)
bool C2D_DrawImageAtRotated(
    C2D_Image img,
    float x,
    float y,
    float depth,
    float angle,
    const(C2D_ImageTint)* tint,
    float scaleX,
    float scaleY)
{
    C2D_DrawParams params =
    {
        { x, y, scaleX*img.subtex.width, scaleY*img.subtex.height },
        { img.subtex.width/2.0f, img.subtex.height/2.0f },
        depth, angle
    };
    return C2D_DrawImage(img, &params, tint);
}

/** @brief Draws a plain rectangle using the GPU (with a solid color)
 *  @param[in] x X coordinate of the top-left vertex of the rectangle
 *  @param[in] y Y coordinate of the top-left vertex of the rectangle
 *  @param[in] z Z coordinate (depth value) to draw the rectangle with
 *  @param[in] w Width of the rectangle
 *  @param[in] h Height of the rectangle
 *  @param[in] clr 32-bit RGBA color of the rectangle
 */
pragma(inline, true)
bool C2D_DrawRectSolid(float x, float y, float z, float w, float h, uint clr)
{
    return C2D_DrawRectangle(x,y,z,w,h,clr,clr,clr,clr);
}

/** @brief Draws a ellipse using the GPU (with a solid color)
 *  @param[in] x X coordinate of the top-left vertex of the ellipse
 *  @param[in] y Y coordinate of the top-left vertex of the ellipse
 *  @param[in] z Z coordinate (depth value) to draw the ellipse with
 *  @param[in] w Width of the ellipse
 *  @param[in] h Height of the ellipse
 *  @param[in] clr 32-bit RGBA color of the ellipse
 *  @note Switching to and from "circle mode" internally requires an expensive state change. As such, the recommended usage of this feature is to draw all non-circular objects first, then draw all circular objects.
*/
pragma(inline, true)
bool C2D_DrawEllipseSolid(
    float x,
    float y,
    float z,
    float w,
    float h,
    uint clr)
{
    return C2D_DrawEllipse(x,y,z,w,h,clr,clr,clr,clr);
}

/** @brief Draws a circle (an ellipse with identical width and height) using the GPU
 *  @param[in] x X coordinate of the center of the circle
 *  @param[in] y Y coordinate of the center of the circle
 *  @param[in] z Z coordinate (depth value) to draw the ellipse with
 *  @param[in] radius Radius of the circle
 *  @param[in] clr0 32-bit RGBA color of the top-left corner of the ellipse
 *  @param[in] clr1 32-bit RGBA color of the top-right corner of the ellipse
 *  @param[in] clr2 32-bit RGBA color of the bottom-left corner of the ellipse
 *  @param[in] clr3 32-bit RGBA color of the bottom-right corner of the ellipse
 *  @note Switching to and from "circle mode" internally requires an expensive state change. As such, the recommended usage of this feature is to draw all non-circular objects first, then draw all circular objects.
*/
pragma(inline, true)
bool C2D_DrawCircle(
    float x,
    float y,
    float z,
    float radius,
    uint clr0,
    uint clr1,
    uint clr2,
    uint clr3)
{
    return C2D_DrawEllipse(
        x - radius,y - radius,z,radius*2,radius*2,
        clr0,clr1,clr2,clr3);
}

/** @brief Draws a circle (an ellipse with identical width and height) using the GPU (with a solid color)
 *  @param[in] x X coordinate of the center of the circle
 *  @param[in] y Y coordinate of the center of the circle
 *  @param[in] z Z coordinate (depth value) to draw the ellipse with
 *  @param[in] radius Radius of the circle
 *  @param[in] clr0 32-bit RGBA color of the top-left corner of the ellipse
 *  @param[in] clr1 32-bit RGBA color of the top-right corner of the ellipse
 *  @param[in] clr2 32-bit RGBA color of the bottom-left corner of the ellipse
 *  @param[in] clr3 32-bit RGBA color of the bottom-right corner of the ellipse
 *  @note Switching to and from "circle mode" internally requires an expensive state change. As such, the recommended usage of this feature is to draw all non-circular objects first, then draw all circular objects.
*/
pragma(inline, true)
bool C2D_DrawCircleSolid(float x, float y, float z, float radius, uint clr)
{
    return C2D_DrawCircle(x,y,z,radius,clr,clr,clr,clr);
}
/** @} */

static void C2Di_FrameEndHook(void* unused)
{
    C2Di_Context* ctx = C2Di_GetContext();
    C2Di_FlushVtxBuf();

    for (int shaderId = 0; shaderId < C2D_NUM_SHADERS; shaderId++) {
        ctx = &__C2Di_Contexts[shaderId];
        ctx.vtxBufPos = 0;
        ctx.vtxBufLastPos = 0;
    }
}

/** @brief Initialize citro2d
 *  @param[in] maxObjects Maximum number of 2D objects that can be drawn per frame.
 *  @remarks Pass C2D_DEFAULT_MAX_OBJECTS as a starting point.
 *  @returns true on success, false on failure
 */
bool C2D_Init(size_t maxObjects)
{
    __C2Di_CurrentShader = C2DShader.normal;

    for (int shaderId = 0; shaderId < C2D_NUM_SHADERS; shaderId++) {
        C2Di_Context* ctx = &__C2Di_Contexts[shaderId];
        if (ctx.flags & C2DiF_Active)
            return false;

        int vertsPerSprite;
        final switch (shaderId) {
            case C2DShader.normal:
                vertsPerSprite = 6;
                break;
            case C2DShader.scanline_offset:
                vertsPerSprite = 2;
                break;
        }

        ctx.vtxBufSize = vertsPerSprite*maxObjects;
        ctx.vtxBuf = cast(C2Di_Vertex*)linearAlloc(ctx.vtxBufSize*C2Di_Vertex.sizeof);
        if (!ctx.vtxBuf)
            return false;

        final switch (shaderId) {
            case C2DShader.normal:
                ctx.shader = DVLB_ParseFile(cast(uint*)RENDER2D_SHBIN.ptr, RENDER2D_SHBIN.length);
                break;
            case C2DShader.scanline_offset:
                ctx.shader = DVLB_ParseFile(cast(uint*)RENDER2G_SHBIN.ptr, RENDER2G_SHBIN.length);
                break;
        }

        if (!ctx.shader)
        {
            linearFree(ctx.vtxBuf);
            return false;
        }

        shaderProgramInit(&ctx.program);
        shaderProgramSetVsh(&ctx.program, &ctx.shader.DVLE[0]);

        final switch (shaderId) {
            case C2DShader.normal:
                shaderProgramSetGsh(&ctx.program, &ctx.shader.DVLE[1], cast(ubyte) (4*vertsPerSprite/2));
                break;
            case C2DShader.scanline_offset:
                shaderProgramSetGsh(&ctx.program, &ctx.shader.DVLE[1], cast(ubyte) (4*vertsPerSprite));
                break;
        }

        AttrInfo_Init(&ctx.attrInfo);
        AttrInfo_AddLoader(&ctx.attrInfo, 0, GPUFormats._float,        3); // v0=position
        AttrInfo_AddLoader(&ctx.attrInfo, 1, GPUFormats._float,        2); // v1=texcoord
        AttrInfo_AddLoader(&ctx.attrInfo, 2, GPUFormats._float,        2); // v2=blend
        AttrInfo_AddLoader(&ctx.attrInfo, 3, GPUFormats.unsigned_byte, 4); // v3=color

        BufInfo_Init(&ctx.bufInfo);
        BufInfo_Add(&ctx.bufInfo, ctx.vtxBuf, C2Di_Vertex.sizeof, 4, 0x3210);

        // Cache these common projection matrices
        Mtx_OrthoTilt(&s_projTop, 0.0f, 400.0f, 240.0f, 0.0f, 1.0f, -1.0f, true);
        Mtx_OrthoTilt(&s_projBot, 0.0f, 320.0f, 240.0f, 0.0f, 1.0f, -1.0f, true);

        // Get uniform locations
        ctx.uLoc_mdlvMtx = shaderInstanceGetUniformLocation(ctx.program.vertexShader, "mdlvMtx");
        ctx.uLoc_projMtx = shaderInstanceGetUniformLocation(ctx.program.vertexShader, "projMtx");

        // Prepare proctex
        C3D_ProcTexInit(&ctx.ptBlend, 0, 1);
        C3D_ProcTexClamp(&ctx.ptBlend, GPUProcTexClamp.clamp_to_edge, GPUProcTexClamp.clamp_to_edge);
        C3D_ProcTexCombiner(&ctx.ptBlend, true, GPUProcTexMapFunc.u, GPUProcTexMapFunc.v);
        C3D_ProcTexFilter(&ctx.ptBlend, GPUProcTexFilter.linear);

        C3D_ProcTexInit(&ctx.ptCircle, 0, 1);
        C3D_ProcTexClamp(&ctx.ptCircle, GPUProcTexClamp.mirrored_repeat, GPUProcTexClamp.mirrored_repeat);
        C3D_ProcTexCombiner(&ctx.ptCircle, true, GPUProcTexMapFunc.sqrt2, GPUProcTexMapFunc.sqrt2);
        C3D_ProcTexFilter(&ctx.ptCircle, GPUProcTexFilter.linear);

        // Prepare proctex lut
        float[129] data;
        int i;
        for (i = 0; i <= 128; i ++)
            data[i] = i/128.0f;
        ProcTexLut_FromArray(&ctx.ptBlendLut, data);

        for (i = 0; i <= 128; i ++)
            data[i] = (i >= 127) ? 0 : 1;
        ProcTexLut_FromArray(&ctx.ptCircleLut, data);

        ctx.flags = C2DiF_Active;
        ctx.vtxBufPos = 0;
        ctx.vtxBufLastPos = 0;
        Mtx_Identity(&ctx.projMtx);
        Mtx_Identity(&ctx.mdlvMtx);
        ctx.fadeClr = 0;
    }

    C3D_FrameEndHook(&C2Di_FrameEndHook, null);
    return true;
}

/** @brief Deinitialize citro2d */
void C2D_Fini()
{
    for (int shaderId = 0; shaderId < C2D_NUM_SHADERS; shaderId++) {
        C2Di_Context* ctx = &__C2Di_Contexts[shaderId];
        if (!(ctx.flags & C2DiF_Active))
            continue;

        ctx.flags = 0;
        shaderProgramFree(&ctx.program);
        DVLB_Free(ctx.shader);
        linearFree(ctx.vtxBuf);
    }
    C3D_FrameEndHook(null, null);
}

/** @brief Prepares the GPU for rendering 2D content
 *  @remarks This needs to be done only once in the program if citro2d is the sole user of the GPU.
 */
void C2D_Prepare(C2DShader shaderId)
{
  __C2Di_CurrentShader = shaderId;
  C2Di_Context* ctx = C2Di_GetContext();

  if (!(ctx.flags & C2DiF_Active))
        return;

  ctx.flags  = (ctx.flags &~ C2DiF_Src_Mask) | C2DiF_DirtyAny;
  ctx.curTex = null;

  C3D_BindProgram(&ctx.program);
  C3D_SetAttrInfo(&ctx.attrInfo);
  C3D_SetBufInfo(&ctx.bufInfo);
  C3D_ProcTexBind(1, &ctx.ptBlend);
  C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, &ctx.ptBlendLut);

  C3D_TexEnv* env;

  // Set texenv0 to retrieve the texture color (or white if disabled)
  // texenv0.rgba = texture2D(texunit0, vtx.texcoord0);
  env = C3D_GetTexEnv(0);
  C3D_TexEnvInit(env);
  //C3D_TexEnvSrc set afterwards by C2Di_Update()
  C3D_TexEnvFunc(env, C3DTexEnvMode.both, GPUCombineFunc.replace);
  C3D_TexEnvColor(env, 0xFFFFFFFF);

  //TexEnv1 set afterwards by C2Di_Update()

  /*
  // Set texenv2 to tint the output of texenv1 with the specified tint
  // texenv2.rgb = texenv1.rgb * colorwheel(vtx.blend.x);
  // texenv2.a   = texenv1.a;
  env = C3D_GetTexEnv(2);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3D_RGB, GPU_PREVIOUS, GPU_TEXTURE3, 0);
  C3D_TexEnvFunc(env, C3D_RGB, GPU_MODULATE);
  */

  // Set texenv5 to apply the fade color
  // texenv5.rgb = mix(texenv4.rgb, fadeclr.rgb, fadeclr.a);
  // texenv5.a   = texenv4.a;
  env = C3D_GetTexEnv(5);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.previous, GPUTevSrc.constant, GPUTevSrc.constant);
  C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color, GPUTevOpRGB.one_minus_src_alpha);
  C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.interpolate);
  C3D_TexEnvColor(env, ctx.fadeClr);

  // Configure depth test to overwrite pixels with the same depth (needed to draw overlapping sprites)
  C3D_DepthTest(true, GPUTestFunc.gequal, GPUWriteMask.all);

  // Don't cull anything
  C3D_CullFace(GPUCullMode.none);
}

/** @brief Ensures all 2D objects so far have been drawn */
void C2D_Flush()
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return;

    C2Di_FlushVtxBuf();
}

/** @brief Configures the size of the 2D scene.
 *  @param[in] width The width of the scene, in pixels.
 *  @param[in] height The height of the scene, in pixels.
 *  @param[in] tilt Whether the scene is tilted like the 3DS's sideways screens.
 */
void C2D_SceneSize(uint width, uint height, bool tilt)
{
    C3D_Mtx projResult;

    if (tilt)
    {
        uint temp = width;
        width = height;
        height = temp;
    }

    bool constructed = false;

    // Check for cached projection matrices
    if (height == GSP_SCREEN_WIDTH && tilt)
    {
        if (width == GSP_SCREEN_HEIGHT_TOP || width == GSP_SCREEN_HEIGHT_TOP_2X)
        {
            Mtx_Copy(&projResult, &s_projTop);
            constructed = true;
        }
        else if (width == GSP_SCREEN_HEIGHT_BOTTOM)
        {
            Mtx_Copy(&projResult, &s_projBot);
            constructed = true;
        }
    }

    // Construct the projection matrix
    if (!constructed) {
        (tilt ? &Mtx_OrthoTilt : &Mtx_Ortho)(&projResult, 0.0f, width, height, 0.0f, 1.0f, -1.0f, true);
    }

    for (int shaderId = 0; shaderId < C2D_NUM_SHADERS; shaderId++) {
        C2Di_Context* ctx = &__C2Di_Contexts[shaderId];

        if (!(ctx.flags & C2DiF_Active))
            continue;

        ctx.flags |= C2DiF_DirtyProj;
        ctx.sceneW = width;
        ctx.sceneH = height;

        Mtx_Copy(&ctx.projMtx, &projResult);
    }
}

void C2D_ViewReset()
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return;

    Mtx_Identity(&ctx.mdlvMtx);
    ctx.flags |= C2DiF_DirtyMdlv;
}

void C2D_ViewSave(C3D_Mtx* matrix)
{
    C2Di_Context* ctx = C2Di_GetContext();
    Mtx_Copy(matrix, &ctx.mdlvMtx);
}

void C2D_ViewRestore(const C3D_Mtx* matrix)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return;

    Mtx_Copy(&ctx.mdlvMtx, matrix);
    ctx.flags |= C2DiF_DirtyMdlv;
}

void C2D_ViewTranslate(float x, float y)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return;

    Mtx_Translate(&ctx.mdlvMtx, x, y, 0.0f, true);
    ctx.flags |= C2DiF_DirtyMdlv;
}

void C2D_ViewRotate(float radians)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return;

    Mtx_RotateZ(&ctx.mdlvMtx, radians, true);
    ctx.flags |= C2DiF_DirtyMdlv;
}

void C2D_ViewShear(float x, float y)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return;

    C3D_Mtx mult;
    Mtx_Identity(&mult);
    mult.r[0].y = x;
    mult.r[1].x = y;
    Mtx_Multiply(&ctx.mdlvMtx, &ctx.mdlvMtx, &mult);
    ctx.flags |= C2DiF_DirtyMdlv;
}

void C2D_ViewScale(float x, float y)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return;

    Mtx_Scale(&ctx.mdlvMtx, x, y, 1.0f);
    ctx.flags |= C2DiF_DirtyMdlv;
}

/** @brief Helper function to create a render target for a screen
 *  @param[in] screen Screen (GFXScreen.top or GFXScreen.bottom)
 *  @param[in] side Side (GFX_LEFT or GFX_RIGHT)
 *  @returns citro3d render target object
 */
C3D_RenderTarget* C2D_CreateScreenTarget(GFXScreen screen, GFX3DSide side)
{
    int height;
    switch (screen)
    {
        default:
        case GFXScreen.bottom:
            height = GSP_SCREEN_HEIGHT_BOTTOM;
            break;
        case GFXScreen.top:
            height = !gfxIsWide() ? GSP_SCREEN_HEIGHT_TOP : GSP_SCREEN_HEIGHT_TOP_2X;
            break;
    }
    C3D_RenderTarget* target = C3D_RenderTargetCreate(GSP_SCREEN_WIDTH, height, GPUColorBuf.rgba8, C3D_DEPTHTYPE(GPUDepthBuf.depth16));
    if (target)
        C3D_RenderTargetSetOutput(target, screen, side,
            GX_TRANSFER_FLIP_VERT(0) | GX_TRANSFER_OUT_TILED(0) | GX_TRANSFER_RAW_COPY(0) |
            GX_TRANSFER_IN_FORMAT(GxTransferFormat.rgba8) | GX_TRANSFER_OUT_FORMAT(GxTransferFormat.rgb8) |
            GX_TRANSFER_SCALING(GxTransferScale.no));
    return target;
}

/** @brief Helper function to clear a rendertarget using the specified color
 *  @param[in] target Render target to clear
 *  @param[in] color 32-bit RGBA color value to fill the target with
 */
void C2D_TargetClear(C3D_RenderTarget* target, uint color)
{
    import std.bitmanip : swapEndian;

    C2Di_FlushVtxBuf();
    C3D_FrameSplit(0);
    C3D_RenderTargetClear(target, C3DClearBits.clear_all, swapEndian(color), 0);
}

/** @brief Configures the fading color
 *  @param[in] color 32-bit RGBA color value to be used as the fading color (0 by default)
 *  @remark The alpha component of the color is used as the strength of the fading color.
 *          If alpha is zero, the fading color has no effect. If it is the highest value,
 *          the rendered pixels will all have the fading color. Everything inbetween is
 *          rendered as a blend of the original pixel color and the fading color.
 */
bool C2D_Fade(uint color)
{
    bool atLeastOne = false;

    foreach (shaderId; 0..C2D_NUM_SHADERS) {
        C2Di_Context* ctx = &__C2Di_Contexts[shaderId];

        if (!(ctx.flags & C2DiF_Active))
            continue;

        ctx.flags |= C2DiF_DirtyFade;
        ctx.fadeClr = color;
        atLeastOne = true;
    }

    return atLeastOne;
}

pragma(inline, true)
void C2Di_RotatePoint(ref float[2] point, float rsin, float rcos)
{
    float x = point[0] * rcos - point[1] * rsin;
    float y = point[1] * rcos + point[0] * rsin;
    point[0] = x;
    point[1] = y;
}

//pragma(inline, true)
//void C2Di_SwapUV(float* a, float* b)
//{
//    float[2] temp = [ a[0], a[1] ];
//    a[0] = b[0];
//    a[1] = b[1];
//    b[0] = temp[0];
//    b[1] = temp[1];
//}

void C2Di_CalcQuad(C2Di_Quad* quad, const(C2D_DrawParams)* params)
{
    import std.math : fabs, sin, cos;

    const float w = fabs(params.pos.w);
    const float h = fabs(params.pos.h);

    quad.topLeft[0]  = -params.center.x;
    quad.topLeft[1]  = -params.center.y;
    quad.topRight[0] = -params.center.x+w;
    quad.topRight[1] = -params.center.y;
    quad.botLeft[0]  = -params.center.x;
    quad.botLeft[1]  = -params.center.y+h;
    quad.botRight[0] = -params.center.x+w;
    quad.botRight[1] = -params.center.y+h;

    if (params.angle != 0.0f)
    {
        float rsin = sin(params.angle);
        float rcos = cos(params.angle);
        C2Di_RotatePoint(quad.topLeft,  rsin, rcos);
        C2Di_RotatePoint(quad.topRight, rsin, rcos);
        C2Di_RotatePoint(quad.botLeft,  rsin, rcos);
        C2Di_RotatePoint(quad.botRight, rsin, rcos);
    }

    quad.topLeft[0]  += params.pos.x;
    quad.topLeft[1]  += params.pos.y;
    quad.topRight[0] += params.pos.x;
    quad.topRight[1] += params.pos.y;
    quad.botLeft[0]  += params.pos.x;
    quad.botLeft[1]  += params.pos.y;
    quad.botRight[0] += params.pos.x;
    quad.botRight[1] += params.pos.y;
}

bool C2D_DrawImage(C2D_Image img, const C2D_DrawParams* params, const C2D_ImageTint* tint)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return false;
    if (6 > (ctx.vtxBufSize - ctx.vtxBufPos))
        return false;

    C2Di_SetCircle(false);
    C2Di_SetTex(img.tex);
    C2Di_Update();

    // Calculate positions
    C2Di_Quad quad;
    C2Di_CalcQuad(&quad, params);

    // Calculate texcoords
    float[2] tcTopLeft, tcTopRight, tcBotLeft, tcBotRight;
    Tex3DS_SubTextureTopLeft    (img.subtex, &tcTopLeft[0],  &tcTopLeft[1]);
    Tex3DS_SubTextureTopRight   (img.subtex, &tcTopRight[0], &tcTopRight[1]);
    Tex3DS_SubTextureBottomLeft (img.subtex, &tcBotLeft[0],  &tcBotLeft[1]);
    Tex3DS_SubTextureBottomRight(img.subtex, &tcBotRight[0], &tcBotRight[1]);

    // Perform flip if needed
    if (params.pos.w < 0)
    {
        C2Di_SwapUV(tcTopLeft, tcTopRight);
        C2Di_SwapUV(tcBotLeft, tcBotRight);
    }
    if (params.pos.h < 0)
    {
        C2Di_SwapUV(tcTopLeft, tcBotLeft);
        C2Di_SwapUV(tcTopRight, tcBotRight);
    }

    // Calculate colors
    static const C2D_Tint s_defaultTint = { 0xFF<<24, 0.0f };
    const C2D_Tint* tintTopLeft  = tint ? &tint.corners[C2D_Corner.top_left]     : &s_defaultTint;
    const C2D_Tint* tintTopRight = tint ? &tint.corners[C2D_Corner.top_right]    : &s_defaultTint;
    const C2D_Tint* tintBotLeft  = tint ? &tint.corners[C2D_Corner.bottom_left]  : &s_defaultTint;
    const C2D_Tint* tintBotRight = tint ? &tint.corners[C2D_Corner.bottom_right] : &s_defaultTint;

    // Draw triangles
    C2Di_AppendVtx(quad.topLeft[0],  quad.topLeft[1],  params.depth, tcTopLeft[0],  tcTopLeft[1],  0, tintTopLeft.blend,  tintTopLeft.color);
    C2Di_AppendVtx(quad.botLeft[0],  quad.botLeft[1],  params.depth, tcBotLeft[0],  tcBotLeft[1],  0, tintBotLeft.blend,  tintBotLeft.color);
    C2Di_AppendVtx(quad.botRight[0], quad.botRight[1], params.depth, tcBotRight[0], tcBotRight[1], 0, tintBotRight.blend, tintBotRight.color);

    C2Di_AppendVtx(quad.topLeft[0],  quad.topLeft[1],  params.depth, tcTopLeft[0],  tcTopLeft[1],  0, tintTopLeft.blend,  tintTopLeft.color);
    C2Di_AppendVtx(quad.botRight[0], quad.botRight[1], params.depth, tcBotRight[0], tcBotRight[1], 0, tintBotRight.blend, tintBotRight.color);
    C2Di_AppendVtx(quad.topRight[0], quad.topRight[1], params.depth, tcTopRight[0], tcTopRight[1], 0, tintTopRight.blend, tintTopRight.color);

    return true;
}

/** @brief Draws a plain triangle using the GPU
 *  @param[in] x0 X coordinate of the first vertex of the triangle
 *  @param[in] y0 Y coordinate of the first vertex of the triangle
 *  @param[in] clr0 32-bit RGBA color of the first vertex of the triangle
 *  @param[in] x1 X coordinate of the second vertex of the triangle
 *  @param[in] y1 Y coordinate of the second vertex of the triangle
 *  @param[in] clr1 32-bit RGBA color of the second vertex of the triangle
 *  @param[in] x2 X coordinate of the third vertex of the triangle
 *  @param[in] y2 Y coordinate of the third vertex of the triangle
 *  @param[in] clr2 32-bit RGBA color of the third vertex of the triangle
 *  @param[in] depth Depth value to draw the triangle with
 */
bool C2D_DrawTriangle(float x0, float y0, uint clr0, float x1, float y1, uint clr1, float x2, float y2, uint clr2, float depth)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return false;
    if (3 > (ctx.vtxBufSize - ctx.vtxBufPos))
        return false;

    C2Di_SetCircle(false);
    C2Di_SetSrc(C2DiF_Src_None);
    C2Di_Update();

    C2Di_AppendVtx(x0, y0, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr0);
    C2Di_AppendVtx(x1, y1, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr1);
    C2Di_AppendVtx(x2, y2, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr2);
    return true;
}

/** @brief Draws a plain line using the GPU
 *  @param[in] x0 X coordinate of the first vertex of the line
 *  @param[in] y0 Y coordinate of the first vertex of the line
 *  @param[in] clr0 32-bit RGBA color of the first vertex of the line
 *  @param[in] x1 X coordinate of the second vertex of the line
 *  @param[in] y1 Y coordinate of the second vertex of the line
 *  @param[in] clr1 32-bit RGBA color of the second vertex of the line
 *  @param[in] thickness Thickness, in pixels, of the line
 *  @param[in] depth Depth value to draw the line with
 */
bool C2D_DrawLine(float x0, float y0, uint clr0, float x1, float y1, uint clr1, float thickness, float depth)
{
    import std.math : sqrt;

    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return false;
    if (6 > (ctx.vtxBufSize - ctx.vtxBufPos))
        return false;

    float dx = x1-x0, dy = y1-y0, len = sqrt(dx*dx+dy*dy), th = thickness/2;
    float ux = (-dy/len)*th, uy = (dx/len)*th;
    float px0 = x0-ux, py0 = y0-uy, px1 = x0+ux, py1 = y0+uy, px2 = x1+ux, py2 = y1+uy, px3 = x1-ux, py3 = y1-uy;

    C2Di_SetCircle(false);
    // Not necessary:
    //C2Di_SetSrc(C2DiF_Src_None);
    C2Di_Update();

    C2Di_AppendVtx(px0, py0, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr0);
    C2Di_AppendVtx(px1, py1, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr0);
    C2Di_AppendVtx(px2, py2, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr1);

    C2Di_AppendVtx(px2, py2, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr1);
    C2Di_AppendVtx(px3, py3, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr1);
    C2Di_AppendVtx(px0, py0, depth, -1.0f, -1.0f, 0.0f, 1.0f, clr0);
    return true;
}

/** @brief Draws a plain rectangle using the GPU
 *  @param[in] x X coordinate of the top-left vertex of the rectangle
 *  @param[in] y Y coordinate of the top-left vertex of the rectangle
 *  @param[in] z Z coordinate (depth value) to draw the rectangle with
 *  @param[in] w Width of the rectangle
 *  @param[in] h Height of the rectangle
 *  @param[in] clr0 32-bit RGBA color of the top-left corner of the rectangle
 *  @param[in] clr1 32-bit RGBA color of the top-right corner of the rectangle
 *  @param[in] clr2 32-bit RGBA color of the bottom-left corner of the rectangle
 *  @param[in] clr3 32-bit RGBA color of the bottom-right corner of the rectangle
 */
bool C2D_DrawRectangle(float x, float y, float z, float w, float h, uint clr0, uint clr1, uint clr2, uint clr3)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return false;
    if (6 > (ctx.vtxBufSize - ctx.vtxBufPos))
        return false;

    C2Di_SetCircle(false);
    C2Di_SetSrc(C2DiF_Src_None);
    C2Di_Update();

    C2Di_AppendVtx(x,   y,   z, -1.0f, -1.0f, 0.0f, 1.0f, clr0);
    C2Di_AppendVtx(x,   y+h, z, -1.0f, -1.0f, 0.0f, 1.0f, clr2);
    C2Di_AppendVtx(x+w, y+h, z, -1.0f, -1.0f, 0.0f, 1.0f, clr3);

    C2Di_AppendVtx(x,   y,   z, -1.0f, -1.0f, 0.0f, 1.0f, clr0);
    C2Di_AppendVtx(x+w, y+h, z, -1.0f, -1.0f, 0.0f, 1.0f, clr3);
    C2Di_AppendVtx(x+w, y,   z, -1.0f, -1.0f, 0.0f, 1.0f, clr1);
    return true;
}

/** @brief Draws an ellipse using the GPU
 *  @param[in] x X coordinate of the top-left vertex of the ellipse
 *  @param[in] y Y coordinate of the top-left vertex of the ellipse
 *  @param[in] z Z coordinate (depth value) to draw the ellipse with
 *  @param[in] w Width of the ellipse
 *  @param[in] h Height of the ellipse
 *  @param[in] clr0 32-bit RGBA color of the top-left corner of the ellipse
 *  @param[in] clr1 32-bit RGBA color of the top-right corner of the ellipse
 *  @param[in] clr2 32-bit RGBA color of the bottom-left corner of the ellipse
 *  @param[in] clr3 32-bit RGBA color of the bottom-right corner of the ellipse
 *  @note Switching to and from "circle mode" internally requires an expensive state change. As such, the recommended usage of this feature is to draw all non-circular objects first, then draw all circular objects.
*/
bool C2D_DrawEllipse(float x, float y, float z, float w, float h, uint clr0, uint clr1, uint clr2, uint clr3)
{
    C2Di_Context* ctx = C2Di_GetContext();
    if (!(ctx.flags & C2DiF_Active))
        return false;
    if (6 > (ctx.vtxBufSize - ctx.vtxBufPos))
        return false;

    C2Di_SetCircle(true);
    C2Di_SetSrc(C2DiF_Src_None);
    C2Di_Update();

    C2Di_AppendVtx(x,   y,   z, -1.0f, -1.0f, -1.0f, -1.0f, clr0);
    C2Di_AppendVtx(x,   y+h, z, -1.0f, -1.0f, -1.0f,  1.0f, clr2);
    C2Di_AppendVtx(x+w, y+h, z, -1.0f, -1.0f,  1.0f,  1.0f, clr3);

    C2Di_AppendVtx(x,   y,   z, -1.0f, -1.0f, -1.0f, -1.0f, clr0);
    C2Di_AppendVtx(x+w, y+h, z, -1.0f, -1.0f,  1.0f,  1.0f, clr3);
    C2Di_AppendVtx(x+w, y,   z, -1.0f, -1.0f,  1.0f, -1.0f, clr1);
    return true;
}

void C2Di_AppendVtx(float x, float y, float z, float u, float v, float ptx, float pty, uint color)
{
    C2Di_Context* ctx = C2Di_GetContext();
    C2Di_Vertex* vtx = &ctx.vtxBuf[ctx.vtxBufPos++];
    vtx.x     = x;
    vtx.y     = y;
    vtx.z     = z;
    vtx.u     = u;
    vtx.v     = v;
    vtx.ptX   = ptx;
    vtx.ptY   = pty;
    vtx.color = color;
}

void C2Di_FlushVtxBuf()
{
    C2Di_Context* ctx = C2Di_GetContext();
    size_t len = ctx.vtxBufPos - ctx.vtxBufLastPos;
    if (!len) return;

    GPUPrimitive primitive;

    primitive = GPUPrimitive.geometry_prim;

    C3D_DrawArrays(primitive, ctx.vtxBufLastPos, len);
    ctx.vtxBufLastPos = ctx.vtxBufPos;
}

void C2Di_Update()
{
  C2Di_Context* ctx = C2Di_GetContext();
  uint flags = ctx.flags & C2DiF_DirtyAny;
  if (!flags) return;

  C2Di_FlushVtxBuf();

  if (flags & C2DiF_DirtyProj)
    C3D_FVUnifMtx4x4(GPUShaderType.vertex_shader, ctx.uLoc_projMtx, &ctx.projMtx);
  if (flags & C2DiF_DirtyMdlv)
    C3D_FVUnifMtx4x4(GPUShaderType.vertex_shader, ctx.uLoc_mdlvMtx, &ctx.mdlvMtx);
  if (flags & C2DiF_DirtyTex)
    C3D_TexBind(0, ctx.curTex);
  if (flags & C2DiF_DirtySrc)
    C3D_TexEnvSrc(C3D_GetTexEnv(0), C3DTexEnvMode.both, (ctx.flags & C2DiF_Src_Tex) ? GPUTevSrc.texture0 : GPUTevSrc.constant, GPUTevSrc.primary_color, GPUTevSrc.primary_color);
  if (flags & C2DiF_DirtyFade)
    C3D_TexEnvColor(C3D_GetTexEnv(5), ctx.fadeClr);

  if (flags & C2DiF_DirtyProcTex) {
    if (ctx.flags & C2DiF_ProcTex_Circle) { // flags variable is only for dirty flags
      C3D_ProcTexBind(1, &ctx.ptCircle);
      C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, &ctx.ptCircleLut);

      // Set TexEnv1 to use proctex to generate a circle.
      // This circle then either passes through the alpha (if the fragment
      // is within the circle) or discards the fragment.
      // Unfortunately, blending the vertex color is not possible
      // (because proctex is already being used), therefore it is simply multiplied.
      // texenv1.rgb = texenv0.rgb * vtx.color.rgb;
      // texenv1.a = vtx.color.a * proctex.a;
      C3D_TexEnv* env = C3D_GetTexEnv(1);
      C3D_TexEnvInit(env);
      C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.previous, GPUTevSrc.primary_color, GPUTevSrc.primary_color);
      C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.primary_color, GPUTevSrc.texture3, GPUTevSrc.primary_color);
      C3D_TexEnvFunc(env, C3DTexEnvMode.both, GPUCombineFunc.modulate);
    }
    else {
      C3D_ProcTexBind(1, &ctx.ptBlend);
      C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, &ctx.ptBlendLut);

      // Set texenv1 to blend the output of texenv0 with the primary color
      // texenv1.rgb = mix(texenv0.rgb, vtx.color.rgb, vtx.blend.y);
      // texenv1.a   = texenv0.a * vtx.color.a;
      C3D_TexEnv* env = C3D_GetTexEnv(1);
      C3D_TexEnvInit(env);
      C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.previous, GPUTevSrc.primary_color, GPUTevSrc.texture3);
      C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color, GPUTevOpRGB.one_minus_src_alpha);
      C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.previous, GPUTevSrc.primary_color, GPUTevSrc.primary_color);
      C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.interpolate);
      C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.modulate);
    }
  }

  ctx.flags &= ~C2DiF_DirtyAny;
}