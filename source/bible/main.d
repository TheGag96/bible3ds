/*
  Bible for 3DS
  Written by TheGag96
*/

module bible.main;

import ctru;
import citro3d;
import citro2d;

import bible.bible, bible.audio, bible.input, bible.util, bible.save;
import bible.widgets;
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

  ScrollInfo scrollInfo;
}

enum View {
  book,
  reading,
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

  UiState uiState;

  bool frameNeedsRender;
}


enum CLEAR_COLOR = 0xFFEEEEEE;

enum BACKGROUND_COLOR_BG            = C2D_Color32(0xF5, 0xF5, 0xF5, 255);
enum BACKGROUND_COLOR_STRIPES_DARK  = C2D_Color32(208,  208,  212,  255);
enum BACKGROUND_COLOR_STRIPES_LIGHT = C2D_Color32(197,  197,  189,  255);

struct MainData {
  View curView = View.book, nextView = View.book;
  ScrollCache scrollCache;
  C3D_Tex vignetteTex, lineTex; //@TODO: Move somewhere probably
  C3D_Tex selectorTex;
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
  //C3D_AlphaTest(true, GPUTestFunc.notequal, 0); //make empty space in sprites properly transparent, even despite using the depth buffer
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
    if (!loadTextureFromFile(&selectorTex, null, "romfs:/gfx/selector.t3x"))
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

    final switch (mainData.nextView) {
      case View.book:
        if (mainData.curView != mainData.nextView) {
          mainData.curView = mainData.nextView;
          resetScrollDiff(&input);
          mainData.scrollCache.needsRepaint = true;
        }

        mainData.nextView = updateBookView(&bookViewData, &input);

        break;

      case View.reading:
        if (mainData.curView != mainData.nextView) {
          mainData.curView = mainData.nextView;

          with (readingViewData) {
            unloadPage(&loadedPage);
            closeBibleBook(&book);
            curBook = cast(Book) bookViewData.chosenBook;
            book = openBibleBook(Translation.asv, curBook);
            curChapter = 1;
            loadPage(&loadedPage, book.chapters[curChapter], 0.5);
            resetScrollDiff(&input);
            mainData.scrollCache.needsRepaint = true;
            frameNeedsRender = true;
          }
        }

        mainData.nextView = updateReadingView(&readingViewData, &input);

        break;
    }

    audioUpdate();

    //debug printf("\x1b[3;1HCPU:     %6.2f%%\x1b[K", C3D_GetProcessingTime()*6.0f);
    //debug printf("\x1b[4;1HGPU:     %6.2f%%\x1b[K", C3D_GetDrawingTime()*6.0f);
    //debug printf("\x1b[5;1HCmdBuf:  %6.2f%%\x1b[K", C3D_GetCmdBufUsage()*100.0f);

    // Render the scene
    C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
    {
      final switch (mainData.curView) {
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
  backBtn = Button(0, 0, SCREEN_HEIGHT - buttonHeight, 0.5, SCREEN_BOTTOM_WIDTH, buttonHeight, text, textWidth, textHeight);

  char[3] buf = 0;
  foreach (i; 1..85) {
    snprintf(buf.ptr, buf.length, "%d", i);
    C2D_TextParse(&textArray[i], textBuf, buf.ptr);
  }

  uiState.buttonHeld    = -1;
  uiState.buttonHovered = -1;
}}

View updateReadingView(ReadingViewData* viewData, Input* input) { with (viewData) {
  uiState.buttonHeldLast = uiState.buttonHeld;
  uiState.buttonHoveredLast = uiState.buttonHovered;

  if (input.down(Key.b) || handleButton(backBtn, *input, loadedPage.scrollInfo, &uiState, false)) {
    audioPlaySound(SoundEffect.button_back, 0.5);
    frameNeedsRender = true;
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
    frameNeedsRender = true;
  }
  else if (chapterDiff) {
    unloadPage(&loadedPage);
    curChapter += chapterDiff;
    loadPage(&loadedPage, book.chapters[curChapter], size);
    frameNeedsRender = true;
  }


  ////
  // update scrolling
  ////

  if (uiState.buttonHeld == -1) {
    float scrollLimit = max(loadedPage.actualLineNumberTable.length * glyphHeight + MARGIN * 2 - SCREEN_HEIGHT * 2, 0)
                        + backBtn.textH + 2*BOTTOM_BUTTON_MARGIN;
    handleScroll(&loadedPage.scrollInfo, input, 0, scrollLimit);

    frameNeedsRender = frameNeedsRender || loadedPage.scrollInfo.scrollOffset != loadedPage.scrollInfo.scrollOffsetLast;
  }
  else {
    loadedPage.scrollInfo.scrollOffsetLast = loadedPage.scrollInfo.scrollOffset;
    input.scrollVel = 0;
    frameNeedsRender = true;
  }

  frameNeedsRender = frameNeedsRender || loadedPage.scrollInfo.pushingAgainstTimer != 0;

  return View.reading;
}}

void renderReadingView(
  ReadingViewData* viewData, C3D_RenderTarget* topLeft, C3D_RenderTarget* topRight,
  C3D_RenderTarget* bottom, bool _3DEnabled, float slider3DState
) { with (viewData) {
  // Save battery by only rendering if we're scrolling, pressing buttons, etc.
  if (!viewData.frameNeedsRender) return;

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

  drawBackground(GFXScreen.top, &mainData.vignetteTex, &mainData.lineTex, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);

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

    drawBackground(GFXScreen.top, &mainData.vignetteTex, &mainData.lineTex, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);

    C2D_DrawSprite(&sprite);
    renderScrollIndicator(loadedPage.scrollInfo, SCREEN_BOTTOM_WIDTH + (SCREEN_TOP_WIDTH-SCREEN_BOTTOM_WIDTH)/2, 0, SCREEN_HEIGHT, mainData.scrollCache.desiredHeight);
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);

  C2D_SpriteFromImage(&sprite, cacheImageBottom);
  C2D_SpriteSetPos(&sprite, 0, 0);
  C2D_DrawSprite(&sprite);

  renderButton(backBtn, uiState, BOTTOM_BUTTON_STYLE);

  frameNeedsRender = false;
}}

