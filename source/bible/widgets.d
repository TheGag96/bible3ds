module bible.widgets;

import bible.util, bible.types, bible.input, bible.audio;
import ctru, citro3d, citro2d;

@nogc: nothrow:

struct UiState {
  int buttonHovered, buttonHoveredLast;
  int buttonHeld, buttonHeldLast;
  int buttonSelected, buttonSelectedLast;
  int selectedFadeTimer, selectedLastFadeTimer;
}


////////
// Buttons
////////

struct Button {
  int id;
  float x = 0, y = 0, z = 0, w = 0, h = 0;
  C2D_Text* text;
  float textW, textH;
}

enum Justification {
  left_justified,
  centered,
  right_justified
}

struct ButtonStyle {
  uint colorText, colorBg, colorBgHeld;
  float margin;
  float textSize = 0;
  Justification justification;
}

enum BUTTON_DEPRESS_OFFSET = 3;

enum OneFrameEvent {
  not_triggered, triggered, already_processed,
}

bool handleButton(in Button btn, in Input input, in ScrollInfo scrollInfo, UiState* uiState, bool withinScrollable = false) {
  bool result = false;

  if (uiState.buttonHeld == -1 && input.down(Key.touch) && input.scrollMethodCur == ScrollMethod.none) {
    float btnRealY = btn.y - withinScrollable * scrollInfo.scrollOffset;
    float touchRealX = input.touchRaw.px, touchRealY = input.touchRaw.py + withinScrollable * SCREEN_HEIGHT;

    if (btnRealY + btn.h > 0 || btnRealY < SCREEN_HEIGHT) {
      if ( touchRealX >= btn.x    && touchRealX <= btn.x    + btn.w &&
           touchRealY >= btnRealY && touchRealY <= btnRealY + btn.h )
      {
        uiState.buttonHeld    = btn.id;
        uiState.buttonHovered = btn.id;
        audioPlaySound(SoundEffect.button_down, 0.25);
      }
    }
  }
  else if (uiState.buttonHeld == btn.id) {
    float btnRealY = btn.y - withinScrollable * scrollInfo.scrollOffset;
    float touchRealX = input.prevTouchRaw.px, touchRealY = input.prevTouchRaw.py + withinScrollable * SCREEN_HEIGHT;

    bool hoveredOverCurrentButton = touchRealX >= btn.x    && touchRealX <= btn.x    + btn.w &&
                                    touchRealY >= btnRealY && touchRealY <= btnRealY + btn.h;

    enum TOUCH_DRAG_THRESHOLD = 8;
    auto touchDiff = input.touchDiff();

    if (hoveredOverCurrentButton) {
      uiState.buttonHovered = btn.id;
    }
    else {
      uiState.buttonHovered = -1;
    }

    if (hoveredOverCurrentButton && !input.held(Key.touch) && input.prevHeld(Key.touch)) {
      //signal to begin transition to reading view
      result = true;
      uiState.buttonHeld    = -1;
      uiState.buttonHovered = -1;
    }
    else if (!input.held(Key.touch) || (withinScrollable && (touchDiff.y >= TOUCH_DRAG_THRESHOLD || !hoveredOverCurrentButton))) {
      uiState.buttonHeld    = -1;
      uiState.buttonHovered = -1;
    }

    if (uiState.buttonHoveredLast == -1 && uiState.buttonHovered == btn.id) {
      audioPlaySound(SoundEffect.button_down, 0.25);
    }
    else if (uiState.buttonHoveredLast == btn.id && uiState.buttonHovered == -1) {
      if (result) {
        audioPlaySound(SoundEffect.button_confirm, 0.5);
      }
      else {
        audioPlaySound(SoundEffect.button_off, 0.25);
      }
    }
  }

  return result;
}

