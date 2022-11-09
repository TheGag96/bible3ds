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


struct LoadedPage {
  C2D_TextBuf textBuf;
  C2D_Text[] textArray;

  C2D_WrapInfo[] wrapInfos;

  static struct LineTableEntry {
    uint textLineIndex;
    float realPos = 0;
  }
  LineTableEntry[] actualLineNumberTable;

  float scrollOffset = 0, scrollOffsetLast = 0;
}

enum View {
  book,
  reading,
}

__gshared View curView = View.book;

struct Button {
  float x = 0, y = 0, w = 0, h = 0;
  C2D_Text* text;
}

struct BookViewData {
  C2D_TextBuf textBuf;
  C2D_Text[] textArray;

  Button[Book.max+1] bookButtons;

  float scrollOffset = 0, scrollOffsetLast = 0;
}

enum OneFrameEvent {
  not_triggered, triggered, already_processed,
}

struct ReadingViewData {
  float size = 0;
  float glyphWidth = 0, glyphHeight = 0;

  OpenBook book;
  Book curBook;
  LoadedPage loadedPage;
  int curChapter;

  OneFrameEvent startedScrolling;
  OneFrameEvent scrollJustStopped;
}

enum CLEAR_COLOR = 0xFFEEEEEE;

ReadingViewData readingViewData;
BookViewData    bookViewData;

extern(C) int main(int argc, char** argv) {
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
  C3D_RenderTarget* topLeft  = C2D_CreateScreenTarget(GFXScreen.top,    GFX3DSide.left);
  C3D_RenderTarget* topRight = C2D_CreateScreenTarget(GFXScreen.top,    GFX3DSide.right);
  C3D_RenderTarget* bottom   = C2D_CreateScreenTarget(GFXScreen.bottom, GFX3DSide.left);

  osTickCounterStart(&tickCounter);

  initReadingView(&readingViewData);
  initBookView(&bookViewData);

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

    // Respond to user input
    uint kDown = hidKeysDown();
    uint kHeld = hidKeysHeld();

    touchPosition touch;
    hidTouchRead(&touch);

    circlePosition circle;
    hidCircleRead(&circle);

    input.update(kDown, kHeld, touch, circle);

    //@TODO: Probably remove for release
    if ((kHeld & (Key.start | Key.select)) == (Key.start | Key.select))
      break; // break in order to return to hbmenu

    float slider = osGet3DSliderState();
    bool  _3DEnabled = slider > 0;

    //debug printf("\x1b[6;1HTS: watermark: %4d, high: %4d\x1b[K", gTempStorage.watermark, gTempStorage.highWatermark);
    gTempStorage.reset();

    final switch (curView) {
      case View.book:
        updateBookView(&bookViewData, &input);
        break;

      case View.reading:
        updateReadingView(&readingViewData, &input);
        break;
    }


    audioUpdate();

    //debug printf("\x1b[3;1HCPU:     %6.2f%%\x1b[K", C3D_GetProcessingTime()*6.0f);
    //debug printf("\x1b[4;1HGPU:     %6.2f%%\x1b[K", C3D_GetDrawingTime()*6.0f);
    //debug printf("\x1b[5;1HCmdBuf:  %6.2f%%\x1b[K", C3D_GetCmdBufUsage()*100.0f);

    // Render the scene
    C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
    {
      final switch (curView) {
        case View.book:
          renderBookView(&bookViewData, topLeft, topRight, bottom, _3DEnabled, slider);
          break;

        case View.reading:
          renderReadingView(&readingViewData, topLeft, topRight, bottom, _3DEnabled, slider);
          break;
      }
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

void loadPage(LoadedPage* page, char[][] pageLines, float size) {
  if (!page.textArray.length) page.textArray = allocArray!C2D_Text(512);
  if (!page.textBuf)          page.textBuf   = C2D_TextBufNew(16384);

  if (page.wrapInfos.length < pageLines.length) {
    freeArray(page.wrapInfos);
    page.wrapInfos = allocArray!C2D_WrapInfo(pageLines.length);
  }
  else {
    //reuse memory if possible
    page.wrapInfos = page.wrapInfos[0..pageLines.length];
  }

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextParse(&page.textArray[lineNum], page.textBuf, pageLines[lineNum].ptr);
    page.wrapInfos[lineNum] = C2D_CalcWrapInfo(&page.textArray[lineNum], size, SCREEN_BOTTOM_WIDTH - 2 * MARGIN);
  }

  auto actualNumLines = pageLines.length;
  foreach (ref wrapInfo; page.wrapInfos) {
    actualNumLines += wrapInfo.words[$-1].newLineNumber;
  }

  float glyphWidth, glyphHeight;
  C2D_TextGetDimensions(&page.textArray[0], size, size, &glyphWidth, &glyphHeight);

  if (page.actualLineNumberTable.length < actualNumLines) {
    freeArray(page.actualLineNumberTable);
    page.actualLineNumberTable = allocArray!(LoadedPage.LineTableEntry)(actualNumLines);
  }
  else {
    //reuse memory if possible
    page.actualLineNumberTable = page.actualLineNumberTable[0..actualNumLines];
  }

  size_t runner = 0;
  foreach (i, ref wrapInfo; page.wrapInfos) {
    auto realLines = wrapInfo.words[$-1].newLineNumber + 1;

    page.actualLineNumberTable[runner..runner+realLines] = LoadedPage.LineTableEntry(i, runner * glyphHeight);

    runner += realLines;
  }

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextOptimize(&page.textArray[lineNum]);
  }
}

