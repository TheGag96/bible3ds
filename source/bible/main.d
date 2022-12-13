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

struct ScrollCache {
  C3D_Tex scrollTex;
  C3D_RenderTarget* scrollTarget;
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
  float x = 0, y = 0, w = 0, h = 0;
  C2D_Text* text;
  float textW, textH;
}

struct BookViewData {
  C2D_TextBuf textBuf;
  C2D_Text[] textArray;

  Button[Book.max+1] bookButtons;
  Button optionsBtn;

  ScrollInfo scrollInfo;
  int curBookButton, curBookButtonLast;
  int chosenBook;
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

  with (mainData.scrollCache) {
    C3D_TexInitVRAM(&scrollTex, SCROLL_WIDTH, SCROLL_HEIGHT, GPUTexColor.rgba8);
    C3D_TexSetWrap(&scrollTex, GPUTextureWrapParam.repeat, GPUTextureWrapParam.repeat);
    scrollTarget = C3D_RenderTargetCreateFromTex(&scrollTex, GPUTexFace.texface_2d, 0, C3D_DEPTHTYPE(GPUDepthBuf.depth24_stencil8));
    u_scrollRenderOffset = C2D_ShaderGetUniformLocation(C2DShader.scroll_cache, GPUShaderType.vertex_shader, "scrollRenderOffset");
  }

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

  if (scrollOffset > -limitTop) {
    scrollOffset = -limitTop;
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
       ( scrollOffset == -limitTop || scrollOffset == -limitBottom ) &&
       scrollOffset != scrollOffsetLast )
  {
    scrollJustStopped = OneFrameEvent.triggered;
  }
  else if (scrollOffset != -limitTop && scrollOffset != -limitBottom) {
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
enum SCROLL_WIDTH = 512, SCROLL_HEIGHT = 512;

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
  backBtn = Button(0, SCREEN_HEIGHT - buttonHeight, SCREEN_BOTTOM_WIDTH, buttonHeight, text, textWidth, textHeight);

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
    SCREEN_BOTTOM_WIDTH,
  );
  scrollCacheEndFrame(&mainData.scrollCache);

  C2D_TargetClear(topLeft, CLEAR_COLOR);
  C2D_SceneBegin(topLeft);

  Tex3DS_SubTexture subtexTop    = setUvs(SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, 0,             loadedPage.scrollInfo.scrollOffset);
  Tex3DS_SubTexture subtexBottom = setUvs(SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, SCREEN_HEIGHT, loadedPage.scrollInfo.scrollOffset);
  C2D_Image cacheImageTop    = { &mainData.scrollCache.scrollTex, &subtexTop };
  C2D_Image cacheImageBottom = { &mainData.scrollCache.scrollTex, &subtexBottom };
  C2D_Sprite sprite;
  C2D_SpriteFromImage(&sprite, cacheImageTop);

  C2D_SpriteSetPos(&sprite, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2, 0);
  C2D_DrawSprite(&sprite);

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    C2D_DrawSprite(&sprite);
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);

  C2D_SpriteFromImage(&sprite, cacheImageBottom);
  C2D_SpriteSetPos(&sprite, 0, 0);
  C2D_DrawSprite(&sprite);

  auto centerX = backBtn.x + backBtn.w/2 - backBtn.textW/2;
  auto centerY = backBtn.y + backBtn.h/2 - backBtn.textH/2;
  C2D_DrawRectSolid(backBtn.x, backBtn.y, 0.55f, backBtn.w, backBtn.h, /* i == curBookButton ? BOTTOM_BUTTON_DOWN_COLOR : */ BOTTOM_BUTTON_COLOR);
  C2D_DrawText(
    backBtn.text, C2D_WithColor, GFXScreen.bottom, centerX, centerY, 0.6f, 0.5, 0.5, C2D_Color32(0x11, 0x11, 0x11, 255)
  );
}}

