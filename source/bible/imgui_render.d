module bible.imgui_render;

import bible.imgui, bible.util;
import ctru, citro2d, citro3d;
import std.math;

@nogc: nothrow:

enum BUTTON_DEPRESS_NORMAL = 3;
enum BUTTON_DEPRESS_BOTTOM = 1;

void renderNormalButton(const(UiBox)* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 screenPos) {
  bool pressed = box.activeT == 1;

  auto rect = box.rect + Vec2(0, pressed * BUTTON_DEPRESS_NORMAL) - screenPos;
  rect.left = floor(rect.left); rect.top = floor(rect.top); rect.right = floor(rect.right); rect.bottom = floor(rect.bottom);

  float textX, textY;
  final switch (box.justification) {
    case Justification.min:
      textX = rect.left+box.style.margin;
      textY = rect.top+box.style.margin;
      break;
    case Justification.center:
      textX = (rect.left + rect.right)/2 - box.text.width/2;
      textY = (rect.top + rect.bottom)/2 - box.textHeight/2;
      break;
    case Justification.max:
      break;
  }

  C2Di_Context* ctx = C2Di_GetContext();

  auto tex = &gUiAssets.buttonTex;

  C2Di_SetTex(tex);
  C2Di_Update();

  enum CORNER_WIDTH = 6.0f, CORNER_HEIGHT = 4.0f;

  float tlX = rect.left;
  float tlY = rect.top;

  float trX = rect.right - CORNER_WIDTH;
  float trY = tlY;

  float blX = tlX;
  float blY = rect.bottom - CORNER_HEIGHT;

  float brX = trX;
  float brY = blY;

  float z = 0;

  pushQuad(tlX, tlY, tlX + CORNER_WIDTH, tlY + CORNER_HEIGHT, z, 0, 1, (CORNER_WIDTH/tex.width), 1-CORNER_HEIGHT/tex.height); // top-left
  pushQuad(trX, tlY, trX + CORNER_WIDTH, tlY + CORNER_HEIGHT, z, (CORNER_WIDTH/tex.width), 1, 0, 1-CORNER_HEIGHT/tex.height); // top-right
  pushQuad(blX, blY, blX + CORNER_WIDTH, blY + CORNER_HEIGHT, z, 0, (16.0f+CORNER_HEIGHT)/tex.height, (CORNER_WIDTH/tex.width), 16.0f/tex.height); // bottom-left
  pushQuad(brX, brY, brX + CORNER_WIDTH, brY + CORNER_HEIGHT, z, (CORNER_WIDTH/tex.width), (16.0f+CORNER_HEIGHT)/tex.height, 0, 16.0f/tex.height); // bottom-right

  pushQuad(tlX + CORNER_WIDTH, tlY,                 trX,                tlY + CORNER_HEIGHT, z, (CORNER_WIDTH/tex.width), 1,          1, 1-CORNER_HEIGHT/tex.height); //top
  pushQuad(blX + CORNER_WIDTH, blY,                 brX,                blY + CORNER_HEIGHT, z, (CORNER_WIDTH/tex.width), (16.0f+CORNER_HEIGHT)/tex.height,          1, 16.0f/tex.height); //bottom
  pushQuad(tlX,                tlY + CORNER_HEIGHT, tlX + CORNER_WIDTH, blY,                 z, 0,           1-CORNER_HEIGHT/tex.height, (CORNER_WIDTH/tex.width), (16.0f+CORNER_HEIGHT)/tex.height); //left
  pushQuad(trX,                trY + CORNER_HEIGHT, trX + CORNER_WIDTH, brY,                 z, (CORNER_WIDTH/tex.width),           1-CORNER_HEIGHT/tex.height, 0, (16.0f+CORNER_HEIGHT)/tex.height); //right

  pushQuad(tlX + CORNER_WIDTH, tlY + CORNER_HEIGHT, brX,                brY,                 z, (CORNER_WIDTH/tex.width), 1-CORNER_HEIGHT/tex.height,          1, (16.0f+CORNER_HEIGHT)/tex.height); //center
  C2D_Flush();

  C2D_DrawText(
    &box.text, C2D_WithColor, GFXScreen.top, textX, textY, z, box.style.textSize, box.style.textSize, box.style.colorText
  );

  if (box.parent && (box.parent.flags & UiFlags.select_children) && (box.flags & UiFlags.selectable) && box.hotT > 0) {
    renderButtonSelectionIndicator(box, rect, screen, side, _3DEnabled, slider3DState, screenPos);
  }
}