static void renderButton(in Button btn, in UiState uiState, in ButtonStyle style) {
  bool pressed = btn.id == uiState.buttonHeld && btn.id == uiState.buttonHovered;
  float btnRealX = btn.x, btnRealY = btn.y + pressed * BUTTON_DEPRESS_OFFSET;

  C2D_DrawRectSolid(btnRealX, btnRealY, btn.z, btn.w, btn.h, pressed ? style.colorBgHeld : style.colorBg);

  float textX, textY;

  final switch (style.justification) {
    case Justification.left_justified:
      textX = btnRealX+style.margin;
      textY = btnRealY+style.margin;
      break;
    case Justification.centered:
      textX = btnRealX + btn.w/2 - btn.textW/2;
      textY = btnRealY + btn.h/2 - btn.textH/2;
      break;
    case Justification.right_justified:
      break;
  }

  C2D_DrawText(
    btn.text, C2D_WithColor, GFXScreen.top, textX, textY, btn.z + 0.05, style.textSize, style.textSize, style.colorText
  );
}


////////
// 3DS-Styled Striped Background
////////

void drawBackground(GFXScreen screen, C3D_Tex* vignetteTex, C3D_Tex* lineTex, uint colorBg, uint colorStripesDark, uint colorStripesLight) {
  C2Di_Context* ctx = C2Di_GetContext();

  C2D_Flush();

  //basically hijack a bunch of stuff C2D sets up so we can easily reuse the normal shader while still getting to
  //define are own texenv stages
  C2Di_SetTex(lineTex);
  C2Di_Update();
  C3D_TexBind(1, vignetteTex);

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
// Scrolling
////////

struct ScrollInfo {
  float scrollOffset = 0, scrollOffsetLast = 0;
  float limitTop = 0, limitBottom = 0;
  OneFrameEvent startedScrolling;
  OneFrameEvent scrollJustStopped;
  bool pushingAgainstLimit;
  int pushingAgainstTimer;
  enum PUSHING_AGAINST_TIMER_MAX = 10;
}

void handleScroll(ScrollInfo* scrollInfo, Input* input, float newLimitTop, float newLimitBottom) { with (scrollInfo) {
  auto scrollDiff = updateScrollDiff(input);

  respondToScroll(scrollInfo, input, newLimitTop, newLimitBottom, scrollDiff);
}}

void respondToScroll(ScrollInfo* scrollInfo, Input* input, float newLimitTop, float newLimitBottom, ScrollDiff scrollDiff) { with (scrollInfo) {
  enum SCROLL_TICK_DISTANCE = 60;

  limitTop    = newLimitTop;
  limitBottom = newLimitBottom;

  scrollOffsetLast = scrollOffset;

  if (input.scrollMethodCur == ScrollMethod.touch) {
    if (!input.down(Key.touch)) {
      scrollOffset += scrollDiff.y;
    }
  }
  else {
    scrollOffset += scrollDiff.y;
  }

  if (scrollOffset < limitTop) {
    scrollOffset = limitTop;
    input.scrollVel = 0;
  }
  else if (scrollOffset > limitBottom) {
    scrollOffset = limitBottom;
    input.scrollVel = 0;
  }


  ////
  // handle scrolling events
  ////

  pushingAgainstLimit = false;
  if (scrollOffset == limitTop || scrollOffset == limitBottom) {
    if ( scrollJustStopped == OneFrameEvent.not_triggered &&
         scrollOffset != scrollOffsetLast )
    {
      scrollJustStopped = OneFrameEvent.triggered;
    }

    if (input.scrollMethodCur != ScrollMethod.none) {
      pushingAgainstLimit = true;
    }
  }
  else {
    scrollJustStopped = OneFrameEvent.not_triggered;
  }

  if (pushingAgainstLimit) {
    if (pushingAgainstTimer < PUSHING_AGAINST_TIMER_MAX) pushingAgainstTimer++;
  }
  else if (pushingAgainstTimer > 0) {
    pushingAgainstTimer--;
  }

  if ( startedScrolling == OneFrameEvent.not_triggered &&
       input.held(Key.touch) &&
       scrollOffset != scrollOffsetLast )
  {
    startedScrolling = OneFrameEvent.triggered;
  }
  else if (!input.held(Key.touch)) {
    startedScrolling = OneFrameEvent.not_triggered;
  }


  ////
  // play sounds
  ////

  if (startedScrolling == OneFrameEvent.triggered) {
    audioPlaySound(SoundEffect.scroll_tick, 0.1);
    startedScrolling = OneFrameEvent.already_processed;
  }

  if (floor(scrollOffset/SCROLL_TICK_DISTANCE) != floor(scrollOffsetLast/SCROLL_TICK_DISTANCE)) {
    audioPlaySound(SoundEffect.scroll_tick, 0.05);
  }

  if (scrollJustStopped == OneFrameEvent.triggered) {
    audioPlaySound(SoundEffect.scroll_stop, 0.1);
    scrollJustStopped = OneFrameEvent.already_processed;
  }
}}


int handleButtonSelectionAndScroll(UiState* uiState, Button[] buttons, ScrollInfo* scrollInfo, Input* input, float newLimitTop, float newLimitBottom) { with (scrollInfo) {
  bool buttonOnBottomScreen(in Button btn) {
    return btn.y - scrollInfo.scrollOffset >= SCREEN_HEIGHT && btn.y + btn.h - scrollInfo.scrollOffset < 2*SCREEN_HEIGHT;
  }

  if (input.scrollMethodCur == ScrollMethod.none) {
    if (input.held(Key.up | Key.down) && input.scrollVel == 0) {
      input.scrollMethodCur = ScrollMethod.custom;

      if (input.down(Key.up | Key.down)) input.scrollVel = 0;
    }
  }
  else if (input.scrollMethodCur == ScrollMethod.custom) {
    Button* btn = &buttons[uiState.buttonSelected];
    if (!input.held(Key.up | Key.down) && buttonOnBottomScreen(*btn)) {
      input.scrollMethodCur = ScrollMethod.none;
    }
  }

  ScrollDiff scrollDiff;

  if (input.scrollMethodCur == ScrollMethod.custom) {
    bool selectionJustChanged = false;
    if (input.down(Key.down)) {
      if (uiState.buttonSelected < buttons.length-1) {
        audioPlaySound(SoundEffect.button_move, 0.1);
        uiState.buttonSelectedLast = uiState.buttonSelected;
        uiState.buttonSelected++;
        selectionJustChanged = true;
      }
      else {
        audioPlaySound(SoundEffect.scroll_stop, 0.1);
      }
    }
    else if (input.down(Key.up)) {
      if (uiState.buttonSelected > 0) {
        audioPlaySound(SoundEffect.button_move, 0.1);
        uiState.buttonSelectedLast = uiState.buttonSelected;
        uiState.buttonSelected--;
        selectionJustChanged = true;
      }
      else {
        audioPlaySound(SoundEffect.scroll_stop, 0.1);
      }
    }

    Button* btn = &buttons[uiState.buttonSelected];
    if (!buttonOnBottomScreen(*btn)) {
      scrollDiff.y = btn.y - scrollInfo.scrollOffset < SCREEN_HEIGHT ? -5 : 5;

      if (selectionJustChanged) {
        audioPlaySound(SoundEffect.scroll_tick, 0.1);
      }
    }
  }
  else if (input.scrollMethodCur == ScrollMethod.none && input.down(Key.a)) {
    audioPlaySound(SoundEffect.button_confirm, 0.5);
    return uiState.buttonSelected;
  }
  else {
    scrollDiff = updateScrollDiff(input);

    //select new button if the selected one went off-screen
    //@Speed slow but maybe inconsequential
    Button* curBtn = &buttons[uiState.buttonSelected];
    if (!buttonOnBottomScreen(*curBtn)) {
      if (curBtn.y - scrollInfo.scrollOffset < SCREEN_HEIGHT) {
        foreach (ref btn; buttons) { //assuming buttons are sorted here
          if (buttonOnBottomScreen(btn)) {
            uiState.buttonSelected = btn.id;
            break;
          }
        }
      }
      else {
        foreach_reverse (ref btn; buttons) { //assuming buttons are sorted here
          if (buttonOnBottomScreen(btn)) {
            uiState.buttonSelected = btn.id;
            break;
          }
        }
      }
    }
  }

  respondToScroll(scrollInfo, input, newLimitTop, newLimitBottom, scrollDiff);

  return -1;
}}

void renderButtonSelectionIndicator(in UiState uiState, in Button[] buttons, in ScrollInfo scrollInfo, GFXScreen screen, C3D_Tex* tex) { with (scrollInfo) {
  const(Button)* button = &buttons[uiState.buttonSelected];
  C2Di_Context* ctx = C2Di_GetContext();

  void pushQuad(float tlX, float tlY, float brX, float brY, float z, float tlU, float tlV, float brU, float brV) {
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

  C2D_Flush();

  C2D_Prepare(C2DShader.normal);

  C2Di_SetTex(tex);
  C2Di_Update();

  C3D_ProcTexBind(1, null);
  C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, null);

  C3D_TexEnv* env = C3D_GetTexEnv(0);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.texture0, GPUTevSrc.texture0);
  C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.modulate);
  C3D_TexEnvOpAlpha(env, GPUTevOpA.src_alpha, GPUTevOpA.src_r);
  //C3D_TexEnvColor(env, C2D_Color32(0x00, 0xAA, 0x11, 0xFF));
  //C3D_TexEnvColor(env, C2D_Color32(0xFF, 0xFF, 0xFF, 0xFF));

  env = C3D_GetTexEnv(1);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.constant, GPUTevSrc.texture0);
  C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.modulate);
  C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color);
  C3D_TexEnvColor(env, C2D_Color32(0x00, 0xAA, 0x11, 0xFF));

  env = C3D_GetTexEnv(5);
  C3D_TexEnvInit(env);

  enum LINE_WIDTH = 4;

  bool pressed = button.id == uiState.buttonHeld && button.id == uiState.buttonHovered;

  //tlX, tlY, etc. here mean "top-left quad of the selection indicator shape", top-left corner being the origin
  float screenFactor = (screen == GFXScreen.top) * ((SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2);
  float tlX = button.x - LINE_WIDTH + screenFactor;
  float tlY = button.y + pressed * BUTTON_DEPRESS_OFFSET - LINE_WIDTH - floor(scrollInfo.scrollOffset)
              - (screen == GFXScreen.bottom) * SCREEN_HEIGHT;

  float trX = button.x + button.w - (tex.width - LINE_WIDTH) + screenFactor;
  float trY = tlY;

  float blX = tlX;
  float blY = tlY + button.h + LINE_WIDTH - (tex.height - LINE_WIDTH);

  float brX = trX;
  float brY = blY;

  float z = 0.3;

  pushQuad(tlX, tlY, tlX + tex.width, tlY + tex.height, z, 0, 1, 1, 0); // top-left
  pushQuad(trX, tlY, trX + tex.width, tlY + tex.height, z, 1, 1, 0, 0); // top-right
  pushQuad(blX, blY, blX + tex.width, blY + tex.height, z, 0, 0, 1, 1); // bottom-left
  pushQuad(brX, brY, brX + tex.width, brY + tex.height, z, 1, 0, 0, 1); // bottom-right

  pushQuad(tlX + tex.width, tlY,              trX,             tlY + tex.height, z, 15.0f/16.0f, 1,          1, 0); //top
  pushQuad(blX + tex.width, blY,              brX,             blY + tex.height, z, 15.0f/16.0f, 0,          1, 1); //bottom
  pushQuad(tlX,             tlY + tex.height, tlX + tex.width, blY,              z, 0,           1.0f/16.0f, 1, 0); //left
  pushQuad(trX,             trY + tex.height, trX + tex.width, brY,              z, 1,           1.0f/16.0f, 0, 0); //right

  C2D_Flush();

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);
}}

