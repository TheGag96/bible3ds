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

struct ScrollInfo {
  float scrollOffset = 0, scrollOffsetLast = 0;
  OneFrameEvent startedScrolling;
  OneFrameEvent scrollJustStopped;
}

struct LoadedPage {
  C2D_TextBuf textBuf;
  C2D_Text[] textArray;

  C2D_WrapInfo[] wrapInfos;

  static struct LineTableEntry {
    uint textLineIndex;
    float realPos = 0;
  }
  LineTableEntry[] actualLineNumberTable;

  ScrollInfo scrollInfo;
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

  ScrollInfo scrollInfo;
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

    updateInput(&input, kDown, kHeld, touch, circle);

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

void loadPage(LoadedPage* page, char[][] pageLines, float size) { with (page) {
  if (!textArray.length) textArray = allocArray!C2D_Text(512);
  if (!textBuf)          textBuf   = C2D_TextBufNew(16384);

  if (wrapInfos.length < pageLines.length) {
    freeArray(wrapInfos);
    wrapInfos = allocArray!C2D_WrapInfo(pageLines.length);
  }
  else {
    //reuse memory if possible
    wrapInfos = wrapInfos[0..pageLines.length];
  }

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextParse(&textArray[lineNum], textBuf, pageLines[lineNum].ptr);
    wrapInfos[lineNum] = C2D_CalcWrapInfo(&textArray[lineNum], size, SCREEN_BOTTOM_WIDTH - 2 * MARGIN);
  }

  auto actualNumLines = pageLines.length;
  foreach (ref wrapInfo; wrapInfos) {
    actualNumLines += wrapInfo.words[$-1].newLineNumber;
  }

  float glyphWidth, glyphHeight;
  C2D_TextGetDimensions(&textArray[0], size, size, &glyphWidth, &glyphHeight);

  if (actualLineNumberTable.length < actualNumLines) {
    freeArray(actualLineNumberTable);
    actualLineNumberTable = allocArray!(LoadedPage.LineTableEntry)(actualNumLines);
  }
  else {
    //reuse memory if possible
    actualLineNumberTable = actualLineNumberTable[0..actualNumLines];
  }

  size_t runner = 0;
  foreach (i, ref wrapInfo; wrapInfos) {
    auto realLines = wrapInfo.words[$-1].newLineNumber + 1;

    actualLineNumberTable[runner..runner+realLines] = LoadedPage.LineTableEntry(i, runner * glyphHeight);

    runner += realLines;
  }

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextOptimize(&textArray[lineNum]);
  }
}}

void unloadPage(LoadedPage* page) { with (page) {
  if (textBuf) C2D_TextBufClear(textBuf);
}}

void handleScroll(ScrollInfo* scrollInfo, Input* input, float limitTop, float limitBottom) { with (scrollInfo) {
  enum SCROLL_TICK_DISTANCE = 60;

  auto scrollDiff = updateScrollDiff(input);

  scrollOffsetLast = scrollOffset;

  if (input.scrollMethodCur == ScrollMethod.touch) {
    if (!input.down(Key.touch)) {
      scrollOffset += scrollDiff.y;
    }
  }
  else {
    scrollOffset += scrollDiff.y;
  }

  if (scrollOffset > limitTop) {
    scrollOffset = limitTop;
    input.scrollVel = 0;
  }
  else if (scrollOffset < -limitBottom) {
    scrollOffset = -limitBottom;
    input.scrollVel = 0;
  }


  ////
  // handle scrolling events
  ////

  if ( scrollJustStopped == OneFrameEvent.not_triggered &&
       ( scrollOffset == limitTop || scrollOffset == -limitBottom ) &&
       scrollOffset != scrollOffsetLast )
  {
    scrollJustStopped = OneFrameEvent.triggered;
  }
  else if (scrollOffset != limitTop && scrollOffset != -limitBottom) {
    scrollJustStopped = OneFrameEvent.not_triggered;
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
    audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_tick, 0.1);
    startedScrolling = OneFrameEvent.already_processed;
  }

  if (floor(scrollOffset/SCROLL_TICK_DISTANCE) != floor(scrollOffsetLast/SCROLL_TICK_DISTANCE)) {
    audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_tick, 0.05);
  }

  if (scrollJustStopped == OneFrameEvent.triggered) {
    audioPlaySound(SoundSlot.scrolling, SoundEffect.scroll_stop, 0.1);
    scrollJustStopped = OneFrameEvent.already_processed;
  }
}}