void renderBottomButton(const(UiBox)* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 screenPos) {
  bool pressed = box.activeT == 1;

  auto rect = box.rect + Vec2(0, pressed * BUTTON_DEPRESS_BOTTOM) - screenPos;
  rect.left = floor(rect.left); rect.top = floor(rect.top); rect.right = floor(rect.right); rect.bottom = floor(rect.bottom);

  float textX, textY;
  final switch (box.justification) {
    case Justification.min:
      textX = rect.left+box.style.margin;
      textY = rect.top+box.style.margin;
      break;
    case Justification.center:
      textX = (rect.left + rect.right)/2 - box.text.width/2;
      textY = (rect.top + rect.bottom)/2 - box.textHeight/2;
      break;
    case Justification.max:
      break;
  }

  uint topColor, bottomColor, baseColor, textColor, bevelTexColor, lineColor;

  float z = 0;

  //textColor     = box.style.colorText;
  //bevelTexColor = 0xFFFFFFFF;
  bevelTexColor = box.style.colorText;
  textColor     = 0xFFFFFFFF;

  /* //health and safety colors
  if (pressed) {
    topColor      = C2D_Color32(0x6a, 0x6a, 0x6e, 255);
    bottomColor   = C2D_Color32(0xbe, 0xbe, 0xc2, 255);
    baseColor     = C2D_Color32(0x8d, 0x8d, 0x96, 255);
    lineColor     = C2D_Color32(0x81, 0x81, 0x82, 255);
    uint tmp = textColor;
    textColor = bevelTexColor;
    bevelTexColor = tmp;
  }
  else {
    topColor      = C2D_Color32(244, 244, 240, 255);
    bottomColor   = C2D_Color32(199, 199, 195, 255);
    baseColor     = C2D_Color32(228, 228, 220, 255);
    lineColor     = C2D_Color32(158, 158, 157, 255);
  }*/

  if (pressed) {
    topColor      = C2D_Color32(0x6e, 0x6e, 0x6a, 255);
    bottomColor   = C2D_Color32(0xc0, 0xc0, 0xbc, 255);
    baseColor     = C2D_Color32(0xa5, 0xa5, 0x9e, 255);
    lineColor     = C2D_Color32(0x7b, 0x7b, 0x7b, 255);
    uint tmp = textColor;
    textColor = bevelTexColor;
    bevelTexColor = tmp;
  }
  else {
    topColor      = C2D_Color32(0xb6, 0xb6, 0xba, 255);
    bottomColor   = C2D_Color32(0x48, 0x48, 0x4c, 255);
    baseColor     = C2D_Color32(0x66, 0x66, 0x6e, 255);
    lineColor     = C2D_Color32(0x8b, 0x8b, 0x8c, 255);
  }

  // light fade above bottom button
  {
    auto tex = &gUiAssets.bottomButtonAboveFadeTex;

    C2Di_SetTex(tex);
    C2Di_Update();

    // multiply the alpha of the texture with a constant color

    C3D_TexEnv* env = C3D_GetTexEnv(0);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.constant);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.replace);
    C3D_TexEnvColor(env, C2D_Color32(0xf2, 0xf2, 0xf7, 128));

    C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.texture0);
    C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.replace);

    env = C3D_GetTexEnv(5);
    C3D_TexEnvInit(env);

    pushQuad(rect.left, rect.top - tex.height + 1, rect.right, rect.top + 1, z, 0, 1, 1, 0);

    C2D_Flush();
  }

  // main button area
  {
    auto tex = &gUiAssets.bottomButtonTex;

    C2Di_SetTex(tex);
    C2Di_Update();

    // use the value of the texture to interpolate between a top and bottom color.
    // then, use the alpha of the texture to interpolate between THAT calculated color and the button's middle/base color.

    C3D_TexEnv* env = C3D_GetTexEnv(0);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.constant);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.replace);
    C3D_TexEnvColor(env, topColor);

    env = C3D_GetTexEnv(1);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.previous, GPUTevSrc.constant, GPUTevSrc.texture0);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.interpolate);
    C3D_TexEnvColor(env, bottomColor);

    C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.constant);
    C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.replace);

    env = C3D_GetTexEnv(2);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.previous, GPUTevSrc.constant, GPUTevSrc.texture0);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.interpolate);
    C3D_TexEnvColor(env, baseColor);
    C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color, GPUTevOpRGB.src_alpha);

    env = C3D_GetTexEnv(5);
    C3D_TexEnvInit(env);

    pushQuad(rect.left, rect.top, rect.right, rect.bottom, z, 0, 1, 1, 0);

    C2D_Flush();

    //Cleanup, resetting things to how C2D normally expects
    C2D_Prepare(C2DShader.normal, true);

    env = C3D_GetTexEnv(2);
    C3D_TexEnvInit(env);
  }

  C2D_DrawRectSolid(rect.left, rect.top, z, rect.right-rect.left, 1, lineColor);

  int textBevelOffset = pressed ? 1 : -1;

  C2D_DrawText(
    &box.text, C2D_WithColor, GFXScreen.top, textX, textY + textBevelOffset, z, box.style.textSize, box.style.textSize, bevelTexColor
  );

  C2D_DrawText(
    &box.text, C2D_WithColor, GFXScreen.top, textX, textY, z, box.style.textSize, box.style.textSize, textColor
  );
}

