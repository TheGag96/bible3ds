module bible.widgets;

import bible.util, bible.types, bible.input, bible.audio;
import ctru, citro3d, citro2d;

@nogc: nothrow:

struct UiState {
  int buttonHovered, buttonHoveredLast;
  int buttonHeld, buttonHeldLast;
  int buttonSelected, buttonSelectedLast;
  float selectedFadeTimer = 0, selectedLastFadeTimer = 0;
}

////////
// Internal state
////////

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

////////
// Buttons
////////

struct Button {
  int id;
  float x = 0, y = 0, z = 0, w = 0, h = 0;
  C2D_Text* text;
  float textW, textH;
  const(ButtonStyle)* style;
}

enum Justification {
  left_justified,
  centered,
  right_justified
}

enum ButtonType { normal, bottom }

struct ButtonStyle {
  ButtonType type;
  uint colorText, colorBg, colorBgHeld;
  float margin;
  float textSize = 0;
  Justification justification;
  SoundEffect pressedSound = SoundEffect.button_confirm;
  float pressedSoundVol = 0.5;
}

static immutable int[ButtonType.max+1] BUTTON_DEPRESS_OFFSETS = [
  ButtonType.normal : 3,
  ButtonType.bottom : 1,
];

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
        uiState.buttonHeld         = btn.id;
        uiState.buttonHovered      = btn.id;
        uiState.buttonSelectedLast = uiState.buttonSelected;
        uiState.buttonSelected     = btn.id;
        uiState.selectedLastFadeTimer = 1.0f;
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
        audioPlaySound(btn.style.pressedSound, btn.style.pressedSoundVol);
      }
      else {
        audioPlaySound(SoundEffect.button_off, 0.25);
      }
    }
  }

  return result;
}

void renderButton(in Button btn, in UiState uiState) {
  bool pressed = btn.id == uiState.buttonHeld && btn.id == uiState.buttonHovered;
  float btnRealX = btn.x, btnRealY = btn.y + pressed * BUTTON_DEPRESS_OFFSETS[btn.style.type];
  float textX, textY;

  final switch (btn.style.justification) {
    case Justification.left_justified:
      textX = btnRealX+btn.style.margin;
      textY = btnRealY+btn.style.margin;
      break;
    case Justification.centered:
      textX = btnRealX + btn.w/2 - btn.textW/2;
      textY = btnRealY + btn.h/2 - btn.textH/2;
      break;
    case Justification.right_justified:
      break;
  }

  final switch (btn.style.type) {
    case ButtonType.normal:
      renderNormalButton(btn, uiState, btnRealX, btnRealY, textX, textY, pressed);
      break;
    case ButtonType.bottom:
      renderBottomButton(btn, uiState, btnRealX, btnRealY, textX, textY, pressed);
      break;
  }
}

private void renderNormalButton(in Button btn, in UiState uiState, float btnRealX, float btnRealY, float textX, float textY, bool pressed) {
  C2Di_Context* ctx = C2Di_GetContext();

  auto tex = &gUiAssets.buttonTex;

  C2Di_SetTex(tex);
  C2Di_Update();

  enum CORNER_WIDTH = 6.0f, CORNER_HEIGHT = 4.0f;

  float tlX = btnRealX;
  float tlY = btnRealY;

  float trX = btnRealX + btn.w - CORNER_WIDTH;
  float trY = tlY;

  float blX = tlX;
  float blY = tlY + btn.h - CORNER_HEIGHT;

  float brX = trX;
  float brY = blY;

  pushQuad(tlX, tlY, tlX + CORNER_WIDTH, tlY + CORNER_HEIGHT, btn.z, 0, 1, (CORNER_WIDTH/tex.width), 1-CORNER_HEIGHT/tex.height); // top-left
  pushQuad(trX, tlY, trX + CORNER_WIDTH, tlY + CORNER_HEIGHT, btn.z, (CORNER_WIDTH/tex.width), 1, 0, 1-CORNER_HEIGHT/tex.height); // top-right
  pushQuad(blX, blY, blX + CORNER_WIDTH, blY + CORNER_HEIGHT, btn.z, 0, (16.0f+CORNER_HEIGHT)/tex.height, (CORNER_WIDTH/tex.width), 16.0f/tex.height); // bottom-left
  pushQuad(brX, brY, brX + CORNER_WIDTH, brY + CORNER_HEIGHT, btn.z, (CORNER_WIDTH/tex.width), (16.0f+CORNER_HEIGHT)/tex.height, 0, 16.0f/tex.height); // bottom-right

  pushQuad(tlX + CORNER_WIDTH, tlY,                 trX,                tlY + CORNER_HEIGHT, btn.z, (CORNER_WIDTH/tex.width), 1,          1, 1-CORNER_HEIGHT/tex.height); //top
  pushQuad(blX + CORNER_WIDTH, blY,                 brX,                blY + CORNER_HEIGHT, btn.z, (CORNER_WIDTH/tex.width), (16.0f+CORNER_HEIGHT)/tex.height,          1, 16.0f/tex.height); //bottom
  pushQuad(tlX,                tlY + CORNER_HEIGHT, tlX + CORNER_WIDTH, blY,                 btn.z, 0,           1-CORNER_HEIGHT/tex.height, (CORNER_WIDTH/tex.width), (16.0f+CORNER_HEIGHT)/tex.height); //left
  pushQuad(trX,                trY + CORNER_HEIGHT, trX + CORNER_WIDTH, brY,                 btn.z, (CORNER_WIDTH/tex.width),           1-CORNER_HEIGHT/tex.height, 0, (16.0f+CORNER_HEIGHT)/tex.height); //right

  pushQuad(tlX + CORNER_WIDTH, tlY + CORNER_HEIGHT, brX,                brY,                 btn.z, (CORNER_WIDTH/tex.width), 1-CORNER_HEIGHT/tex.height,          1, (16.0f+CORNER_HEIGHT)/tex.height); //center
  C2D_Flush();

  C2D_DrawText(
    btn.text, C2D_WithColor, GFXScreen.top, textX, textY, btn.z + 0.05, btn.style.textSize, btn.style.textSize, btn.style.colorText
  );
}