void unloadPage(LoadedPage* page) {
  if (page.textBuf) C2D_TextBufClear(page.textBuf);
}

enum SCREEN_TOP_WIDTH    = 400.0f;
enum SCREEN_BOTTOM_WIDTH = 320.0f;
enum SCREEN_HEIGHT       = 240.0f;

void initReadingView(ReadingViewData* viewData) {
  viewData.size = 0.5f;
  viewData.curBook = Book.Joshua;
  viewData.curChapter = 1;
  viewData.book = openBibleBook(Translation.asv, viewData.curBook);
  loadPage(&viewData.loadedPage, viewData.book.chapters[viewData.curChapter], viewData.size);
  C2D_TextGetDimensions(
    &viewData.loadedPage.textArray[0], viewData.size, viewData.size,
    &viewData.glyphWidth, &viewData.glyphHeight
  );
}

void updateReadingView(ReadingViewData* viewData, Input* input) {
  if (input.down(Key.b)) {
    curView = View.book;
    return;
  }

  int chapterDiff, bookDiff;
  if (input.down(Key.l)) {
    chapterDiff = -1;
    if (viewData.curChapter == 1 && viewData.curBook != Book.min) {
      bookDiff = -1;
    }
  }
  else if (input.down(Key.r)) {
    chapterDiff = 1;
    if (viewData.curChapter == viewData.book.chapters.length-1 && viewData.curBook != Book.max) {
      bookDiff = 1;
    }
  }

  if (bookDiff) {
    unloadPage(&viewData.loadedPage);

    closeBibleBook(&viewData.book);
    viewData.curBook = cast(Book) (viewData.curBook + bookDiff);
    viewData.book = openBibleBook(Translation.asv, viewData.curBook);

    if (bookDiff > 0) {
      viewData.curChapter = 1;
    }
    else {
      viewData.curChapter = viewData.book.chapters.length-1;
    }

    loadPage(&viewData.loadedPage, viewData.book.chapters[viewData.curChapter], viewData.size);
  }
  else if (chapterDiff) {
    unloadPage(&viewData.loadedPage);
    viewData.curChapter += chapterDiff;
    loadPage(&viewData.loadedPage, viewData.book.chapters[viewData.curChapter], viewData.size);
  }

  ////
  // update scrolling
  ////

  auto scrollDiff = input.scrollDiff();

  viewData.loadedPage.scrollOffsetLast = viewData.loadedPage.scrollOffset;

  if (input.scrollMethodCur == ScrollMethod.touch) {
    if (!input.down(Key.touch)) {
      viewData.loadedPage.scrollOffset += scrollDiff.y;
    }
  }
  else {
    viewData.loadedPage.scrollOffset += scrollDiff.y;
  }

  float scrollLimit = viewData.loadedPage.actualLineNumberTable.length * viewData.glyphHeight + MARGIN * 2 - SCREEN_HEIGHT * 2;
  if (viewData.loadedPage.scrollOffset > 0) {
    viewData.loadedPage.scrollOffset = 0;
    input.scrollVel = 0;
  }
  else if (viewData.loadedPage.scrollOffset < -scrollLimit) {
    viewData.loadedPage.scrollOffset = -scrollLimit;
    input.scrollVel = 0;
  }

  ////
  // handle scrolling events
  ////

  if ( viewData.scrollJustStopped == OneFrameEvent.not_triggered &&
       ( viewData.loadedPage.scrollOffset == 0 || viewData.loadedPage.scrollOffset == -scrollLimit ) &&
       viewData.loadedPage.scrollOffset != viewData.loadedPage.scrollOffsetLast )
  {
    viewData.scrollJustStopped = OneFrameEvent.triggered;
  }
  else if (viewData.loadedPage.scrollOffset != 0 && viewData.loadedPage.scrollOffset != -scrollLimit) {
    viewData.scrollJustStopped = OneFrameEvent.not_triggered;
  }

  if ( viewData.startedScrolling == OneFrameEvent.not_triggered &&
       input.held(Key.touch) &&
       viewData.loadedPage.scrollOffset != viewData.loadedPage.scrollOffsetLast )
  {
    viewData.startedScrolling = OneFrameEvent.triggered;
  }
  else if (!input.held(Key.touch)) {
    viewData.startedScrolling = OneFrameEvent.not_triggered;
  }

  ////
  // play sounds
  ////

  if (viewData.startedScrolling == OneFrameEvent.triggered) {
    audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_tick, 0.1);
    viewData.startedScrolling = OneFrameEvent.already_processed;
  }

  if (floor(viewData.loadedPage.scrollOffset/(viewData.glyphHeight*4)) != floor(viewData.loadedPage.scrollOffsetLast/(viewData.glyphHeight*4))) {
    audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_tick, 0.05);
  }

  if (viewData.scrollJustStopped == OneFrameEvent.triggered) {
    audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_stop, 0.1);
    viewData.scrollJustStopped = OneFrameEvent.already_processed;
  }
}