void renderButtonSelectionIndicator(const(UiBox)* box, in Rectangle rect, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 screenPos) {
  C2Di_Context* ctx = C2Di_GetContext();

  C2D_Prepare(C2DShader.normal);

  auto tex = &gUiAssets.selectorTex;

  C2Di_SetTex(tex);
  C2Di_Update();

  C3D_ProcTexBind(1, null);
  C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, null);

  //consider texture's value to count as alpha as well as the texture's actual alpha
  C3D_TexEnv* env = C3D_GetTexEnv(0);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.texture0, GPUTevSrc.texture0);
  C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.modulate);
  C3D_TexEnvOpAlpha(env, GPUTevOpA.src_alpha, GPUTevOpA.src_r);

  //used to apply dynamic color
  env = C3D_GetTexEnv(1);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.constant, GPUTevSrc.texture0);
  C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.modulate);
  C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color);
  C3D_TexEnvColor(env, C2D_Color32(0x00, 0xAA, 0x11, 0xFF));

  //used to apply dynamic fade alpha
  env = C3D_GetTexEnv(2);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.previous, GPUTevSrc.constant);
  C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.modulate);
  C3D_TexEnvOpAlpha(env, GPUTevOpA.src_alpha, GPUTevOpA.src_alpha);

  env = C3D_GetTexEnv(5);
  C3D_TexEnvInit(env);

  enum LINE_WIDTH = 4;

  ubyte alpha  = cast(ubyte) round(0xFF*box.hotT);

  env = C3D_GetTexEnv(2); //must be done to mark the texenv as dirty! without this, each indicator will have one alpha
  C3D_TexEnvColor(env, C2D_Color32(0xFF, 0xFF, 0xFF, alpha));

  //tlX, tlY, etc. here mean "top-left quad of the selection indicator shape", top-left corner being the origin
  float tlX = rect.left - LINE_WIDTH;
  float tlY = rect.top  - LINE_WIDTH;

  float trX = rect.right - (tex.width - LINE_WIDTH);
  float trY = tlY;

  float blX = tlX;
  float blY = rect.bottom - (tex.height - LINE_WIDTH);

  float brX = trX;
  float brY = blY;

  float z = 0; // 0.3; @TODO: Do we need to use different z-values here?

  pushQuad(tlX, tlY, tlX + tex.width, tlY + tex.height, z, 0, 1, 1, 0); // top-left
  pushQuad(trX, tlY, trX + tex.width, tlY + tex.height, z, 1, 1, 0, 0); // top-right
  pushQuad(blX, blY, blX + tex.width, blY + tex.height, z, 0, 0, 1, 1); // bottom-left
  pushQuad(brX, brY, brX + tex.width, brY + tex.height, z, 1, 0, 0, 1); // bottom-right

  pushQuad(tlX + tex.width, tlY,              trX,             tlY + tex.height, z, 15.0f/16.0f, 1,          1, 0); //top
  pushQuad(blX + tex.width, blY,              brX,             blY + tex.height, z, 15.0f/16.0f, 0,          1, 1); //bottom
  pushQuad(tlX,             tlY + tex.height, tlX + tex.width, blY,              z, 0,           1.0f/16.0f, 1, 0); //left
  pushQuad(trX,             trY + tex.height, trX + tex.width, brY,              z, 1,           1.0f/16.0f, 0, 0); //right

  C2D_Flush(); //need this if alpha value changes

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);

  env = C3D_GetTexEnv(2);
  C3D_TexEnvInit(env);
}