enum MARGIN = 8.0f;
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

    btn.text = &textArray[i];
    C2D_TextParse(btn.text, textBuf, name.ptr);
    C2D_TextGetDimensions(btn.text, 0.5, 0.5, &btn.textW, &btn.textH);
    btn.x = 100;
    btn.y = i*(btn.textH+24) + SCREEN_HEIGHT;
    btn.w = btn.textW + 2*BOOK_BUTTON_MARGIN;
    btn.h = btn.textH + 2*BOOK_BUTTON_MARGIN;
  }

  float textWidth, textHeight;
  auto text = &textArray[BOOK_NAMES.length+1];
  C2D_TextParse(text, textBuf, "Options");
  C2D_TextGetDimensions(text, 0.5, 0.5, &textWidth, &textHeight);
  auto buttonHeight = textHeight + 2*BOTTOM_BUTTON_MARGIN;
  optionsBtn = Button(0, SCREEN_HEIGHT - buttonHeight, SCREEN_BOTTOM_WIDTH, buttonHeight, text, textWidth, textHeight);

  curBookButton = -1;
}}

View updateBookView(BookViewData* viewData, Input* input) { with (viewData) {
  View retVal = View.book;

  curBookButtonLast = curBookButton;

  if (input.down(Key.touch) && input.scrollMethodCur == ScrollMethod.none) {
    foreach (i, ref btn; bookButtons) {
      float btnRealY = btn.y + scrollInfo.scrollOffset;
      float touchRealX = input.touchRaw.px, touchRealY = input.touchRaw.py + SCREEN_HEIGHT;

      if (btnRealY + btn.h > 0 || btnRealY < SCREEN_HEIGHT) {
        if ( touchRealX >= btn.x    && touchRealX <= btn.x    + btn.w &&
             touchRealY >= btnRealY && touchRealY <= btnRealY + btn.h )
        {
          curBookButton = i;
          audioPlaySound(SoundSlot.button, SoundEffect.button_down, 0.25);
          break;
        }
      }
    }
  }
  else if (curBookButton != -1) {
    Button* btn = &bookButtons[curBookButton];
    float btnRealY = btn.y + scrollInfo.scrollOffset;
    float touchRealX = input.prevTouchRaw.px, touchRealY = input.prevTouchRaw.py + SCREEN_HEIGHT;

    bool hoveredOverCurrentButton = touchRealX >= btn.x    && touchRealX <= btn.x    + btn.w &&
                                    touchRealY >= btnRealY && touchRealY <= btnRealY + btn.h;

    enum TOUCH_DRAG_THRESHOLD = 8;
    auto touchDiff = input.touchDiff();

    if (hoveredOverCurrentButton && !input.held(Key.touch) && input.prevHeld(Key.touch)) {
      //signal to begin transition to reading view
      retVal = View.reading;
      chosenBook = curBookButton;
      curBookButton = -1;
      audioPlaySound(SoundSlot.button, SoundEffect.button_confirm, 0.5);
    }
    else if (!input.held(Key.touch) || touchDiff.y >= TOUCH_DRAG_THRESHOLD || !hoveredOverCurrentButton) {
      curBookButton = -1;
      audioPlaySound(SoundSlot.button, SoundEffect.button_off, 0.25);
    }
  }

  if (curBookButton == -1) {
    handleScroll(&scrollInfo, input, 0, bookButtons[$-1].y+bookButtons[$-1].h - SCREEN_HEIGHT + optionsBtn.textH + 2*BOTTOM_BUTTON_MARGIN);
  }
  else {
    scrollInfo.scrollOffsetLast = scrollInfo.scrollOffset;
    input.scrollVel = 0;
  }

  return retVal;
}}