enum SCREEN_TOP_WIDTH    = 400.0f;
enum SCREEN_BOTTOM_WIDTH = 320.0f;
enum SCREEN_HEIGHT       = 240.0f;

void initReadingView(ReadingViewData* viewData) { with (viewData) {
  size = 0.5f;
  curBook = Book.Joshua;
  curChapter = 1;
  book = openBibleBook(Translation.asv, curBook);
  loadPage(&loadedPage, book.chapters[curChapter], size);
  C2D_TextGetDimensions(
    &loadedPage.textArray[0], size, size,
    &glyphWidth, &glyphHeight
  );
}}

void updateReadingView(ReadingViewData* viewData, Input* input) { with (viewData) {
  if (input.down(Key.b)) {
    curView = View.book;
    return;
  }

  int chapterDiff, bookDiff;
  if (input.down(Key.l)) {
    chapterDiff = -1;
    if (curChapter == 1 && curBook != Book.min) {
      bookDiff = -1;
    }
  }
  else if (input.down(Key.r)) {
    chapterDiff = 1;
    if (curChapter == book.chapters.length-1 && curBook != Book.max) {
      bookDiff = 1;
    }
  }

  if (bookDiff) {
    unloadPage(&loadedPage);

    closeBibleBook(&book);
    curBook = cast(Book) (curBook + bookDiff);
    book = openBibleBook(Translation.asv, curBook);

    if (bookDiff > 0) {
      curChapter = 1;
    }
    else {
      curChapter = book.chapters.length-1;
    }

    loadPage(&loadedPage, book.chapters[curChapter], size);
  }
  else if (chapterDiff) {
    unloadPage(&loadedPage);
    curChapter += chapterDiff;
    loadPage(&loadedPage, book.chapters[curChapter], size);
  }


  ////
  // update scrolling
  ////

  float scrollLimit = loadedPage.actualLineNumberTable.length * glyphHeight + MARGIN * 2 - SCREEN_HEIGHT * 2;
  handleScroll(&loadedPage.scrollInfo, input, 0, scrollLimit);
}}

void renderReadingView(
  ReadingViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight,
  C3D_RenderTarget* bottom, bool _3DEnabled, float slider3DState
) { with (viewData) {
  C2D_TargetClear(topLeft, CLEAR_COLOR);
  C2D_SceneBegin(topLeft);

  int virtualLine = max(cast(int) floor((-round(loadedPage.scrollInfo.scrollOffset+MARGIN))/glyphHeight), 0);
  int renderStartLine = loadedPage.actualLineNumberTable[virtualLine].textLineIndex;
  float renderStartOffset = round(loadedPage.scrollInfo.scrollOffset +
                                  loadedPage.actualLineNumberTable[virtualLine].realPos +
                                  MARGIN);

  auto result = renderPage(
    *viewData, GFXScreen.top, GFX3DSide.left, slider3DState, renderStartLine, 0, renderStartOffset
  );

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    renderPage(
      *viewData, GFXScreen.top, GFX3DSide.right, slider3DState, renderStartLine, 0, renderStartOffset
    );
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);
  renderPage(
    *viewData, GFXScreen.bottom, GFX3DSide.left, slider3DState, result.line, 0, result.offsetY
  );
}}

enum MARGIN = 8.0f;

struct RenderResult {
  int line;
  float offsetY;
}

