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

enum SCREEN_TOP_WIDTH    = 400.0f;
enum SCREEN_BOTTOM_WIDTH = 320.0f;

float screenWidth(GFXScreen screen) { return screen == GFXScreen.top ? SCREEN_TOP_WIDTH : SCREEN_BOTTOM_WIDTH; }

enum SCREEN_HEIGHT       = 240.0f;

struct ScrollInfo {
  float scrollOffset = 0, scrollOffsetLast = 0;
  float limitTop = 0, limitBottom = 0;
  OneFrameEvent startedScrolling;
  OneFrameEvent scrollJustStopped;
  bool pushingAgainstLimit;
  int pushingAgainstTimer;
  enum PUSHING_AGAINST_TIMER_MAX = 10;
}

struct ScrollCache {
  C3D_Tex scrollTex;
  C3D_RenderTarget* scrollTarget;
  float desiredWidth = 0, desiredHeight = 0, texWidth = 0, texHeight = 0;

  bool needsRepaint;
  int u_scrollRenderOffset; // location of uniform from scroll_cache.v.pica
  ubyte curStencilVal;
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
  int id;
  float x = 0, y = 0, w = 0, h = 0;
  C2D_Text* text;
  float textW, textH;
}

struct UiState {
  int buttonHovered, buttonHoveredLast;
  int buttonHeld, buttonHeldLast;
}

struct BookViewData {
  C2D_TextBuf textBuf;
  C2D_Text[] textArray;

  enum BookButton {
    none = -1,
    genesis = Book.min,
    revelation = Book.max,
    options
  }

  Button[Book.max+1] bookButtons;
  Button optionsBtn;

  ScrollInfo scrollInfo;

  UiState uiState;
  Book chosenBook;
}

enum OneFrameEvent {
  not_triggered, triggered, already_processed,
}

struct ReadingViewData {
  C2D_TextBuf textBuf;
  C2D_Text[] textArray;

  float size = 0;
  float glyphWidth = 0, glyphHeight = 0;

  OpenBook book;
  Book curBook;
  LoadedPage loadedPage;
  int curChapter;

  Button backBtn;
}


enum CLEAR_COLOR = 0xFFEEEEEE;

struct MainData {
  ScrollCache scrollCache;
  C3D_Tex vignetteTex, lineTex; //@TODO: Move somewhere probably
}
MainData mainData;

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

  enum SCROLL_CACHE_WIDTH  = cast(ushort) SCREEN_BOTTOM_WIDTH,
       SCROLL_CACHE_HEIGHT = cast(ushort) (2*SCREEN_HEIGHT);

  mainData.scrollCache = scrollCacheCreate(SCROLL_CACHE_WIDTH, SCROLL_CACHE_HEIGHT);

  initReadingView(&readingViewData);
  initBookView(&bookViewData);

  with (mainData) {
    // Load the textures and bind them to their respective texture units
    if (!loadTextureFromFile(&vignetteTex, null, "romfs:/gfx/vignette.t3x"))
      svcBreak(UserBreakType.panic);
    if (!loadTextureFromFile(&lineTex, null, "romfs:/gfx/line.t3x"))
      svcBreak(UserBreakType.panic);
    C3D_TexSetFilter(&vignetteTex, GPUTextureFilterParam.linear, GPUTextureFilterParam.linear);
    C3D_TexSetFilter(&lineTex, GPUTextureFilterParam.linear, GPUTextureFilterParam.linear);
    C3D_TexBind(1, &vignetteTex);
    C3D_TexSetWrap(&vignetteTex, GPUTextureWrapParam.mirrored_repeat, GPUTextureWrapParam.mirrored_repeat);
    C3D_TexBind(0, &lineTex);
    C3D_TexSetWrap(&lineTex, GPUTextureWrapParam.repeat, GPUTextureWrapParam.repeat);
    C3D_TexBind(0, &lineTex);
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

    View updateResult = curView;

    final switch (curView) {
      case View.book:
        updateResult = updateBookView(&bookViewData, &input);

        if (curView != updateResult) {
          with (readingViewData) {
            unloadPage(&loadedPage);
            closeBibleBook(&book);
            curBook = cast(Book) bookViewData.chosenBook;
            book = openBibleBook(Translation.asv, curBook);
            curChapter = 1;
            loadPage(&loadedPage, book.chapters[curChapter], 0.5);
            curView = View.reading;
            resetScrollDiff(&input);
            mainData.scrollCache.needsRepaint = true;
          }
        }
        break;

      case View.reading:
        updateResult = updateReadingView(&readingViewData, &input);

        if (curView != updateResult) {
          curView = updateResult;
          resetScrollDiff(&input);
          mainData.scrollCache.needsRepaint = true;
        }
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

  page.scrollInfo = ScrollInfo.init;

  mainData.scrollCache.needsRepaint = true;
}}