////////
// Scroll Indicator
////////

void renderScrollIndicator(in ScrollInfo scrollInfo, float x, float yMin, float yMax, float viewHeight, bool rightJustified = false) { with (scrollInfo) {
  enum WIDTH = 4;
  enum COLOR_NORMAL  = Vec3(0x20, 0x60, 0xDD)/255;
  enum COLOR_PUSHING = Vec3(0xDD, 0x80, 0x20)/255;

  auto colorNorm = lerp(COLOR_NORMAL, COLOR_PUSHING, min(pushingAgainstTimer, PUSHING_AGAINST_TIMER_MAX)*1.0f/PUSHING_AGAINST_TIMER_MAX);

  float scale = (yMax - yMin) / (limitBottom - limitTop + viewHeight);
  float height = viewHeight * scale;

  //@TODO: gramphics
  C2D_DrawRectSolid(x - rightJustified*WIDTH, yMin + scrollOffset * scale, 0, WIDTH, height, C2D_Color32f(colorNorm.x, colorNorm.y, colorNorm.z, 1));
}}


////////
// Scroll Cache
////////

struct ScrollCache {
  C3D_Tex scrollTex;
  C3D_RenderTarget* scrollTarget;
  float desiredWidth = 0, desiredHeight = 0, texWidth = 0, texHeight = 0;