struct UiAssets {
  C3D_Tex vignetteTex, lineTex; //@TODO: Move somewhere probably
  C3D_Tex selectorTex;
  C3D_Tex buttonTex, bottomButtonTex, bottomButtonAboveFadeTex;
  C3D_Tex indicatorTex;
}

UiAssets gUiAssets;

void loadUiAssets() {
  with (gUiAssets) {
    if (!loadTextureFromFile(&vignetteTex, null, "romfs:/gfx/vignette.t3x"))
      svcBreak(UserBreakType.panic);
    if (!loadTextureFromFile(&lineTex, null, "romfs:/gfx/line.t3x"))
      svcBreak(UserBreakType.panic);
    if (!loadTextureFromFile(&selectorTex, null, "romfs:/gfx/selector.t3x"))
      svcBreak(UserBreakType.panic);
    if (!loadTextureFromFile(&buttonTex, null, "romfs:/gfx/button.t3x"))
      svcBreak(UserBreakType.panic);
    if (!loadTextureFromFile(&bottomButtonTex, null, "romfs:/gfx/bottom_button.t3x"))
      svcBreak(UserBreakType.panic);
    if (!loadTextureFromFile(&bottomButtonAboveFadeTex, null, "romfs:/gfx/bottom_button_above_fade.t3x"))
      svcBreak(UserBreakType.panic);
    if (!loadTextureFromFile(&indicatorTex, null, "romfs:/gfx/scroll_indicator.t3x"))
      svcBreak(UserBreakType.panic);

    //set some special properties of background textures
    C3D_TexSetFilter(&vignetteTex, GPUTextureFilterParam.linear, GPUTextureFilterParam.linear);
    C3D_TexSetFilter(&lineTex, GPUTextureFilterParam.linear, GPUTextureFilterParam.linear);
    C3D_TexSetWrap(&vignetteTex, GPUTextureWrapParam.mirrored_repeat, GPUTextureWrapParam.mirrored_repeat);
    C3D_TexSetWrap(&lineTex, GPUTextureWrapParam.repeat, GPUTextureWrapParam.repeat);
    C3D_TexSetFilter(&bottomButtonTex, GPUTextureFilterParam.linear, GPUTextureFilterParam.linear);
  }
}

void pushQuad(float tlX, float tlY, float brX, float brY, float z, float tlU, float tlV, float brU, float brV) {
  C2Di_Context* ctx = C2Di_GetContext();

  C2Di_Vertex[6] vertexList = [
    // Top-left quad
    // First triangle
    { tlX, tlY, z,   tlU,  tlV,  0.0f,  0.0f,  0xFF<<24 },
    { brX, tlY, z,   brU,  tlV,  0.0f,  0.0f,  0xFF<<24 },
    { brX, brY, z,   brU,  brV,  0.0f,  0.0f,  0xFF<<24 },
    // Second triangle
    { brX, brY, z,   brU,  brV,  0.0f,  0.0f,  0xFF<<24 },
    { tlX, brY, z,   tlU,  brV,  0.0f,  0.0f,  0xFF<<24 },
    { tlX, tlY, z,   tlU,  tlV,  0.0f,  0.0f,  0xFF<<24 },
  ];

  ctx.vtxBuf[ctx.vtxBufPos..ctx.vtxBufPos+vertexList.length] = vertexList[];
  ctx.vtxBufPos += vertexList.length;
}

////////
// 3DS-Styled Striped Background
////////