private void renderBottomButton(in Button btn, in UiState uiState, float btnRealX, float btnRealY, float textX, float textY, bool pressed) {
  uint topColor, bottomColor, baseColor, textColor, bevelTexColor, lineColor;
  textColor     = btn.style.colorText;
  bevelTexColor = 0xFFFFFFFF;

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

    pushQuad(btnRealX, btn.y - tex.height + 1, btnRealX+btn.w, btn.y + 1, btn.z, 0, 1, 1, 0);

    C2D_Flush();

    //Cleanup, resetting things to how C2D normally expects
    C2D_Prepare(C2DShader.normal, true);

    env = C3D_GetTexEnv(2);
    C3D_TexEnvInit(env);
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

    pushQuad(btnRealX, btnRealY, btnRealX+btn.w, btnRealY+btn.h, btn.z, 0, 1, 1, 0);

    C2D_Flush();

    //Cleanup, resetting things to how C2D normally expects
    C2D_Prepare(C2DShader.normal, true);

    env = C3D_GetTexEnv(2);
    C3D_TexEnvInit(env);
  }

  C2D_DrawRectSolid(btnRealX, btnRealY, btn.z + 0.05, btn.w, 1, lineColor);

  C2D_DrawText(
    btn.text, C2D_WithColor, GFXScreen.top, textX, textY+2, btn.z + 0.05, btn.style.textSize, btn.style.textSize, bevelTexColor
  );

  C2D_DrawText(
    btn.text, C2D_WithColor, GFXScreen.top, textX, textY, btn.z + 0.05, btn.style.textSize, btn.style.textSize, textColor
  );
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
  int result = -1;

  bool buttonOnBottomScreen(in Button btn) {
    return btn.y - scrollInfo.scrollOffset >= SCREEN_HEIGHT && btn.y + btn.h - scrollInfo.scrollOffset < 2*SCREEN_HEIGHT;
  }

  //get in or out of our custom scroll handler (d-pad / circle pad scrolls by selecting buttons)
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
        uiState.selectedLastFadeTimer = 1.0f;
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
        uiState.selectedLastFadeTimer = 1.0f;
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
    Button* btn = &buttons[uiState.buttonSelected];
    audioPlaySound(btn.style.pressedSound, btn.style.pressedSoundVol);
    result = uiState.buttonSelected;
  }
  else {
    //only allow touch scrolling, since we use the d-pad and circle pad
    scrollDiff = updateScrollDiff(input, (1 << ScrollMethod.touch));

    //select new button if the selected one went off-screen
    //@Speed slow but maybe inconsequential
    Button* curBtn = uiState.buttonSelected >= 0 && uiState.buttonSelected < buttons.length ? &buttons[uiState.buttonSelected] : null;
    if (curBtn && !buttonOnBottomScreen(*curBtn)) {
      if (curBtn.y - scrollInfo.scrollOffset < SCREEN_HEIGHT) {
        foreach (ref btn; buttons) { //assuming buttons are sorted here
          if (buttonOnBottomScreen(btn)) {
            uiState.buttonSelectedLast = uiState.buttonSelected;
            uiState.buttonSelected     = btn.id;
            break;
          }
        }
      }
      else {
        foreach_reverse (ref btn; buttons) { //assuming buttons are sorted here
          if (buttonOnBottomScreen(btn)) {
            uiState.buttonSelectedLast = uiState.buttonSelected;
            uiState.buttonSelected     = btn.id;
            break;
          }
        }
      }
    }
  }

  //fade out previously selected button
  uiState.selectedLastFadeTimer = approach(uiState.selectedLastFadeTimer, 0, 0.1);

  if (result == -1) {
    respondToScroll(scrollInfo, input, newLimitTop, newLimitBottom, scrollDiff);
  }

  //fade out current selection when touch scrolling, fade faster when done
  if (input.scrollMethodCur != ScrollMethod.none && input.scrollMethodCur != ScrollMethod.custom || input.scrollVel != 0) {
    uiState.selectedFadeTimer = approach(uiState.selectedFadeTimer, 0, 0.1);
  }
  else {
    uiState.selectedFadeTimer = approach(uiState.selectedFadeTimer, 1, 0.25);
  }

  return result;
}}

