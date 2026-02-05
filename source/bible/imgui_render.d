module bible.imgui_render;

import bible.imgui, bible.util, bible.profiling;
import ctru, citro2d, citro3d;
import std.math;

@nogc: nothrow:

Vec2 renderLabel(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  auto thisDepth = depthOffset(box.computedDepth, screen, side, slider3DState);
  auto rect      = box.rect + drawOffset + Vec2(thisDepth, 0);
  rect.left      = floorSlop(rect.left); rect.top = floorSlop(rect.top); rect.right = floorSlop(rect.right); rect.bottom = floorSlop(rect.bottom);

  float textX, textY;
  final switch (box.justification) {
    case Justification.min:
      textX = rect.left+box.style.margin.x;
      textY = rect.top+box.style.margin.y;
      break;
    case Justification.center:
      textX = (rect.left + rect.right)/2 - box.text.width/2;
      textY = (rect.top + rect.bottom)/2 - box.textHeight/2;
      break;
    case Justification.max:
      break;
  }

  C2D_DrawText(
    &box.text, C2D_WithColor, GFXScreen.top, textX, textY, z, box.style.textSize, box.style.textSize, box.style.colors[Color.text]
  );

  return Vec2(0);
}

enum BUTTON_DEPRESS_NORMAL = 3;
enum BUTTON_DEPRESS_BOTTOM = 1;

Vec2 renderNormalButton(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  bool pressed = box.activeT == 1;
  auto result = Vec2(0, pressed * BUTTON_DEPRESS_NORMAL);

  auto thisDepth = depthOffset(box.computedDepth, screen, side, slider3DState);
  auto rect = box.rect + result + drawOffset + Vec2(thisDepth, 0);
  rect.left = floorSlop(rect.left); rect.top = floorSlop(rect.top); rect.right = floorSlop(rect.right); rect.bottom = floorSlop(rect.bottom);

  float textX, textY;
  final switch (box.justification) {
    case Justification.min:
      textX = rect.left+box.style.margin.x;
      textY = rect.top+box.style.margin.y;
      break;
    case Justification.center:
      textX = (rect.left + rect.right)/2 - box.text.width/2;
      textY = (rect.top + rect.bottom)/2 - box.textHeight/2;
      break;
    case Justification.max:
      break;
  }

  C2Di_Context* ctx = C2Di_GetContext();
  C2D_Prepare(C2DShader.normal);

  auto tex = &gUiAssets.buttonTex;

  C2Di_SetTex(tex);
  C2Di_Update();

  C3D_ProcTexBind(1, null);
  C3D_ProcTexLutBind(GPUProcTexLutId.alphamap, null);

  // Apply dynamic color
  auto env = C3D_GetTexEnv(0);
  C3D_TexEnvInit(env);
  C3D_TexEnvSrc(env, C3DTexEnvMode.both, GPUTevSrc.texture0, GPUTevSrc.constant);
  C3D_TexEnvFunc(env, C3DTexEnvMode.both, GPUCombineFunc.modulate);
  C3D_TexEnvOpRgb(env, GPUTevOpRGB.src_color, GPUTevOpRGB.src_color);
  C3D_TexEnvOpAlpha(env, GPUTevOpA.src_alpha, GPUTevOpA.src_alpha);
  C3D_TexEnvColor(env, box.style.colors[Color.button_normal]);

  env = C3D_GetTexEnv(1);
  C3D_TexEnvInit(env);

  env = C3D_GetTexEnv(5);
  C3D_TexEnvInit(env);

  enum CORNER_WIDTH = 6.0f, CORNER_HEIGHT = 4.0f;

  float tlX = rect.left;
  float tlY = rect.top;

  float trX = rect.right - CORNER_WIDTH;
  float trY = tlY;

  float blX = tlX;
  float blY = rect.bottom - CORNER_HEIGHT;

  float brX = trX;
  float brY = blY;


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

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);

  env = C3D_GetTexEnv(2);
  C3D_TexEnvInit(env);

  if (box.flags & BoxFlags.draw_text) {
    C2D_DrawText(
      &box.text, C2D_WithColor, GFXScreen.top, textX, textY, z, box.style.textSize, box.style.textSize, box.style.colors[Color.text]
    );
  }

  if ((box.parent.flags & BoxFlags.select_children) && (box.flags & BoxFlags.selectable) && box.hotT > 0) {
    renderButtonSelectionIndicator(box, rect, screen, side, _3DEnabled, slider3DState, drawOffset, z);
  }

  return result;
}