void drawBackground(GFXScreen screen, uint colorBg, uint colorStripesDark, uint colorStripesLight) {
  C2Di_Context* ctx = C2Di_GetContext();

  C2D_Flush();

  //basically hijack a bunch of stuff C2D sets up so we can easily reuse the normal shader while still getting to
  //define are own texenv stages
  C2Di_SetTex(&gUiAssets.lineTex);
  C2Di_Update();
  C3D_TexBind(1, &gUiAssets.vignetteTex);

  C3D_ProcTexBind(1, null);
  C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, null);

  auto thisScreenWidth = screenWidth(screen);

  C2Di_Vertex[6] vertex_list = [
    // First face (PZ)
    // First triangle
    { 0.0f,            0.0f,          0.0f,   0.0f,  0.0f,  0.0f, -1.0f,  0xFF<<24 },
    { thisScreenWidth, 0.0f,          0.0f,  28.0f,  0.0f,  2.0f, -1.0f,  0xFF<<24 },
    { thisScreenWidth, SCREEN_HEIGHT, 0.0f,  28.0f, 28.0f,  2.0f,  1.0f,  0xFF<<24 },
    // Second triangle
    { thisScreenWidth, SCREEN_HEIGHT, 0.0f,  28.0f, 28.0f,  2.0f,  1.0f,  0xFF<<24 },
    { 0.0f,            SCREEN_HEIGHT, 0.0f,   0.0f, 28.0f,  0.0f,  1.0f,  0xFF<<24 },
    { 0.0f,            0.0f,          0.0f,   0.0f,  0.0f,  0.0f, -1.0f,  0xFF<<24 },
  ];

  static if (true) {
    //overlay the vignette texture on top of the stripes/lines, using the line texture and some texenv stages to
    //interpolate between two colors
    C3D_TexEnv* env = C3D_GetTexEnv(0);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.both, GPUTevSrc.constant);
    C3D_TexEnvFunc(env, C3DTexEnvMode.both, GPUCombineFunc.replace);
    C3D_TexEnvColor(env, colorStripesDark);
    env = C3D_GetTexEnv(1);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.both, GPUTevSrc.previous, GPUTevSrc.constant, GPUTevSrc.texture0);
    C3D_TexEnvFunc(env, C3DTexEnvMode.both, GPUCombineFunc.interpolate);
    C3D_TexEnvColor(env, colorStripesLight);

    env = C3D_GetTexEnv(2);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.constant, GPUTevSrc.previous, GPUTevSrc.texture1);
    C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color, GPUTevOpRGB.src_alpha);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.interpolate);
    C3D_TexEnvColor(env, colorBg);
  }
  else {
    //alternate method that uses the vignette texture to affect the alpha of the stripes
    C3D_TexEnv* env = C3D_GetTexEnv(0);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.constant);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.replace);
    C3D_TexEnvColor(env, colorStripesLight);
    env = C3D_GetTexEnv(1);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.previous, GPUTevSrc.constant, GPUTevSrc.texture0);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.interpolate);
    C3D_TexEnvColor(env, colorStripesDark);

    C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.constant, GPUTevSrc.texture1);
    C3D_TexEnvOpAlpha(env, GPUTevOpA.src_alpha, GPUTevOpA.one_minus_src_alpha, GPUTevOpA.src_alpha);
    C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.modulate);
  }

  env = C3D_GetTexEnv(5);
  C3D_TexEnvInit(env);

  ctx.vtxBuf[ctx.vtxBufPos..ctx.vtxBufPos+vertex_list.length] = vertex_list[];
  ctx.vtxBufPos += vertex_list.length;

  C2D_Flush();

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);

  env = C3D_GetTexEnv(2);
  C3D_TexEnvInit(env);
}

////////
// Scroll Indicator
////////

