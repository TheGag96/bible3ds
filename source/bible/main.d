/*
  Bible for 3DS
  Written by TheGag96
*/

module bible.main;

import ctru;
import citro3d;
import citro2d;

import bible.bible, bible.audio, bible.input, bible.util, bible.save;
import std.algorithm;
import std.string : representation;
import std.range;

//debug import bible.debugging;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.time;

nothrow: @nogc:

__gshared TickCounter tickCounter;

__gshared float size = 0.5f;
__gshared C2D_TextBuf g_staticBuf,  g_dynamicBuf;
__gshared C2D_Text[512] g_staticText;

extern(C) int main(int argc, char** argv) {
  srand(time(null));

  // Init libs
  romfsInit();

  gfxInitDefault();
  gfxSet3D(true); // Enable stereoscopic 3D
  C3D_Init(C3D_DEFAULT_CMDBUF_SIZE);
  C2D_Init(C2D_DEFAULT_MAX_OBJECTS);
  C2D_Prepare(C2DShader.normal);
  //consoleInit(GFXScreen.bottom, null);

  Input input;

  audioInit();

  gTempStorage.init();

  Result saveResult = saveGameInit();
  assert(!saveResult, "file creation failed");

  saveGameSelect(0);

  // Create screens
  C3D_RenderTarget* topLeft  = C2D_CreateScreenTarget(GFXScreen.top, GFX3DSide.left);
  C3D_RenderTarget* topRight = C2D_CreateScreenTarget(GFXScreen.top, GFX3DSide.right);
  C3D_RenderTarget* bottom   = C2D_CreateScreenTarget(GFXScreen.bottom, GFX3DSide.left);

  osTickCounterStart(&tickCounter);

  g_staticBuf = C2D_TextBufNew(4096);
  g_dynamicBuf = C2D_TextBufNew(4096);

  auto book = readTextFile(gTempStorage.printf("romfs:/bibles/asv/%s", BOOK_FILENAMES[Book.Romans].ptr));

  int numLines = book.representation.count('\n');
  char[][] lines = allocArray!(char[])(numLines);
  C2D_WrapInfo[] wrapInfos = allocArray!C2D_WrapInfo(numLines);

  foreach (i, line; book.representation.splitter('\n').enumerate) {
    if (i != numLines) lines[i] = cast(char[])line;
  }

  foreach (ref c; book.representation) {
    if (c == '\n') c = '\0';
  }

  foreach (lineNum; 0..numLines) {
    C2D_TextParse(&g_staticText[lineNum], g_staticBuf, lines[lineNum].ptr);
    wrapInfos[lineNum] = C2D_CalcWrapInfo(&g_staticText[lineNum], size, SCREEN_BOTTOM_WIDTH - 2 * MARGIN);
  }

  foreach (lineNum; 0..numLines) {
    C2D_TextOptimize(&g_staticText[lineNum]);
  }

  // Main loop
  while (aptMainLoop()) {
    osTickCounterUpdate(&tickCounter);
    float frameTime = osTickCounterRead(&tickCounter);

    //debug printf("\x1b[2;1HTime:    %6.8f\x1b[K", frameTime);

    static int counter = 0;

    debug if (frameTime > 17) {
      //printf("\x1b[%d;1HOverframe: %6.8f\x1b[K", 12+counter%10, frameTime);
      counter++;
    }

    hidScanInput();

    float slider = osGet3DSliderState();
    float _3DEnabled = slider > 0;

    // Respond to user input
    uint kDown = hidKeysDown();
    uint kHeld = hidKeysHeld();

    if ((kHeld & (Key.start | Key.select)) == (Key.start | Key.select))
      break; // break in order to return to hbmenu

    //debug printf("\x1b[6;1HTS: watermark: %4d, high: %4d\x1b[K", gTempStorage.watermark, gTempStorage.highWatermark);
    gTempStorage.reset();

    input.update(kDown, kHeld);

    //TODO: ui/stuff

    audioUpdate();

    //debug printf("\x1b[3;1HCPU:     %6.2f%%\x1b[K", C3D_GetProcessingTime()*6.0f);
    //debug printf("\x1b[4;1HGPU:     %6.2f%%\x1b[K", C3D_GetDrawingTime()*6.0f);
    //debug printf("\x1b[5;1HCmdBuf:  %6.2f%%\x1b[K", C3D_GetCmdBufUsage()*100.0f);

    // Render the scene
    enum CLEAR_COLOR = 0xFFEEEEEE;
    C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
    {
      C2D_TargetClear(topLeft, CLEAR_COLOR);
      C2D_SceneBegin(topLeft);

      auto result = renderPage(GFXScreen.top, GFX3DSide.left, slider, lines, wrapInfos, 0, 0);

      if (_3DEnabled) {
        C2D_TargetClear(topRight, CLEAR_COLOR);
        C2D_SceneBegin(topRight);

        renderPage(GFXScreen.top, GFX3DSide.right, slider, lines, wrapInfos, 0, 0);
      }

      C2D_TargetClear(bottom, CLEAR_COLOR);
      C2D_SceneBegin(bottom);
      renderPage(GFXScreen.bottom, GFX3DSide.left, slider, lines, wrapInfos, result.line, result.offsetY);
    }
    C3D_FrameEnd(0);
  }

  // Deinit libs
  audioFini();
  C2D_Fini();
  C3D_Fini();
  gfxExit();
  romfsExit();
  return 0;
}

enum SCREEN_TOP_WIDTH    = 400.0f;
enum SCREEN_BOTTOM_WIDTH = 320.0f;
enum SCREEN_HEIGHT       = 240.0f;
enum MARGIN = 8.0f;

struct RenderResult {
  int line;
  float offsetY;
}

RenderResult renderPage(GFXScreen screen, GFX3DSide side, float slider3DState, char[][] lines, C2D_WrapInfo[] wrapInfos, int startLine, float offsetY) {
  float width, height;

  float startX, startY;
  if (screen == GFXScreen.top) {
    startX = (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2 + MARGIN + (side == GFX3DSide.left ? -1 : 1) * slider3DState * 4;
    startY = MARGIN;
  }
  else {
    startX = MARGIN;
    startY = 0;
  }

  int i = startLine;
  float extra = 0;
  while (offsetY < SCREEN_HEIGHT) {
    C2D_DrawText(&g_staticText[i], C2D_WordWrapPrecalc, startX, startY + offsetY, 0.5f, size, size, &wrapInfos[i]); //, SCREEN_BOTTOM_WIDTH - 2 * MARGIN);
    C2D_TextGetDimensions(&g_staticText[i], size, size, &width, &height);
    auto text = &g_staticText[i];
    extra = height * (1 + wrapInfos[i].words[text.words-1].newLineNumber);
    offsetY += extra;
    i++;
  }

  return RenderResult(i - 1, startY + offsetY - SCREEN_HEIGHT - extra);
}