void unloadPage(LoadedPage* page) { with (page) {
  if (textBuf) C2D_TextBufClear(textBuf);
}}

void handleScroll(ScrollInfo* scrollInfo, Input* input, float newLimitTop, float newLimitBottom) { with (scrollInfo) {
  enum SCROLL_TICK_DISTANCE = 60;

  auto scrollDiff = updateScrollDiff(input);

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

void initReadingView(ReadingViewData* viewData) { with (viewData) {
  textBuf   = C2D_TextBufNew(192);
  textArray = allocArray!C2D_Text(128);

  size = 0.5f;
  curBook = Book.Joshua;
  curChapter = 1;
  book = openBibleBook(Translation.asv, curBook);
  loadPage(&loadedPage, book.chapters[curChapter], size);
  C2D_TextGetDimensions(
    &loadedPage.textArray[0], size, size,
    &glyphWidth, &glyphHeight
  );

  float textWidth, textHeight;
  auto text = &textArray[0];
  C2D_TextParse(text, textBuf, "Back");
  C2D_TextGetDimensions(text, 0.5, 0.5, &textWidth, &textHeight);
  auto buttonHeight = textHeight + 2*BOTTOM_BUTTON_MARGIN;
  backBtn = Button(0, 0, SCREEN_HEIGHT - buttonHeight, SCREEN_BOTTOM_WIDTH, buttonHeight, text, textWidth, textHeight);

  char[3] buf = 0;
  foreach (i; 1..85) {
    snprintf(buf.ptr, buf.length, "%d", i);
    C2D_TextParse(&textArray[i], textBuf, buf.ptr);
  }
}}

View updateReadingView(ReadingViewData* viewData, Input* input) { with (viewData) {
  if (input.down(Key.b)) {
    audioPlaySound(SoundSlot.button, SoundEffect.button_back, 0.5);
    return View.book;
  }

  int chapterDiff, bookDiff;
  if (input.down(Key.l)) {
    if (curChapter == 1) {
      if (curBook != Book.min) {
        bookDiff = -1;
      }
    }
    else {
      chapterDiff = -1;
    }
  }
  else if (input.down(Key.r)) {
    if (curChapter == book.chapters.length-1) {
      if (curBook != Book.max) {
        bookDiff = 1;
      }
    }
    else {
      chapterDiff = 1;
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

  float scrollLimit = max(loadedPage.actualLineNumberTable.length * glyphHeight + MARGIN * 2 - SCREEN_HEIGHT * 2, 0)
                      + backBtn.textH + 2*BOTTOM_BUTTON_MARGIN;
  handleScroll(&loadedPage.scrollInfo, input, 0, scrollLimit);

  return View.reading;
}}

void renderReadingView(
  ReadingViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight,
  C3D_RenderTarget* bottom, bool _3DEnabled, float slider3DState
) { with (viewData) {
  scrollCacheBeginFrame(&mainData.scrollCache);
  scrollCacheRenderScrollUpdate(
    &mainData.scrollCache,
    loadedPage.scrollInfo,
    &renderPage, viewData,
    CLEAR_COLOR,
  );
  scrollCacheEndFrame(&mainData.scrollCache);

  C2D_TargetClear(topLeft, CLEAR_COLOR);
  C2D_SceneBegin(topLeft);

  Tex3DS_SubTexture subtexTop    = scrollCacheGetUvs(mainData.scrollCache, SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, 0,             loadedPage.scrollInfo.scrollOffset);
  Tex3DS_SubTexture subtexBottom = scrollCacheGetUvs(mainData.scrollCache, SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, SCREEN_HEIGHT, loadedPage.scrollInfo.scrollOffset);
  C2D_Image cacheImageTop    = { &mainData.scrollCache.scrollTex, &subtexTop };
  C2D_Image cacheImageBottom = { &mainData.scrollCache.scrollTex, &subtexBottom };
  C2D_Sprite sprite;
  C2D_SpriteFromImage(&sprite, cacheImageTop);

  C2D_SpriteSetPos(&sprite, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2, 0);
  C2D_DrawSprite(&sprite);
  renderScrollIndicator(loadedPage.scrollInfo, SCREEN_BOTTOM_WIDTH + (SCREEN_TOP_WIDTH-SCREEN_BOTTOM_WIDTH)/2, 0, SCREEN_HEIGHT, mainData.scrollCache.desiredHeight);

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    C2D_DrawSprite(&sprite);
    renderScrollIndicator(loadedPage.scrollInfo, SCREEN_BOTTOM_WIDTH + (SCREEN_TOP_WIDTH-SCREEN_BOTTOM_WIDTH)/2, 0, SCREEN_HEIGHT, mainData.scrollCache.desiredHeight);
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);

  C2D_SpriteFromImage(&sprite, cacheImageBottom);
  C2D_SpriteSetPos(&sprite, 0, 0);
  C2D_DrawSprite(&sprite);

  auto centerX = backBtn.x + backBtn.w/2 - backBtn.textW/2;
  auto centerY = backBtn.y + backBtn.h/2 - backBtn.textH/2;
  C2D_DrawRectSolid(backBtn.x, backBtn.y, 0.55f, backBtn.w, backBtn.h, /* i == buttonHeld ? BOTTOM_BUTTON_DOWN_COLOR : */ BOTTOM_BUTTON_COLOR);
  C2D_DrawText(
    backBtn.text, C2D_WithColor, GFXScreen.bottom, centerX, centerY, 0.6f, 0.5, 0.5, C2D_Color32(0x11, 0x11, 0x11, 255)
  );
}}

enum MARGIN = 8.0f;
enum BOOK_BUTTON_WIDTH = 200.0f;
enum BOOK_BUTTON_MARGIN = 8.0f;
enum BOTTOM_BUTTON_MARGIN = 6.0f;
enum BOTTOM_BUTTON_COLOR = C2D_Color32(0xCC, 0xCC, 0xCC, 0xFF);

void renderPage(
  ReadingViewData* viewData, float from, float to
) { with (viewData) {
  float width, height;

  float startX = MARGIN;

  C2D_TextGetDimensions(&loadedPage.textArray[0], size, size, &width, &height);

  const(char[][]) lines = book.chapters[curChapter];

  //float renderStartOffset = round(loadedPage.scrollInfo.scrollOffset +
  //                                loadedPage.actualLineNumberTable[virtualLine].realPos +
  //                                MARGIN);

  int virtualLine = min(max(cast(int) floor((round(from-MARGIN))/glyphHeight), 0), cast(int)loadedPage.actualLineNumberTable.length-1);
  int startLine = loadedPage.actualLineNumberTable[virtualLine].textLineIndex;
  float offsetY = loadedPage.actualLineNumberTable[virtualLine].realPos + MARGIN;

  float extra = 0;
  int i = startLine; //max(startLine, 0);
  while (offsetY < to && i < lines.length) {
    C2D_DrawText(
      &loadedPage.textArray[i], C2D_WordWrapPrecalc, GFXScreen.bottom, startX, offsetY, 0.5f, size, size,
      &loadedPage.wrapInfos[i]
    );
    extra = height * (1 + loadedPage.wrapInfos[i].words[loadedPage.textArray[i].words-1].newLineNumber);
    offsetY += extra;
    i++;
  }
}}

void initBookView(BookViewData* viewData) { with (viewData) {
  textBuf = C2D_TextBufNew(4096);
  textArray = allocArray!C2D_Text(128);

  foreach (i, name; BOOK_NAMES) {
    Button* btn = &bookButtons[i];

    btn.id = i;
    btn.text = &textArray[i];
    C2D_TextParse(btn.text, textBuf, name.ptr);
    C2D_TextGetDimensions(btn.text, 0.5, 0.5, &btn.textW, &btn.textH);
    btn.x = SCREEN_BOTTOM_WIDTH/2 - BOOK_BUTTON_WIDTH/2;
    btn.y = i*(btn.textH+24) + SCREEN_HEIGHT;
    btn.w = BOOK_BUTTON_WIDTH;
    btn.h = btn.textH + 2*BOOK_BUTTON_MARGIN;
  }

  float textWidth, textHeight;
  auto text = &textArray[BOOK_NAMES.length+1];
  C2D_TextParse(text, textBuf, "Options");
  C2D_TextGetDimensions(text, 0.5, 0.5, &textWidth, &textHeight);
  auto buttonHeight = textHeight + 2*BOTTOM_BUTTON_MARGIN;
  optionsBtn = Button(BookButton.options, 0, SCREEN_HEIGHT - buttonHeight, SCREEN_BOTTOM_WIDTH, buttonHeight, text, textWidth, textHeight);

  uiState.buttonHeld    = BookButton.none;
  uiState.buttonHovered = BookButton.none;
}}

View updateBookView(BookViewData* viewData, Input* input) { with (viewData) {
  View retVal = View.book;

  uiState.buttonHeldLast = uiState.buttonHeld;
  uiState.buttonHoveredLast = uiState.buttonHovered;

  static bool handleButton(in Button btn, in Input input, in ScrollInfo scrollInfo, UiState* uiState, bool withinScrollable = false) {
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
          audioPlaySound(SoundSlot.button, SoundEffect.button_down, 0.25);
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
        audioPlaySound(SoundSlot.button, SoundEffect.button_down, 0.25);
      }
      else if (uiState.buttonHoveredLast == btn.id && uiState.buttonHovered == -1) {
        if (result) {
          audioPlaySound(SoundSlot.button, SoundEffect.button_confirm, 0.5);
        }
        else {
          audioPlaySound(SoundSlot.button, SoundEffect.button_off, 0.25);
        }
      }
    }

    return result;
  }

  if (handleButton(optionsBtn, *input, scrollInfo, &uiState, false)) {
    //
  }

  foreach (i, ref btn; bookButtons) {
    if (handleButton(btn, *input, scrollInfo, &uiState, true)) {
      retVal = View.reading;
      chosenBook = cast(Book) uiState.buttonHeldLast;
    }
  }

  if (uiState.buttonHeld == BookButton.none) {
    handleScroll(&scrollInfo, input, 0, bookButtons[$-1].y+bookButtons[$-1].h - SCREEN_HEIGHT + optionsBtn.textH + 2*BOTTOM_BUTTON_MARGIN);
  }
  else {
    scrollInfo.scrollOffsetLast = scrollInfo.scrollOffset;
    input.scrollVel = 0;
  }

  return retVal;
}}

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

void renderBookView(
  BookViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight, C3D_RenderTarget* bottom,
  bool _3DEnabled, float slider3DState
) { with (viewData) {
  enum BOOK_BUTTON_COLOR      = C2D_Color32(0x00, 0x00, 0xFF, 0xFF);
  enum BOOK_BUTTON_DOWN_COLOR = C2D_Color32(0x55, 0x55, 0xFF, 0xFF);
  static immutable ButtonStyle BOOK_BUTTON_STYLE = {
    colorText     : C2D_Color32(255, 255, 255, 255),
    colorBg       : BOOK_BUTTON_COLOR,
    colorBgHeld   : BOOK_BUTTON_DOWN_COLOR,
    margin        : BOOK_BUTTON_MARGIN,
    textSize      : 0.5f,
    justification : Justification.left_justified,
  };

  static immutable ButtonStyle BOTTOM_BUTTON_STYLE = {
    colorText     : C2D_Color32(0x11, 0x11, 0x11, 255),
    colorBg       : BOTTOM_BUTTON_COLOR,
    colorBgHeld   : BOOK_BUTTON_DOWN_COLOR,
    margin        : BOTTOM_BUTTON_MARGIN,
    textSize      : 0.5f,
    justification : Justification.centered,
  };

  static void renderButton(in Button btn, in UiState uiState, in ButtonStyle style) {
    bool pressed = btn.id == uiState.buttonHeld && btn.id == uiState.buttonHovered;
    float btnRealX = btn.x, btnRealY = btn.y + pressed * 3;

    C2D_DrawRectSolid(btnRealX, btnRealY, 0.0, btn.w, btn.h, pressed ? style.colorBgHeld : style.colorBg);

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
      btn.text, C2D_WithColor, GFXScreen.top, textX, textY, 0.5f, style.textSize, style.textSize, style.colorText
    );
  }

  static void renderBookButtons(
    BookViewData* viewData, float from, float to
  ) { with (viewData) {

    foreach (i, ref btn; bookButtons) {
      if (btn.y + btn.h < from) {
      }
      else if (btn.y > to){
        break;
      }
      else {
        renderButton(btn, uiState, BOOK_BUTTON_STYLE);
      }
    }
  }}


  scrollCacheBeginFrame(&mainData.scrollCache);
  scrollCacheRenderScrollUpdate(
    &mainData.scrollCache,
    scrollInfo,
    &renderBookButtons, viewData,
  );

  if (uiState.buttonHeld != -1 || uiState.buttonHeldLast != -1) {
    auto btnId = uiState.buttonHeld == -1 ? uiState.buttonHeldLast : uiState.buttonHeld;

    if (btnId >= BookButton.genesis && btnId <= BookButton.revelation) {
      Button* btn = &bookButtons[btnId];

      scrollCacheRenderRegion(
        &mainData.scrollCache,
        btn.y-4, btn.y+btn.h+4,
        &renderBookButtons, viewData,
      );
    }
  }
  scrollCacheEndFrame(&mainData.scrollCache);

  C2D_TargetClear(topLeft, CLEAR_COLOR);
  C2D_SceneBegin(topLeft);

  auto colorBg           = C2D_Color32(0xF5, 0xF5, 0xF5, 255);
  auto colorStripesDark  = C2D_Color32(208,  208,  212,  255);
  auto colorStripesLight = C2D_Color32(197,  197,  189,  255);

  drawBackground(GFXScreen.top, &mainData.vignetteTex, &mainData.lineTex, colorBg, colorStripesDark, colorStripesLight);

  Tex3DS_SubTexture subtexTop    = scrollCacheGetUvs(mainData.scrollCache, SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, 0,             scrollInfo.scrollOffset);
  Tex3DS_SubTexture subtexBottom = scrollCacheGetUvs(mainData.scrollCache, SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, SCREEN_HEIGHT, scrollInfo.scrollOffset);
  C2D_Image cacheImageTop    = { &mainData.scrollCache.scrollTex, &subtexTop };
  C2D_Image cacheImageBottom = { &mainData.scrollCache.scrollTex, &subtexBottom };
  C2D_Sprite sprite;
  C2D_SpriteFromImage(&sprite, cacheImageTop);

  C2D_SpriteSetPos(&sprite, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2, 0);
  C2D_DrawSprite(&sprite);
  renderScrollIndicator(scrollInfo, SCREEN_TOP_WIDTH, 0, SCREEN_HEIGHT, mainData.scrollCache.desiredHeight, true);

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    drawBackground(GFXScreen.top, &mainData.vignetteTex, &mainData.lineTex, colorBg, colorStripesDark, colorStripesLight);

    C2D_DrawSprite(&sprite);
    renderScrollIndicator(scrollInfo, SCREEN_TOP_WIDTH, 0, SCREEN_HEIGHT, mainData.scrollCache.desiredHeight, true);
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);

  drawBackground(GFXScreen.bottom, &mainData.vignetteTex, &mainData.lineTex, colorBg, colorStripesDark, colorStripesLight);

  C2D_SpriteFromImage(&sprite, cacheImageBottom);
  C2D_DrawSprite(&sprite);

  renderButton(optionsBtn, uiState, BOTTOM_BUTTON_STYLE);
}}

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

void _scrollCacheRenderScrollUpdateImpl(
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

//fmod doesn't handle negatives the way you'd expect, so we need this instead
float wrap(float x, float mod) {
  import core.stdc.math : floor;
  return x - mod * floor(x/mod);
}

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
  C2D_Prepare(C2DShader.normal);

  env = C3D_GetTexEnv(2);
  C3D_TexEnvInit(env);
}

// Helper function for loading a texture from memory
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