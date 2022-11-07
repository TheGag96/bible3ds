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
import std.math;

//debug import bible.debugging;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.time;

nothrow: @nogc:

__gshared TickCounter tickCounter;

__gshared float size = 0.5f;
__gshared C2D_TextBuf gTextBuf;
__gshared C2D_Text[512] gTextArr;

struct LoadedPage {
  C2D_WrapInfo[] wrapInfos;

  static struct LineTableEntry {
    uint textLineIndex;
    float realPos;
  }
  LineTableEntry[] actualLineNumberTable;
}

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

  gTextBuf = C2D_TextBufNew(16384);

  int curChapter = 1;

  auto book = openBibleBook(Translation.asv, Book.Romans);
  auto loadedPage = loadPage(gTextArr[], gTextBuf, book.chapters[curChapter]);

  float glyphWidth, glyphHeight;
  C2D_TextGetDimensions(&gTextArr[0], size, size, &glyphWidth, &glyphHeight);

  enum ScrollMethod {
    none, dpad, circle, touch
  }

  touchPosition touchLast = {0, 0}, touchLastLast = {0, 0};
  float scrollOffset = 0, scrollOffsetLast = 0, scrollVel = 0, scrollDistance = 0;
  ScrollMethod scrollMethodCur;

  enum OneFrameEvent {
    not_triggered, triggered, already_processed,
  }

  OneFrameEvent startedScrolling;
  OneFrameEvent scrollJustStopped;

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

    touchPosition touch;
    hidTouchRead(&touch);

    circlePosition circle;
    hidCircleRead(&circle);

    if (circle != circlePosition.init) {
      int xzz = 3;
    }

    //debug printf("\x1b[6;1HTS: watermark: %4d, high: %4d\x1b[K", gTempStorage.watermark, gTempStorage.highWatermark);
    gTempStorage.reset();

    input.update(kDown, kHeld);

    ////
    // update scrolling
    ////

    static struct ScrollDiff {
      float x = 0, y = 0;
    }
    ScrollDiff scrollDiff;

    enum CIRCLE_DEADZONE = 15;

    final switch (scrollMethodCur) {
      case ScrollMethod.none: break;
      case ScrollMethod.dpad:
        if (!input.held(Key.dup | Key.ddown | Key.dleft | Key.dright)) {
          scrollMethodCur = ScrollMethod.none;
        }
        break;
      case ScrollMethod.circle:
        if (circle.dy * circle.dy + circle.dx * circle.dx <= CIRCLE_DEADZONE * CIRCLE_DEADZONE) {
          scrollMethodCur = ScrollMethod.none;
        }
        break;
      case ScrollMethod.touch:
        if (!input.held(Key.touch)) {
          scrollMethodCur = ScrollMethod.none;
        }
        break;
    }

    if (scrollMethodCur == ScrollMethod.none) {
      StartScrollingSwitch:
      foreach (method; ScrollMethod.min..ScrollMethod.max+1) {
        final switch (method) {
          case ScrollMethod.none: break;
          case ScrollMethod.dpad:
            if (input.held(Key.dup | Key.ddown | Key.dleft | Key.dright)) {
              scrollMethodCur = cast(ScrollMethod) method;
              break StartScrollingSwitch;
            }
            break;
          case ScrollMethod.circle:
            if (circle.dy * circle.dy + circle.dx * circle.dx > CIRCLE_DEADZONE * CIRCLE_DEADZONE) {
              scrollMethodCur = cast(ScrollMethod) method;
              break StartScrollingSwitch;
            }
            break;
          case ScrollMethod.touch:
            if (input.held(Key.touch)) {
              scrollMethodCur = cast(ScrollMethod) method;
              break StartScrollingSwitch;
            }
            break;
        }
      }

      if (scrollMethodCur != ScrollMethod.none) scrollVel = 0;
    }

    final switch (scrollMethodCur) {
      case ScrollMethod.none:
        if (input.prevHeld(Key.touch)) {
          scrollVel = max(min(touchLast.py - touchLastLast.py, 40), -40);
        }
        scrollDiff.y = scrollVel;
        scrollVel *= 0.95;

        if (fabs(scrollVel) < 3) {
          scrollVel = 0;
        }
        break;
      case ScrollMethod.dpad:
        if      (input.held(Key.dup))    scrollDiff.y =  5;
        else if (input.held(Key.ddown))  scrollDiff.y = -5;
        else if (input.held(Key.dleft))  scrollDiff.x = -5;
        else if (input.held(Key.dright)) scrollDiff.x =  5;
        break;
      case ScrollMethod.circle:
        scrollDiff = ScrollDiff(circle.dx/10, circle.dy/10);
        break;
      case ScrollMethod.touch:
        scrollDiff = ScrollDiff(touch.px - touchLast.px, touch.py - touchLast.py);
        break;
    }


    scrollOffsetLast = scrollOffset;

    if (scrollMethodCur == ScrollMethod.touch) {
      if (!input.down(Key.touch)) {
        scrollOffset += scrollDiff.y;
      }
    }
    else {
      scrollOffset += scrollDiff.y;
    }

    float scrollLimit = loadedPage.actualLineNumberTable.length * glyphHeight + MARGIN * 2 - SCREEN_HEIGHT * 2;
    if (scrollOffset > 0) {
      scrollOffset = 0;
      scrollVel = 0;
    }
    else if (scrollOffset < -scrollLimit) {
      scrollOffset = -scrollLimit;
      scrollVel = 0;
    }

    ////
    // handle scrolling events
    ////

    if (scrollJustStopped == OneFrameEvent.not_triggered && (scrollOffset == 0 || scrollOffset == -scrollLimit) && scrollOffset != scrollOffsetLast) {
      scrollJustStopped = OneFrameEvent.triggered;
    }
    else if (scrollOffset != 0 && scrollOffset != -scrollLimit) {
      scrollJustStopped = OneFrameEvent.not_triggered;
    }

    if (startedScrolling == OneFrameEvent.not_triggered && input.held(Key.touch) && scrollOffset != scrollOffsetLast) {
      startedScrolling = OneFrameEvent.triggered;
    }
    else if (!input.held(Key.touch)) {
      startedScrolling = OneFrameEvent.not_triggered;
    }

    ////
    // play sounds
    ////

    if (startedScrolling == OneFrameEvent.triggered) {
      audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_tick, 0.1);
      startedScrolling = OneFrameEvent.already_processed;
    }

    if (floor(scrollOffset/(glyphHeight*4)) != floor(scrollOffsetLast/(glyphHeight*4))) {
      audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_tick, 0.05);
    }

    if (scrollJustStopped == OneFrameEvent.triggered) {
      audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_stop, 0.1);
      scrollJustStopped = OneFrameEvent.already_processed;
    }

    touchLastLast = touchLast;
    touchLast = touch;

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

      int virtualLine = max(cast(int) floor((-round(scrollOffset+MARGIN))/glyphHeight), 0);
      int renderStartLine = loadedPage.actualLineNumberTable[virtualLine].textLineIndex;
      float renderStartOffset = round(scrollOffset + loadedPage.actualLineNumberTable[virtualLine].realPos + MARGIN);

      auto result = renderPage(GFXScreen.top, GFX3DSide.left, slider, book.chapters[curChapter], loadedPage.wrapInfos, gTextArr[], renderStartLine, 0, renderStartOffset);

      if (_3DEnabled) {
        C2D_TargetClear(topRight, CLEAR_COLOR);
        C2D_SceneBegin(topRight);

        renderPage(GFXScreen.top, GFX3DSide.right, slider, book.chapters[curChapter], loadedPage.wrapInfos, gTextArr[], renderStartLine, 0, renderStartOffset);
      }

      C2D_TargetClear(bottom, CLEAR_COLOR);
      C2D_SceneBegin(bottom);
      renderPage(GFXScreen.bottom, GFX3DSide.left, slider, book.chapters[curChapter], loadedPage.wrapInfos, gTextArr[], result.line, 0, result.offsetY);
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