void renderReadingView(ReadingViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight, C3D_RenderTarget* bottom, bool _3DEnabled, float slider3DState) {
  C2D_TargetClear(topLeft, CLEAR_COLOR);
  C2D_SceneBegin(topLeft);

  int virtualLine = max(cast(int) floor((-round(viewData.loadedPage.scrollOffset+MARGIN))/viewData.glyphHeight), 0);
  int renderStartLine = viewData.loadedPage.actualLineNumberTable[virtualLine].textLineIndex;
  float renderStartOffset = round(viewData.loadedPage.scrollOffset +
                                  viewData.loadedPage.actualLineNumberTable[virtualLine].realPos +
                                  MARGIN);

  auto result = renderPage(
    GFXScreen.top, GFX3DSide.left, slider3DState, renderStartLine, 0, renderStartOffset, *viewData
  );

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    renderPage(
      GFXScreen.top, GFX3DSide.right, slider3DState, renderStartLine, 0, renderStartOffset, *viewData
    );
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);
  renderPage(
    GFXScreen.bottom, GFX3DSide.left, slider3DState, result.line, 0, result.offsetY, *viewData
  );
}

enum MARGIN = 8.0f;

struct RenderResult {
  int line;
  float offsetY;
}

RenderResult renderPage(GFXScreen screen, GFX3DSide side, float slider3DState, int startLine, float offsetX, float offsetY, const ref ReadingViewData viewData) {
  float width, height;

  float startX;
  if (screen == GFXScreen.top) {
    startX = offsetX + (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2 + MARGIN;
  }
  else {
    startX = offsetX + MARGIN;
  }

  C2D_TextGetDimensions(&viewData.loadedPage.textArray[0], viewData.size, viewData.size, &width, &height);

  const(char[][]) lines = viewData.book.chapters[viewData.curChapter];

  int i = max(startLine, 0);
  float extra = 0;
  while (offsetY < SCREEN_HEIGHT && i < lines.length) {
    C2D_DrawText(
      &viewData.loadedPage.textArray[i], C2D_WordWrapPrecalc, screen, startX, offsetY, 0.5f, viewData.size, viewData.size,
      &viewData.loadedPage.wrapInfos[i]
    );
    extra = height * (1 + viewData.loadedPage.wrapInfos[i].words[viewData.loadedPage.textArray[i].words-1].newLineNumber);
    offsetY += extra;
    i++;
  }

  return RenderResult(i - 1, offsetY - SCREEN_HEIGHT - extra);
}

void initBookView(BookViewData* viewData) {
  viewData.textBuf = C2D_TextBufNew(4096);
  viewData.textArray = allocArray!C2D_Text(128);

  foreach (i, name; BOOK_NAMES) {
    Button* btn = &viewData.bookButtons[i];

    btn.text = &viewData.textArray[i];
    C2D_TextParse(btn.text, viewData.textBuf, name.ptr);
    float textWidth, textHeight;
    C2D_TextGetDimensions(btn.text, 0.5, 0.5, &textWidth, &textHeight);
    btn.x = 100;
    btn.y = i*(textHeight+24);
    btn.w = textWidth + 16;
    btn.h = textHeight + 16;
  }
}

int curBookButton = -1;

void updateBookView(BookViewData* viewData, Input* input) {
  if (input.down(Key.touch)) {

    foreach (i, ref btn; viewData.bookButtons) {
      float btnRealY = btn.y + viewData.scrollOffset;

      if (btnRealY + btn.h > 0 || btnRealY < SCREEN_HEIGHT) {
        if ( input.touchRaw.px >= btn.x    && input.touchRaw.px <= btn.x    + btn.w &&
             input.touchRaw.py >= btnRealY && input.touchRaw.py <= btnRealY + btn.h )
        {
          curBookButton = i;
          break;
        }
      }
    }

  }
  else if (!input.held(Key.touch) && input.prevHeld(Key.touch)) {
    if (curBookButton != -1) {
      Button* btn = &viewData.bookButtons[curBookButton];
      float btnRealY = btn.y + viewData.scrollOffset;

      if ( input.prevTouchRaw.px >= btn.x    && input.prevTouchRaw.px <= btn.x    + btn.w &&
           input.prevTouchRaw.py >= btnRealY && input.prevTouchRaw.py <= btnRealY + btn.h )
      {
        unloadPage(&readingViewData.loadedPage);
        closeBibleBook(&readingViewData.book);
        readingViewData.curBook = cast(Book) curBookButton;
        readingViewData.book = openBibleBook(Translation.asv, readingViewData.curBook);
        readingViewData.curChapter = 1;
        loadPage(&readingViewData.loadedPage, readingViewData.book.chapters[readingViewData.curChapter], 0.5);
        curView = View.reading;
      }
      curBookButton = -1;
    }
  }

  viewData.scrollOffsetLast = viewData.scrollOffset;

  if (curBookButton == -1) {
    auto scrollDiff = input.scrollDiff();

    if (input.scrollMethodCur == ScrollMethod.touch) {
      if (!input.down(Key.touch)) {
        viewData.scrollOffset += scrollDiff.y;
      }
    }
    else {
      viewData.scrollOffset += scrollDiff.y;
    }
  }
  else {
    input.scrollVel = 0;
  }
}

void renderBookView(BookViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight, C3D_RenderTarget* bottom, bool _3DEnabled, float slider3DState) {
  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);


  foreach (i, ref btn; viewData.bookButtons) {
    float btnRealY = btn.y + viewData.scrollOffset;

    if (btnRealY + btn.h > 0 || btnRealY < SCREEN_HEIGHT) {
      C2D_DrawRectSolid(btn.x, btnRealY, 0.0, btn.w, btn.h, 0xFFFF0000);

      C2D_DrawText(
        &viewData.textArray[i], 0, GFXScreen.top, btn.x+8, btn.y+8 + viewData.scrollOffset, 0.5f, 0.5, 0.5
      );
    }
  }

}