Vec2 renderBottomButton(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  bool pressed = box.activeT == 1;
  auto result = Vec2(0, pressed * BUTTON_DEPRESS_BOTTOM);

  auto rect = box.rect + result + drawOffset;
  rect.left = floorSlop(rect.left); rect.top = floorSlop(rect.top); rect.right = floorSlop(rect.right); rect.bottom = floorSlop(rect.bottom);

  float textX, textY;
  final switch (box.justification) {
    case Justification.min:
      textX = rect.left+box.style.margin.x;
      textY = rect.top+box.style.margin.y;
      break;
    case Justification.center:
      textX = (rect.left + rect.right)/2 - box.text.width/2;
      textY = (rect.top + rect.bottom)/2 - box.textHeight/2;
      break;
    case Justification.max:
      break;
  }

  uint topColor, bottomColor, baseColor, textColor, bevelTexColor, lineColor;


  bevelTexColor = box.style.colors[Color.button_bottom_text_bevel];
  textColor     = box.style.colors[Color.button_bottom_text];

  if (pressed) {
    topColor      = box.style.colors[Color.button_bottom_pressed_top];
    bottomColor   = box.style.colors[Color.button_bottom_pressed_bottom];
    baseColor     = box.style.colors[Color.button_bottom_pressed_base];
    lineColor     = box.style.colors[Color.button_bottom_pressed_line];
    uint tmp = textColor;
    textColor = bevelTexColor;
    bevelTexColor = tmp;
  }
  else {
    topColor      = box.style.colors[Color.button_bottom_top];
    bottomColor   = box.style.colors[Color.button_bottom_bottom];
    baseColor     = box.style.colors[Color.button_bottom_base];
    lineColor     = box.style.colors[Color.button_bottom_line];
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
    C3D_TexEnvColor(env, box.style.colors[Color.button_bottom_above_fade]);

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

  // Top border line
  // Left-side border line (if there is a left neighbor), with a fade of two different colors on each side.
  {
    auto tex = &gUiAssets.bottomButtonLineTex;

    C2Di_SetTex(tex);
    C2Di_Update();

    // For the top line:
    // color.rgb = mix(lineColor, box.style.colors[Color.button_bottom_above_fade], texture(texture0, uv).rgb);
    // color.a   = texture(texture0, uv).a;
    //
    // For the side line:
    // color.rgb = mix(box.style.colors[Color.button_bottom_line], box.style.colors[Color.button_bottom_above_fade], texture(texture0, uv).rgb);
    // color.a   = texture(texture0, uv).a;
    //
    // The side line always gets colored with the unpressed line color.

    C3D_TexEnv* env = C3D_GetTexEnv(0);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.constant);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.replace);
    C3D_TexEnvColor(env, box.style.colors[Color.button_bottom_above_fade]);

    env = C3D_GetTexEnv(1);
    C3D_TexEnvInit(env);
    C3D_TexEnvSrc(env, C3DTexEnvMode.rgb, GPUTevSrc.previous, GPUTevSrc.constant, GPUTevSrc.texture0);
    C3D_TexEnvFunc(env, C3DTexEnvMode.rgb, GPUCombineFunc.interpolate);
    C3D_TexEnvSrc(env, C3DTexEnvMode.alpha, GPUTevSrc.texture0);
    C3D_TexEnvFunc(env, C3DTexEnvMode.alpha, GPUCombineFunc.replace);
    C3D_TexEnvColor(env, box.style.colors[Color.button_bottom_line]);

    env = C3D_GetTexEnv(5);
    C3D_TexEnvInit(env);

    // Left-side border line
    if ((box.parent.flags & BoxFlags.horizontal_children) && !boxIsNull(box.prev)) {
      pushQuad(rect.left - tex.width/2, rect.top + 1 - pressed * BUTTON_DEPRESS_BOTTOM, rect.left + tex.width/2, rect.bottom, z, 0, 1 - 1.0/tex.height, 1, 0);

      // Unfortunate that we can't batch these because of the potential color difference...
      C2D_Flush();
    }

    env = C3D_GetTexEnv(1);
    C3D_TexEnvColor(env, lineColor);

    // Top line
    // If unpressed, draw one extra pixel to the left, so that even with a pressed left neighbor, there wil still be a
    // square border.
    float unpressedExtra = !pressed;
    pushQuad(rect.left - unpressedExtra, rect.top, rect.right, rect.top + 1, z, 0, 1, 1, 1 - 1.0/tex.height);

    C2D_Flush();

    //Cleanup, resetting things to how C2D normally expects
    C2D_Prepare(C2DShader.normal, true);

    env = C3D_GetTexEnv(2);
    C3D_TexEnvInit(env);
  }

  // @TODO: Flipped for dark bottom button
  //int textBevelOffset = pressed ? -1 : 1;
  int textBevelOffset = 1;

  if (box.flags & BoxFlags.draw_text) {
    C2D_DrawText(
      &box.text, C2D_WithColor, GFXScreen.top, textX, textY + textBevelOffset, z, box.style.textSize, box.style.textSize, bevelTexColor
    );

    C2D_DrawText(
      &box.text, C2D_WithColor, GFXScreen.top, textX, textY, z, box.style.textSize, box.style.textSize, textColor
    );
  }

  return result;
}