LoadedPage loadPage(C2D_Text[] textArray, C2D_TextBuf textBuf, char[][] pageLines) {
  LoadedPage result;
  result.wrapInfos = allocArray!C2D_WrapInfo(pageLines.length);

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextParse(&textArray[lineNum], textBuf, pageLines[lineNum].ptr);
    result.wrapInfos[lineNum] = C2D_CalcWrapInfo(&textArray[lineNum], size, SCREEN_BOTTOM_WIDTH - 2 * MARGIN);
  }

  auto actualNumLines = pageLines.length;
  foreach (ref wrapInfo; result.wrapInfos) {
    actualNumLines += wrapInfo.words[$-1].newLineNumber;
  }

  float glyphWidth, glyphHeight;
  C2D_TextGetDimensions(&textArray[0], size, size, &glyphWidth, &glyphHeight);
  result.actualLineNumberTable = allocArray!(LoadedPage.LineTableEntry)(actualNumLines);
  size_t runner = 0;
  foreach (i, ref wrapInfo; result.wrapInfos) {
    auto realLines = wrapInfo.words[$-1].newLineNumber + 1;

    result.actualLineNumberTable[runner..runner+realLines] = LoadedPage.LineTableEntry(i, runner * glyphHeight);

    runner += realLines;
  }

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextOptimize(&textArray[lineNum]);
  }

  return result;
}

void unloadPage(LoadedPage* page) {
  freeArray(page.wrapInfos);
  freeArray(page.actualLineNumberTable);
}

enum SCREEN_TOP_WIDTH    = 400.0f;
enum SCREEN_BOTTOM_WIDTH = 320.0f;
enum SCREEN_HEIGHT       = 240.0f;
enum MARGIN = 8.0f;

struct RenderResult {
  int line;
  float offsetY;
}

RenderResult renderPage(GFXScreen screen, GFX3DSide side, float slider3DState, char[][] lines, C2D_WrapInfo[] wrapInfos, C2D_Text[] textArray, int startLine, float offsetX, float offsetY) {
  float width, height;

  float startX;
  if (screen == GFXScreen.top) {
    startX = offsetX + (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2 + MARGIN;
  }
  else {
    startX = offsetX + MARGIN;
  }

  C2D_TextGetDimensions(&textArray[0], size, size, &width, &height);

  int i = max(startLine, 0);
  float extra = 0;
  while (offsetY < SCREEN_HEIGHT && i < lines.length) {
    C2D_DrawText(&textArray[i], C2D_WordWrapPrecalc, screen, startX, offsetY, 0.5f, size, size, &wrapInfos[i]); //, SCREEN_BOTTOM_WIDTH - 2 * MARGIN);
    extra = height * (1 + wrapInfos[i].words[textArray[i].words-1].newLineNumber);
    offsetY += extra;
    i++;
  }

  return RenderResult(i - 1, offsetY - SCREEN_HEIGHT - extra);
}