void renderBookView(
  BookViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight, C3D_RenderTarget* bottom,
  bool _3DEnabled, float slider3DState
) { with (viewData) {
  static void renderBookButtons(
    BookViewData* viewData, float from, float to
  ) { with (viewData) {
    enum BOOK_BUTTON_COLOR      = C2D_Color32(0x00, 0x00, 0xFF, 0xFF);
    enum BOOK_BUTTON_DOWN_COLOR = C2D_Color32(0x55, 0x55, 0xFF, 0xFF);

    foreach (i, ref btn; bookButtons) {
      float btnRealX = btn.x, btnRealY = btn.y;

      if (btnRealY + btn.h < from) {
      }
      else if (btnRealY > to){
        break;
      }
      else {
        C2D_DrawRectSolid(btnRealX, btnRealY, 0.0, btn.w, btn.h, i == curBookButton ? BOOK_BUTTON_DOWN_COLOR : BOOK_BUTTON_COLOR);

        C2D_DrawText(
          btn.text, C2D_WithColor, GFXScreen.top, btnRealX+BOOK_BUTTON_MARGIN, btnRealY+BOOK_BUTTON_MARGIN, 0.5f, 0.5, 0.5, C2D_Color32(255, 255, 255, 255)
        );
      }
    }
  }}


  scrollCacheBeginFrame(&mainData.scrollCache);
  scrollCacheRenderScrollUpdate(
    &mainData.scrollCache,
    scrollInfo,
    &renderBookButtons, viewData,
    SCREEN_BOTTOM_WIDTH,
  );

  if (curBookButton != -1 || curBookButtonLast != -1) {
    Button* btn = &bookButtons[curBookButton == -1 ? curBookButtonLast : curBookButton];

    scrollCacheRenderRegion(
      &mainData.scrollCache,
      btn.y, btn.y+btn.h,
      &renderBookButtons, viewData,
      SCREEN_BOTTOM_WIDTH,
    );
  }
  scrollCacheEndFrame(&mainData.scrollCache);

  C2D_TargetClear(topLeft, CLEAR_COLOR);
  C2D_SceneBegin(topLeft);

  Tex3DS_SubTexture subtexTop    = setUvs(SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, 0,             scrollInfo.scrollOffset);
  Tex3DS_SubTexture subtexBottom = setUvs(SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, SCREEN_HEIGHT, scrollInfo.scrollOffset);
  C2D_Image cacheImageTop    = { &mainData.scrollCache.scrollTex, &subtexTop };
  C2D_Image cacheImageBottom = { &mainData.scrollCache.scrollTex, &subtexBottom };
  C2D_Sprite sprite;
  C2D_SpriteFromImage(&sprite, cacheImageTop);

  C2D_SpriteSetPos(&sprite, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2, 0);
  C2D_DrawSprite(&sprite);

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    C2D_DrawSprite(&sprite);
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);

  C2D_SpriteFromImage(&sprite, cacheImageBottom);
  C2D_DrawSprite(&sprite);

  C2D_DrawRectSolid(optionsBtn.x, optionsBtn.y, 0.55f, optionsBtn.w, optionsBtn.h, /* i == curBookButton ? BOTTOM_BUTTON_DOWN_COLOR : */ BOTTOM_BUTTON_COLOR);

  auto centerX = optionsBtn.x + optionsBtn.w/2 - optionsBtn.textW/2;
  auto centerY = optionsBtn.y + optionsBtn.h/2 - optionsBtn.textH/2;
  C2D_DrawText(
    optionsBtn.text, C2D_WithColor, GFXScreen.bottom, centerX, centerY, 0.6f, 0.5, 0.5, C2D_Color32(0x11, 0x11, 0x11, 255)
  );
}}

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
  float usedWidth,
) { with (scrollCache) with (scrollInfo) {
  float drawStart, drawEnd;

  float scroll     = floor(-scrollOffset),
        scrollLast = floor(-scrollOffsetLast);

  if (needsRepaint) {
    needsRepaint = false;
    drawStart = scroll;
    drawEnd   = scroll+SCROLL_HEIGHT;
    //C2D_TargetClear(scrollTarget, CLEAR_COLOR);
  }
  else {
    if (scrollOffset == scrollOffsetLast) return;

    //@TODO: Fix this difference in meaning of sign...

    drawStart  = (scrollLast < scroll) ? scrollLast + SCROLL_HEIGHT : scroll;
    drawEnd    = (scrollLast < scroll) ? scroll     + SCROLL_HEIGHT : scrollLast;
  }

  _scrollCacheRenderRegionImpl(
    scrollCache,
    drawStart, drawEnd,
    cast(void function(void* userData, float from, float to) @nogc nothrow) render, userData,
    usedWidth,
  );
}}