void renderButtonSelectionIndicator(in UiState uiState, in Button[] buttons, in ScrollInfo scrollInfo, GFXScreen screen) { with (scrollInfo) {
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

  void drawIndicatorForButton(const(Button)* btn, float alphaFloat) {
    bool pressed = btn.id == uiState.buttonHeld && btn.id == uiState.buttonHovered;
    ubyte alpha  = cast(ubyte) round(0xFF*alphaFloat);

    env = C3D_GetTexEnv(2); //must be done to mark the texenv as dirty! without this, each indicator will have one alpha
    C3D_TexEnvColor(env, C2D_Color32(0xFF, 0xFF, 0xFF, alpha));

    //tlX, tlY, etc. here mean "top-left quad of the selection indicator shape", top-left corner being the origin
    float screenFactor = (screen == GFXScreen.top) * ((SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2);
    float tlX = btn.x - LINE_WIDTH + screenFactor;
    float tlY = btn.y + pressed * BUTTON_DEPRESS_OFFSETS[btn.style.type] - LINE_WIDTH - floor(scrollInfo.scrollOffset)
                - (screen == GFXScreen.bottom) * SCREEN_HEIGHT;

    float trX = btn.x + btn.w - (tex.width - LINE_WIDTH) + screenFactor;
    float trY = tlY;

    float blX = tlX;
    float blY = tlY + btn.h + LINE_WIDTH - (tex.height - LINE_WIDTH);

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

    C2D_Flush(); //need this if alpha value changes
  }

  if (uiState.buttonSelected >= 0 && uiState.buttonSelected < buttons.length) {
    drawIndicatorForButton(&buttons[uiState.buttonSelected], uiState.selectedFadeTimer);
  }

  if (uiState.buttonSelectedLast >= 0 && uiState.buttonSelectedLast < buttons.length) {
    drawIndicatorForButton(&buttons[uiState.buttonSelectedLast], uiState.selectedLastFadeTimer);
  }

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);

  env = C3D_GetTexEnv(2);
  C3D_TexEnvInit(env);
}}

////////
// Scroll Indicator
////////

void renderScrollIndicator(in ScrollInfo scrollInfo, float x, float yMin, float yMax, float viewHeight, bool rightJustified = false) { with (scrollInfo) {
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

  auto interpAmount     = min(pushingAgainstTimer, PUSHING_AGAINST_TIMER_MAX)*1.0f/PUSHING_AGAINST_TIMER_MAX;
  auto colorLerp        = lerp(COLOR_NORMAL,         COLOR_PUSHING,         interpAmount);
  auto colorOutlineLerp = lerp(COLOR_NORMAL_OUTLINE, COLOR_PUSHING_OUTLINE, interpAmount);

  auto colorC2d        = C2D_Color32f(colorLerp.x,        colorLerp.y,        colorLerp.z,        0);
  auto colorOutlineC2d = C2D_Color32f(colorOutlineLerp.x, colorOutlineLerp.y, colorOutlineLerp.z, 1);

  float scale = (yMax - yMin) / (limitBottom - limitTop + viewHeight);
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

  float realX = round(x - rightJustified*indicatorTex.width), realY = round(yMin + scrollOffset * scale);
  pushQuadUvSwap(realX, realY,                                realX + indicatorTex.width, realY + indicatorTex.width,           0,  0, 0,   1, 1);
  pushQuadUvSwap(realX, realY + indicatorTex.height,          realX + indicatorTex.width, realY + height - indicatorTex.height, 0,  0, 0.5, 1, 1);
  pushQuadUvSwap(realX, realY + height - indicatorTex.height, realX + indicatorTex.width, realY + height,                       0,  1, 1,   0, 0);

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);
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