Vec2 renderListButton(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  // @TODO: Beautify and compress

  bool pressed = box.activeT == 1;

  auto thisDepth = depthOffset(box.computedDepth, screen, side, slider3DState);
  auto rect      = box.rect + drawOffset + Vec2(thisDepth, 0);
  rect.left      = floorSlop(rect.left); rect.top = floorSlop(rect.top); rect.right = floorSlop(rect.right); rect.bottom = floorSlop(rect.bottom);

  float textX, textY;
  final switch (box.justification) {
    case Justification.min:
      textX = rect.left+box.style.margin.x;
      textY = rect.top+box.style.margin.y;
      break;
    case Justification.center:
      textX = (rect.left + rect.right)/2 - box.text.width/2;
      textY = (rect.top + rect.bottom)/2 - box.textHeight/2;
      break;
    case Justification.max:
      break;
  }

  uint baseColor, textColor, lineColor;

  textColor     = box.style.colors[Color.button_bottom_text];

  if (pressed) {
    baseColor     = box.style.colors[Color.button_bottom_pressed_top];
    lineColor     = box.style.colors[Color.button_bottom_pressed_line];
  }
  else {
    baseColor     = box.style.colors[Color.button_bottom_top];
    lineColor     = box.style.colors[Color.button_bottom_line];
  }

  // main button area
  C2D_DrawRectSolid(rect.left, rect.top, z, rect.right-rect.left, rect.bottom-rect.top, baseColor);

  C2D_DrawRectSolid(rect.left, rect.top, z, rect.right-rect.left, 1, lineColor);
  if (boxIsNull(box.next)) {
    C2D_DrawRectSolid(rect.left, rect.bottom, z, rect.right-rect.left, 1, lineColor);
  }

  auto result = Vec2(0, pressed * BUTTON_DEPRESS_BOTTOM);
  if (box.flags & BoxFlags.draw_text) {
    C2D_DrawText(
      &box.text, C2D_WithColor, GFXScreen.top, textX + result.x, textY + result.y, z, box.style.textSize, box.style.textSize, textColor
    );
  }

  return result;
}

Vec2 renderButtonSelectionIndicator(Box* box, in Rectangle rect, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
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
  C3D_TexEnvColor(env, box.style.colors[Color.button_sel_indicator]);

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

  float thisDepth = depthOffset(box.depth, screen, side, slider3DState);

  //tlX, tlY, etc. here mean "top-left quad of the selection indicator shape", top-left corner being the origin
  float tlX = rect.left - LINE_WIDTH + thisDepth;
  float tlY = rect.top  - LINE_WIDTH;

  float trX = rect.right - (tex.width - LINE_WIDTH) + thisDepth;
  float trY = tlY;

  float blX = tlX;
  float blY = rect.bottom - (tex.height - LINE_WIDTH);

  float brX = trX;
  float brY = blY;


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

  return Vec2(0);
}

Vec2 renderModalBackground(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  auto rect = box.rect + drawOffset;

  C2D_DrawRectSolid(rect.left, rect.top, z, rect.right - rect.left, rect.bottom - rect.top, box.style.colors[Color.clear_color]);
  return Vec2(0);
}

Vec2 renderVerse(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  // @TODO: Something better!
  if (box.hotT > 0) {
    auto rect = box.rect + drawOffset;
    rect.left  += box.style.margin.x/2;
    rect.right -= box.style.margin.x/2;
    renderButtonSelectionIndicator(box, rect, screen, side, _3DEnabled, slider3DState, drawOffset, z);
  }

  return Vec2(0);
}