void renderScrollIndicator(const(UiBox)* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 screenPos) {
  C2Di_Context* ctx = C2Di_GetContext();

  void pushQuadUvSwap(float tlX, float tlY, float brX, float brY, float z, float tlU, float tlV, float brU, float brV) {
    C2Di_Vertex[6] vertexList = [
      // Top-left quad
      // First triangle
      { tlX, tlY, z,   tlV,  tlU,  0.0f,  0.0f,  0xFF<<24 },
      { brX, tlY, z,   tlV,  brU,  0.0f,  0.0f,  0xFF<<24 },
      { brX, brY, z,   brV,  brU,  0.0f,  0.0f,  0xFF<<24 },
      // Second triangle
      { brX, brY, z,   brV,  brU,  0.0f,  0.0f,  0xFF<<24 },
      { tlX, brY, z,   brV,  tlU,  0.0f,  0.0f,  0xFF<<24 },
      { tlX, tlY, z,   tlV,  tlU,  0.0f,  0.0f,  0xFF<<24 },
    ];

    ctx.vtxBuf[ctx.vtxBufPos..ctx.vtxBufPos+vertexList.length] = vertexList[];
    ctx.vtxBufPos += vertexList.length;
  }

  enum COLOR_NORMAL          = Vec3(0x66, 0xAD, 0xC1)/255;
  enum COLOR_NORMAL_OUTLINE  = Vec3(0xE1, 0xED, 0xF1)/255;
  enum COLOR_PUSHING         = Vec3(0xDD, 0x80, 0x20)/255;
  enum COLOR_PUSHING_OUTLINE = Vec3(0xE3, 0xAE, 0x78)/255;

  auto rect = box.rect - screenPos;
  float viewHeight = box.related.computedSize[Axis2.y];

  auto colorLerp        = lerp(COLOR_NORMAL,         COLOR_PUSHING,         box.hotT);
  auto colorOutlineLerp = lerp(COLOR_NORMAL_OUTLINE, COLOR_PUSHING_OUTLINE, box.hotT);

  auto colorC2d        = C2D_Color32f(colorLerp.x,        colorLerp.y,        colorLerp.z,        0);
  auto colorOutlineC2d = C2D_Color32f(colorOutlineLerp.x, colorOutlineLerp.y, colorOutlineLerp.z, 1);

  // @TODO: Only vertical scrolling indicators are supported right now.

  float scale = (rect.bottom - rect.top) / (box.related.scrollLimitMax - box.related.scrollLimitMin + viewHeight);
  float height = viewHeight * scale;

  C2D_Prepare(C2DShader.normal);

  auto indicatorTex = &gUiAssets.indicatorTex;

  C2Di_SetTex(indicatorTex);
  C2Di_Update();

  C3D_ProcTexBind(1, null);
  C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, null);

  //dynamically color the indicator. pure white on the indicator texture is the outline, while pure black is the filling
  //use two texenvs to set up two colors and then use the texture values to interpolate between the two
  C3D_TexEnv* env = C3D_GetTexEnv(0);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.both, GPUTevSrc.constant);
  C3D_TexEnvFunc(env, C3DTexEnvMode.both, GPUCombineFunc.replace);
  C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color);
  C3D_TexEnvOpAlpha(env, GPUTevOpA.src_alpha);
  C3D_TexEnvColor(env, colorOutlineC2d);

  env = C3D_GetTexEnv(1);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.both, GPUTevSrc.previous, GPUTevSrc.constant, GPUTevSrc.texture0);
  C3D_TexEnvFunc(env, C3DTexEnvMode.both, GPUCombineFunc.interpolate);
  C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color);
  C3D_TexEnvOpAlpha(env, GPUTevOpA.src_alpha, GPUTevOpA.src_alpha, GPUTevOpA.src_alpha);
  C3D_TexEnvColor(env, colorC2d);

  env = C3D_GetTexEnv(5);
  C3D_TexEnvInit(env);

  bool rightJustified = box.justification == Justification.max;
  float realX = round(rect.left - rightJustified*indicatorTex.width), realY = round(rect.top + box.related.scrollOffset * scale);
  pushQuadUvSwap(realX, realY,                                realX + indicatorTex.width, realY + indicatorTex.width,           0,  0, 0,   1, 1);
  pushQuadUvSwap(realX, realY + indicatorTex.height,          realX + indicatorTex.width, realY + height - indicatorTex.height, 0,  0, 0.5, 1, 1);
  pushQuadUvSwap(realX, realY + height - indicatorTex.height, realX + indicatorTex.width, realY + height,                       0,  1, 1,   0, 0);

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);
}