pragma(inline, true)
void scrollCacheRenderRegion(T)(
  ScrollCache* scrollCache,
  float from, float to,
  void function(T* userData, float from, float to) @nogc nothrow render, T* userData,
  float usedWidth,
) {
  _scrollCacheRenderRegionImpl(
    scrollCache,
    from, to,
    cast(void function(void* userData, float from, float to) @nogc nothrow) render, userData,
    usedWidth,
  );
}

private void _scrollCacheRenderRegionImpl(
  ScrollCache* scrollCache,
  float from, float to,
  void function(void* userData, float from, float to) @nogc nothrow render, void* userData,
  float usedWidth,
) { with (scrollCache) {
  float drawStart  = from;
  float drawEnd    = to;
  float drawOffset = -(drawStart - wrap(drawStart, SCROLL_HEIGHT));
  float drawHeight = drawEnd-drawStart;

  float drawStartOnTexture = wrap(drawStart, SCROLL_HEIGHT);
  float drawEndOnTexture   = drawStartOnTexture + drawHeight;
  float drawOffTexture     = max(drawEndOnTexture - SCROLL_HEIGHT, 0);

  C3D_FVUnifSet(GPUShaderType.vertex_shader, u_scrollRenderOffset, 0, drawOffset, 0, 0);

  //carve out stencil and clear piece of screen simulatenously
  C3D_StencilTest(true, GPUTestFunc.always, curStencilVal, 0xFF, 0xFF);
  C3D_StencilOp(GPUStencilOp.replace, GPUStencilOp.replace, GPUStencilOp.replace);

  C2D_DrawRectSolid(0, drawStart, 0, usedWidth, drawHeight, CLEAR_COLOR);
  C2D_Flush();

  //use callback to draw newly scrolled region
  C3D_StencilTest(true, GPUTestFunc.equal, curStencilVal, 0xFF, 0xFF);
  C3D_StencilOp(GPUStencilOp.keep, GPUStencilOp.keep, GPUStencilOp.keep);

  render(userData, drawStart, drawEnd - drawOffTexture);
  C2D_Flush();
  curStencilVal++;

  //draw from top if we draw past the bottom. use a different stencil to prevent overwriting stuff we just drew
  if (drawEndOnTexture >= SCROLL_HEIGHT) {
    C3D_FVUnifSet(GPUShaderType.vertex_shader, u_scrollRenderOffset, 0, drawOffset - SCROLL_HEIGHT, 0, 0);
    C3D_StencilTest(true, GPUTestFunc.always, curStencilVal, 0xFF, 0xFF);
    C3D_StencilOp(GPUStencilOp.replace, GPUStencilOp.replace, GPUStencilOp.replace);
    C2D_DrawRectSolid(0, drawStart, 0, usedWidth, drawHeight, CLEAR_COLOR);
    C2D_Flush();

    C3D_StencilTest(true, GPUTestFunc.equal, curStencilVal, 0xFF, 0xFF);
    C3D_StencilOp(GPUStencilOp.keep, GPUStencilOp.keep, GPUStencilOp.keep);
    render(userData, drawEnd - drawOffTexture, drawEnd);
    C2D_Flush();

    curStencilVal++;
  }
}}

Tex3DS_SubTexture setUvs(float width, float height, float yOffset, float scroll) {
  Tex3DS_SubTexture result = {
    width  : cast(ushort) width,
    height : cast(ushort) height,
    left   : 0,
    right  : width/SCROLL_WIDTH,
    top    : 1.0f - yOffset         /SCROLL_HEIGHT + floor(wrap(scroll, SCROLL_HEIGHT))/SCROLL_HEIGHT,
    bottom : 1.0f - (yOffset+height)/SCROLL_HEIGHT + floor(wrap(scroll, SCROLL_HEIGHT))/SCROLL_HEIGHT,
  };
  return result;
}

//fmod doesn't handle negatives the way you'd expect, so we need this instead
float wrap(float x, float mod) {
  import core.stdc.math : floor;
  return x - mod * floor(x/mod);
}