  bool needsRepaint;
  int u_scrollRenderOffset; // location of uniform from scroll_cache.v.pica
  ubyte curStencilVal;
}

ScrollCache scrollCacheCreate(ushort width, ushort height) {
  import std.math.algebraic : nextPow2;

  ScrollCache result;

  with (result) {
    //round sizes to power of two if needed
    desiredWidth  = width;
    desiredHeight = height;
    width         = (width  & (width  - 1)) ? nextPow2(width)  : width;
    height        = (height & (height - 1)) ? nextPow2(height) : height;
    texWidth      = width;
    texHeight     = height;

    C3D_TexInitVRAM(&scrollTex, width, height, GPUTexColor.rgba8);
    C3D_TexSetWrap(&scrollTex, GPUTextureWrapParam.repeat, GPUTextureWrapParam.repeat);
    scrollTarget = C3D_RenderTargetCreateFromTex(&scrollTex, GPUTexFace.texface_2d, 0, C3D_DEPTHTYPE(GPUDepthBuf.depth24_stencil8));
    u_scrollRenderOffset = C2D_ShaderGetUniformLocation(C2DShader.scroll_cache, GPUShaderType.vertex_shader, "scrollRenderOffset");
  }

  return result;
}

alias renderCallback(T) = void function(T* userData, float from, float to);