enum MARGIN = 8.0f;
enum BOOK_BUTTON_WIDTH = 200.0f;
enum BOOK_BUTTON_MARGIN = 8.0f;
enum BOTTOM_BUTTON_MARGIN = 6.0f;
enum BOTTOM_BUTTON_COLOR      = C2D_Color32(0xCC, 0xCC, 0xCC, 0xFF);
enum BOTTOM_BUTTON_DOWN_COLOR = C2D_Color32(0x8C, 0x8C, 0x8C, 0xFF);

static immutable ButtonStyle BOTTOM_BUTTON_STYLE = {
  colorText     : C2D_Color32(0x11, 0x11, 0x11, 255),
  colorBg       : BOTTOM_BUTTON_COLOR,
  colorBgHeld   : BOTTOM_BUTTON_DOWN_COLOR,
  margin        : BOTTOM_BUTTON_MARGIN,
  textSize      : 0.5f,
  justification : Justification.centered,
};

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
    btn.z = 0.25;
    btn.w = BOOK_BUTTON_WIDTH;
    btn.h = btn.textH + 2*BOOK_BUTTON_MARGIN;
  }

  float textWidth, textHeight;
  auto text = &textArray[BOOK_NAMES.length+1];
  C2D_TextParse(text, textBuf, "Options");
  C2D_TextGetDimensions(text, 0.5, 0.5, &textWidth, &textHeight);
  auto buttonHeight = textHeight + 2*BOTTOM_BUTTON_MARGIN;
  optionsBtn = Button(BookButton.options, 0, SCREEN_HEIGHT - buttonHeight, 0.5, SCREEN_BOTTOM_WIDTH, buttonHeight, text, textWidth, textHeight);

  uiState.buttonHeld    = BookButton.none;
  uiState.buttonHovered = BookButton.none;
}}

View updateBookView(BookViewData* viewData, Input* input) { with (viewData) {
  View retVal = View.book;

  uiState.buttonHeldLast = uiState.buttonHeld;
  uiState.buttonHoveredLast = uiState.buttonHovered;

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
    int buttonSelected = handleButtonSelectionAndScroll(&uiState, bookButtons[], &scrollInfo, input, 0, bookButtons[$-1].y+bookButtons[$-1].h - SCREEN_HEIGHT + optionsBtn.textH + 2*BOTTOM_BUTTON_MARGIN);
    if (buttonSelected != -1) {
      retVal = View.reading;
      chosenBook = cast(Book) buttonSelected;
    }
  }
  else {
    //@TODO: Move this into widget code or something?
    uiState.selectedLastFadeTimer = approach(uiState.selectedLastFadeTimer, 0, 0.1);
    scrollInfo.scrollOffsetLast = scrollInfo.scrollOffset;
    input.scrollVel = 0;
  }

  return retVal;
}}

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

  drawBackground(GFXScreen.top, &mainData.vignetteTex, &mainData.lineTex, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);

  Tex3DS_SubTexture subtexTop    = scrollCacheGetUvs(mainData.scrollCache, SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, 0,             scrollInfo.scrollOffset);
  Tex3DS_SubTexture subtexBottom = scrollCacheGetUvs(mainData.scrollCache, SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT, SCREEN_HEIGHT, scrollInfo.scrollOffset);
  C2D_Image cacheImageTop    = { &mainData.scrollCache.scrollTex, &subtexTop };
  C2D_Image cacheImageBottom = { &mainData.scrollCache.scrollTex, &subtexBottom };
  C2D_Sprite sprite;
  C2D_SpriteFromImage(&sprite, cacheImageTop);

  C2D_SpriteSetPos(&sprite, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2, 0);
  C2D_DrawSprite(&sprite);

  renderButtonSelectionIndicator(uiState, bookButtons, scrollInfo, GFXScreen.top, &mainData.selectorTex);

  renderScrollIndicator(scrollInfo, SCREEN_TOP_WIDTH, 0, SCREEN_HEIGHT, mainData.scrollCache.desiredHeight, true);

  if (_3DEnabled) {
    C2D_TargetClear(topRight, CLEAR_COLOR);
    C2D_SceneBegin(topRight);

    drawBackground(GFXScreen.top, &mainData.vignetteTex, &mainData.lineTex, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);

    C2D_DrawSprite(&sprite);
    renderButtonSelectionIndicator(uiState, bookButtons, scrollInfo, GFXScreen.top, &mainData.selectorTex);

    renderScrollIndicator(scrollInfo, SCREEN_TOP_WIDTH, 0, SCREEN_HEIGHT, mainData.scrollCache.desiredHeight, true);
  }

  C2D_TargetClear(bottom, CLEAR_COLOR);
  C2D_SceneBegin(bottom);

  drawBackground(GFXScreen.bottom, &mainData.vignetteTex, &mainData.lineTex, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);

  C2D_SpriteFromImage(&sprite, cacheImageBottom);
  C2D_DrawSprite(&sprite);

  renderButtonSelectionIndicator(uiState, bookButtons, scrollInfo, GFXScreen.bottom, &mainData.selectorTex);

  renderButton(optionsBtn, uiState, BOTTOM_BUTTON_STYLE);
}}