RenderResult renderPage(
  in ReadingViewData viewData, GFXScreen screen, GFX3DSide side, float slider3DState, int startLine,
  float offsetX, float offsetY
) { with (viewData) {
  float width, height;

  float startX;
  if (screen == GFXScreen.top) {
    startX = offsetX + (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2 + MARGIN;
  }
  else {
    startX = offsetX + MARGIN;
  }

  C2D_TextGetDimensions(&loadedPage.textArray[0], size, size, &width, &height);

  const(char[][]) lines = book.chapters[curChapter];

  int i = max(startLine, 0);
  float extra = 0;
  while (offsetY < SCREEN_HEIGHT && i < lines.length) {
    C2D_DrawText(
      &loadedPage.textArray[i], C2D_WordWrapPrecalc, screen, startX, offsetY, 0.5f, size, size,
      &loadedPage.wrapInfos[i]
    );
    extra = height * (1 + loadedPage.wrapInfos[i].words[loadedPage.textArray[i].words-1].newLineNumber);
    offsetY += extra;
    i++;
  }

  return RenderResult(i - 1, offsetY - SCREEN_HEIGHT - extra);
}}

void initBookView(BookViewData* viewData) { with (viewData) {
  textBuf = C2D_TextBufNew(4096);
  textArray = allocArray!C2D_Text(128);

  foreach (i, name; BOOK_NAMES) {
    Button* btn = &bookButtons[i];

    btn.text = &textArray[i];
    C2D_TextParse(btn.text, textBuf, name.ptr);
    float textWidth, textHeight;
    C2D_TextGetDimensions(btn.text, 0.5, 0.5, &textWidth, &textHeight);
    btn.x = 100;
    btn.y = i*(textHeight+24);
    btn.w = textWidth + 16;
    btn.h = textHeight + 16;
  }
}}

int curBookButton = -1;

void updateBookView(BookViewData* viewData, Input* input) { with (viewData) {
  if (input.down(Key.touch)) {

    foreach (i, ref btn; bookButtons) {
      float btnRealY = btn.y + scrollInfo.scrollOffset;

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
      Button* btn = &bookButtons[curBookButton];
      float btnRealY = btn.y + scrollInfo.scrollOffset;

      if ( input.prevTouchRaw.px >= btn.x    && input.prevTouchRaw.px <= btn.x    + btn.w &&
           input.prevTouchRaw.py >= btnRealY && input.prevTouchRaw.py <= btnRealY + btn.h )
      {
        with (readingViewData) {
          unloadPage(&loadedPage);
          closeBibleBook(&book);
          curBook = cast(Book) curBookButton;
          book = openBibleBook(Translation.asv, curBook);
          curChapter = 1;
          loadPage(&loadedPage, book.chapters[curChapter], 0.5);
          curView = View.reading;
        }
      }
      curBookButton = -1;
    }
  }

  if (curBookButton == -1) {
    handleScroll(&scrollInfo, input, 0, bookButtons[$-1].y+bookButtons[$-1].h - SCREEN_HEIGHT);
  }
  else {
    scrollInfo.scrollOffsetLast = scrollInfo.scrollOffset;
    input.scrollVel = 0;
  }
}}

void renderBookView(
  BookViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight, C3D_RenderTarget* bottom,
  bool _3DEnabled, float slider3DState
) { with (viewData) {
  void renderButtons(float offsetX, float offsetY) {
    foreach (i, ref btn; bookButtons) {
      float btnRealX = btn.x + offsetX, btnRealY = btn.y + offsetY;

      if (btnRealY + btn.h < 0) {
      }
      else if (btnRealY > SCREEN_HEIGHT){
        break;
      }
      else {
        C2D_DrawRectSolid(btnRealX, btnRealY, 0.0, btn.w, btn.h, 0xFFFF0000);

        C2D_DrawText(
          &textArray[i], 0, GFXScreen.top, btnRealX+8, btn.y+8 + offsetY, 0.5f, 0.5, 0.5
        );
      }
    }
  }

  C2D_TargetClear(topLeft, CLEAR_COLOR);
  C2D_SceneBegin(topLeft);
  renderButtons((SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2, scrollInfo.scrollOffset + SCREEN_HEIGHT);

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    renderButtons((SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH) / 2, scrollInfo.scrollOffset + SCREEN_HEIGHT);
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);
  renderButtons(0, scrollInfo.scrollOffset);
}}