void scrollCacheBeginFrame(ScrollCache* scrollCache) { with (scrollCache) {
  C2D_Flush();
  C3D_RenderTargetClear(scrollTarget, C3DClearBits.clear_depth, 0, 0);
  C2D_SceneBegin(scrollTarget);
  C2D_Prepare(C2DShader.scroll_cache);
  curStencilVal = 1;
}}

void scrollCacheEndFrame(ScrollCache* scrollCache) { with (scrollCache) {
  C2D_Prepare(C2DShader.normal);
  C3D_StencilTest(false, GPUTestFunc.always, 0, 0, 0);
}}

pragma(inline, true)
void scrollCacheRenderScrollUpdate(T)(
  ScrollCache* scrollCache,
  in ScrollInfo scrollInfo,
  void function(T* userData, float from, float to) @nogc nothrow render, T* userData,
  uint clearColor = 0,
) {
  _scrollCacheRenderScrollUpdateImpl(
    scrollCache,
    scrollInfo,
    cast(void function(void* userData, float from, float to) @nogc nothrow) render, userData,
    clearColor,
  );
}

private void _scrollCacheRenderScrollUpdateImpl(
  ScrollCache* scrollCache,
  in ScrollInfo scrollInfo,
  void function(void* userData, float from, float to) @nogc nothrow render, void* userData,
  uint clearColor = 0,
) { with (scrollCache) with (scrollInfo) {
  float drawStart, drawEnd;

  float scroll     = floor(scrollOffset),
        scrollLast = floor(scrollOffsetLast);

  if (needsRepaint) {
    needsRepaint = false;
    drawStart = scroll;
    drawEnd   = scroll+texHeight;
  }
  else {
    if (scrollOffset == scrollOffsetLast) return;

    drawStart  = (scrollLast < scroll) ? scrollLast + texHeight : scroll;
    drawEnd    = (scrollLast < scroll) ? scroll     + texHeight : scrollLast;
  }

  _scrollCacheRenderRegionImpl(
    scrollCache,
    drawStart, drawEnd,
    render, userData,
    clearColor,
  );
}}

pragma(inline, true)
void scrollCacheRenderRegion(T)(
  ScrollCache* scrollCache,
  float from, float to,
  void function(T* userData, float from, float to) @nogc nothrow render, T* userData,
  uint clearColor = 0,
) {
  _scrollCacheRenderRegionImpl(
    scrollCache,
    from, to,
    cast(void function(void* userData, float from, float to) @nogc nothrow) render, userData,
    clearColor,
  );
}