struct Assets {
  C3D_Tex vignetteTex, lineTex; //@TODO: Move somewhere probably
  C3D_Tex selectorTex;
  C3D_Tex buttonTex, bottomButtonTex, bottomButtonAboveFadeTex, bottomButtonLineTex;
  C3D_Tex indicatorTex;
}

Assets gUiAssets;

bool loadTextureFromFile(C3D_Tex* tex, C3D_TexCube* cube, string filename) {
  auto bytes = readFile(filename);
  scope (exit) freeArray(bytes);

  Tex3DS_Texture t3x = Tex3DS_TextureImport(bytes.ptr, bytes.length, tex, cube, false);
  if (!t3x)
    return false;

  // Delete the t3x object since we don't need it
  Tex3DS_TextureFree(t3x);
  return true;
}

void loadAssets() {
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
    if (!loadTextureFromFile(&bottomButtonLineTex, null, "romfs:/gfx/bottom_button_line.t3x"))
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

void drawBackground(GFXScreen screen, GFX3DSide side, float slider3DState, uint colorBg, uint colorStripesDark, uint colorStripesLight, int depth) {
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

  float thisDepth = depthOffset(depth, screen, side, slider3DState);

  C2Di_Vertex[6] vertex_list = [
    // First face (PZ)
    // First triangle
    { thisDepth + 0.0f,            0.0f,          0.0f,   0.0f,  0.0f,  0.0f, -1.0f,  0xFF<<24 },
    { thisDepth + thisScreenWidth, 0.0f,          0.0f,  28.0f,  0.0f,  2.0f, -1.0f,  0xFF<<24 },
    { thisDepth + thisScreenWidth, SCREEN_HEIGHT, 0.0f,  28.0f, 28.0f,  2.0f,  1.0f,  0xFF<<24 },
    // Second triangle
    { thisDepth + thisScreenWidth, SCREEN_HEIGHT, 0.0f,  28.0f, 28.0f,  2.0f,  1.0f,  0xFF<<24 },
    { thisDepth + 0.0f,            SCREEN_HEIGHT, 0.0f,   0.0f, 28.0f,  0.0f,  1.0f,  0xFF<<24 },
    { thisDepth + 0.0f,            0.0f,          0.0f,   0.0f,  0.0f,  0.0f, -1.0f,  0xFF<<24 },
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

Vec2 renderScrollIndicator(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  if (boxIsNull(box.related) || box.related.scrollInfo.limitMin == box.related.scrollInfo.limitMax) {
    return Vec2(0);
  }

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

  auto colorNormal         = rgba8ToRgbaF(box.style.colors[Color.scroll_indicator]);
  auto colorNormalOutline  = rgba8ToRgbaF(box.style.colors[Color.scroll_indicator_outline]);
  auto colorPushing        = rgba8ToRgbaF(box.style.colors[Color.scroll_indicator_pushing]);
  auto colorPushingOutline = rgba8ToRgbaF(box.style.colors[Color.scroll_indicator_pushing_outline]);

  float thisDepth  = depthOffset(box.depth, screen, side, slider3DState);
  auto rect        = box.rect + drawOffset + Vec2(thisDepth, 0);
  float viewHeight = box.related.computedSize[Axis2.y];


  auto colorLerp        = lerp(colorNormal,        colorPushing,        box.hotT);
  auto colorOutlineLerp = lerp(colorNormalOutline, colorPushingOutline, box.hotT);

  auto colorC2d        = C2D_Color32f(colorLerp.x,        colorLerp.y,        colorLerp.z,        0);
  auto colorOutlineC2d = C2D_Color32f(colorOutlineLerp.x, colorOutlineLerp.y, colorOutlineLerp.z, 1);

  // @TODO: Only vertical scrolling indicators are supported right now.

  float scale = (rect.bottom - rect.top) / (box.related.scrollInfo.limitMax - box.related.scrollInfo.limitMin + viewHeight);
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
  float realX = round(rect.left - rightJustified*indicatorTex.width), realY = round(rect.top + box.related.scrollInfo.offset * scale);
  pushQuadUvSwap(realX, realY,                                realX + indicatorTex.width, realY + indicatorTex.width,           z,  0, 0,   1, 1);
  pushQuadUvSwap(realX, realY + indicatorTex.height,          realX + indicatorTex.width, realY + height - indicatorTex.height, z,  0, 0.5, 1, 1);
  pushQuadUvSwap(realX, realY + height - indicatorTex.height, realX + indicatorTex.width, realY + height,                       z,  1, 1,   0, 0);

  //Cleanup, resetting things to how C2D normally expects
  C2D_Prepare(C2DShader.normal, true);

  return Vec2(0);
}

////////
// Scroll Cache
////////

enum RTKind : ubyte {
  screen,
  texture,
}

struct RenderTarget {
  RTKind kind;
  GFXScreen screen;
  GFX3DSide side;
  float desiredWidth = 0, desiredHeight = 0, realWidth = 0, realHeight = 0;

  C3D_Tex tex;
  Tex3DS_SubTexture subtex;
  C3D_RenderTarget* c3dTarget;

  C2DShader shader;

  // For scroll caches specifically
  bool needsRepaint;
  int u_scrollRenderOffset; // location of uniform from scroll_cache.v.pica
  ubyte curStencilVal;
}

RenderTarget screenRenderTargetCreate(GFXScreen screen, GFX3DSide side) {
  RenderTarget result;

  result.kind          = RTKind.screen;
  result.c3dTarget     = C2D_CreateScreenTarget(screen, side);
  result.desiredWidth  = screenWidth(screen);
  result.desiredHeight = SCREEN_HEIGHT;
  result.realWidth     = result.desiredWidth;
  result.realHeight    = result.desiredHeight;

  return result;
}

RenderTarget offscreenRenderTexCreate(ushort width, ushort height, C2DShader shader = C2DShader.normal) {
  import std.math.algebraic : nextPow2;

  RenderTarget result;

  //round sizes to power of two if needed
  result.kind          = RTKind.texture;
  result.desiredWidth  = width;
  result.desiredHeight = height;
  width                = cast(ushort) ceilPow2(width);
  height               = cast(ushort) ceilPow2(height);
  result.realWidth     = width;
  result.realHeight    = height;
  result.shader        = shader;

  C3D_TexInitVRAM(&result.tex, width, height, GPUTexColor.rgba8);
  C3D_TexSetWrap(&result.tex, GPUTextureWrapParam.repeat, GPUTextureWrapParam.repeat);
  result.c3dTarget = C3D_RenderTargetCreateFromTex(&result.tex, GPUTexFace.texface_2d, 0, C3D_DEPTHTYPE(GPUDepthBuf.depth24_stencil8));

  if (shader == C2DShader.scroll_cache) {
    result.u_scrollRenderOffset = C2D_ShaderGetUniformLocation(shader, GPUShaderType.vertex_shader, "scrollRenderOffset");
  }

  result.subtex = Tex3DS_SubTexture(
    width  : cast(ushort) result.desiredWidth,
    height : cast(ushort) result.desiredHeight,
    left   : 0,
    right  : 1.0f*result.desiredWidth/result.realWidth,
    top    : 1,
    bottom : 1.0 - 1.0f*result.desiredHeight/result.realHeight,
  );

  return result;
}

RenderTarget scrollCacheCreate(ushort width, ushort height) {
  return offscreenRenderTexCreate(width, height, C2DShader.scroll_cache);
}

alias renderCallback(T) = void function(T* userData, float from, float to);

void renderTargetBegin(RenderTarget* renderTarget, uint clearColor = 0) { with (renderTarget) {
  mixin(timeBlock("renderTargetBegin"));
  C2D_Flush();
  C3D_RenderTargetClear(c3dTarget, shader == C2DShader.scroll_cache ? C3DClearBits.clear_depth : C3DClearBits.clear_all, clearColor, 0);
  if (shader != C2DShader.scroll_cache) {
    C3D_StencilTest(false, GPUTestFunc.always, 0, 0, 0);
    C3D_SetScissor(GPUScissorMode.disable, 0, 0, 0, 0);
  }
  C2D_SceneBegin(c3dTarget);
  C2D_Prepare(shader);
  curStencilVal = 1;
}}

void renderTargetEnd(RenderTarget* renderTarget) { with (renderTarget) {
  C2D_Flush();
  C2D_Prepare(C2DShader.normal);
  C3D_StencilTest(false, GPUTestFunc.always, 0, 0, 0);
}}

pragma(inline, true)
void scrollCacheRenderScrollUpdate(T)(
  RenderTarget* scrollCache,
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
  RenderTarget* scrollCache,
  in ScrollInfo scrollInfo,
  void function(void* userData, float from, float to) @nogc nothrow render, void* userData,
  uint clearColor = 0,
) { with (scrollCache) with (scrollInfo) {
  float drawStart, drawEnd;

  float scroll     = floorSlop(offset),
        scrollLast = floorSlop(offsetLast);

  if (needsRepaint) {
    needsRepaint = false;
    drawStart = scroll;
    drawEnd   = scroll+realHeight;
  }
  else {
    if (offset == offsetLast) return;

    drawStart  = (scrollLast < scroll) ? scrollLast + realHeight : scroll;
    drawEnd    = (scrollLast < scroll) ? scroll     + realHeight : scrollLast;
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
  RenderTarget* scrollCache,
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
  RenderTarget* scrollCache,
  float from, float to,
  void function(void* userData, float from, float to) @nogc nothrow render, void* userData,
  uint clearColor = 0,
) { with (scrollCache) {
  float drawStart  = from;
  float drawEnd    = to;
  float drawOffset = -(drawStart - wrap(drawStart, realHeight));
  float drawHeight = drawEnd-drawStart;

  float drawStartOnTexture = wrap(drawStart, realHeight);
  float drawEndOnTexture   = drawStartOnTexture + drawHeight;
  float drawOffTexture     = max(drawEndOnTexture - realHeight, 0);

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
  if (drawEndOnTexture >= realHeight) {
    C3D_FVUnifSet(GPUShaderType.vertex_shader, u_scrollRenderOffset, 0, drawOffset - realHeight, 0, 0);
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
  in RenderTarget scrollCache,
  float width, float height, float yOffset, float scroll
) { with (scrollCache) {
  Tex3DS_SubTexture result = {
    width  : cast(ushort) width,
    height : cast(ushort) height,
    left   : 0,
    right  : width/realWidth,
    top    : 1.0f - yOffset         /realHeight - floorSlop(wrap(scroll, realHeight))/realHeight,
    bottom : 1.0f - (yOffset+height)/realHeight - floorSlop(wrap(scroll, realHeight))/realHeight,
  };
  return result;
}}

C2D_Sprite spriteFromOffscreenRenderTex(RenderTarget* renderTex) {
  C2D_Image image = { &renderTex.tex, &renderTex.subtex };
  C2D_Sprite sprite;
  C2D_SpriteFromImage(&sprite, image);

  return sprite;
}

Vec2 scrollCacheDraw(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
  auto rect = clipWithinOther(box.rect, SCREEN_RECT[screen]);


  Tex3DS_SubTexture subtex = scrollCacheGetUvs(*box.scrollCache, rect.right-rect.left, rect.bottom-rect.top, rect.top, box.scrollInfo.offset);

  C2D_Image cacheImage = { &box.scrollCache.tex, &subtex };
  C2D_Sprite sprite;
  C2D_SpriteFromImage(&sprite, cacheImage);

  auto thisDepth = depthOffset(box.computedDepth, screen, side, slider3DState);
  auto drawPos   = Vec2(rect.left, rect.top) + drawOffset + Vec2(thisDepth, 0);
  C2D_SpriteSetPos(&sprite, drawPos.x, drawPos.y);
  C2D_SpriteSetDepth(&sprite, z);
  C2D_DrawSprite(&sprite);

  return Vec2(0);
}


////
// Loaded reading page
////

void renderPage(
  LoadedPage* loadedPage, float from, float to
) { with (loadedPage) {
  float width, height;

  float startX   = style.margin.x;
  float startY   = style.margin.y + SCREEN_HEIGHT;
  float textSize = style.textSize;

  C2D_TextGetDimensions(&loadedPage.textArray[0], textSize, textSize, &width, &height);

  int virtualLine = min(max(cast(int) floorSlop((round(from-startY))/glyphSize.y), 0), cast(int)loadedPage.actualLineNumberTable.length-1);
  int startLine = loadedPage.actualLineNumberTable[virtualLine].textLineIndex;
  float offsetY = loadedPage.actualLineNumberTable[virtualLine].realPos + startY;

  float extra = 0;
  int i = startLine; //max(startLine, 0);
  while (offsetY < to && i < linesInPage) {
    C2D_DrawText(
      &loadedPage.textArray[i], C2D_WithColor | C2D_WordWrapPrecalc, GFXScreen.bottom, startX, offsetY, 0.5f, textSize, textSize,
      style.colors[Color.text],
      &loadedPage.wrapInfos[i]
    );
    extra = height * (1 + (loadedPage.wrapInfos[i].words.length ? loadedPage.wrapInfos[i].words[loadedPage.textArray[i].words-1].newLineNumber : 0));
    offsetY += extra;
    i++;
  }
}}

float depthOffset(int depth, GFXScreen screen, GFX3DSide side, float slider3DState) {
  return screen == GFXScreen.bottom ? 0 : round((2*side-1) * depth * slider3DState);
}