private void _scrollCacheRenderRegionImpl(
  ScrollCache* scrollCache,
  float from, float to,
  void function(void* userData, float from, float to) @nogc nothrow render, void* userData,
  uint clearColor = 0,
) { with (scrollCache) {
  float drawStart  = from;
  float drawEnd    = to;
  float drawOffset = -(drawStart - wrap(drawStart, texHeight));
  float drawHeight = drawEnd-drawStart;

  float drawStartOnTexture = wrap(drawStart, texHeight);
  float drawEndOnTexture   = drawStartOnTexture + drawHeight;
  float drawOffTexture     = max(drawEndOnTexture - texHeight, 0);

  C3D_FVUnifSet(GPUShaderType.vertex_shader, u_scrollRenderOffset, 0, drawOffset, 0, 0);

  //carve out stencil and clear piece of screen simulatenously
  C3D_StencilTest(true, GPUTestFunc.always, curStencilVal, 0xFF, 0xFF);
  C3D_StencilOp(GPUStencilOp.replace, GPUStencilOp.replace, GPUStencilOp.replace);
  C3D_AlphaBlend(GPUBlendEquation.add, GPUBlendEquation.add, GPUBlendFactor.src_alpha, GPUBlendFactor.zero, GPUBlendFactor.src_alpha, GPUBlendFactor.zero);

  C2D_DrawRectSolid(0, drawStart, 0, desiredWidth, drawHeight, clearColor);
  C2D_Flush();

  //use callback to draw newly scrolled region
  C3D_StencilTest(true, GPUTestFunc.equal, curStencilVal, 0xFF, 0xFF);
  C3D_StencilOp(GPUStencilOp.keep, GPUStencilOp.keep, GPUStencilOp.keep);
  C3D_AlphaBlend(GPUBlendEquation.add, GPUBlendEquation.add, GPUBlendFactor.src_alpha, GPUBlendFactor.one_minus_src_alpha, GPUBlendFactor.src_alpha, GPUBlendFactor.one_minus_src_alpha);

  render(userData, drawStart, drawEnd - drawOffTexture);
  C2D_Flush();
  curStencilVal++;

  //draw from top if we draw past the bottom. use a different stencil to prevent overwriting stuff we just drew
  if (drawEndOnTexture >= texHeight) {
    C3D_FVUnifSet(GPUShaderType.vertex_shader, u_scrollRenderOffset, 0, drawOffset - texHeight, 0, 0);
    C3D_StencilTest(true, GPUTestFunc.always, curStencilVal, 0xFF, 0xFF);
    C3D_StencilOp(GPUStencilOp.replace, GPUStencilOp.replace, GPUStencilOp.replace);
    C3D_AlphaBlend(GPUBlendEquation.add, GPUBlendEquation.add, GPUBlendFactor.src_alpha, GPUBlendFactor.zero, GPUBlendFactor.src_alpha, GPUBlendFactor.zero);
    C2D_DrawRectSolid(0, drawStart, 0, desiredWidth, drawHeight, clearColor);
    C2D_Flush();

    C3D_StencilTest(true, GPUTestFunc.equal, curStencilVal, 0xFF, 0xFF);
    C3D_StencilOp(GPUStencilOp.keep, GPUStencilOp.keep, GPUStencilOp.keep);
    C3D_AlphaBlend(GPUBlendEquation.add, GPUBlendEquation.add, GPUBlendFactor.src_alpha, GPUBlendFactor.one_minus_src_alpha, GPUBlendFactor.src_alpha, GPUBlendFactor.one_minus_src_alpha);
    render(userData, drawEnd - drawOffTexture, drawEnd);
    C2D_Flush();

    curStencilVal++;
  }
}}

Tex3DS_SubTexture scrollCacheGetUvs(
  in ScrollCache scrollCache,
  float width, float height, float yOffset, float scroll
) { with (scrollCache) {
  Tex3DS_SubTexture result = {
    width  : cast(ushort) width,
    height : cast(ushort) height,
    left   : 0,
    right  : width/texWidth,
    top    : 1.0f - yOffset         /texHeight - floor(wrap(scroll, texHeight))/texHeight,
    bottom : 1.0f - (yOffset+height)/texHeight - floor(wrap(scroll, texHeight))/texHeight,
  };
  return result;
}}
