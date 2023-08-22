/*
  Bible for 3DS
  Written by TheGag96
*/

module bible.main;

import ctru;
import citro3d;
import citro2d;

import bible.bible, bible.audio, bible.input, bible.util, bible.save;
import bible.imgui, bible.imgui_render;

//debug import bible.debugging;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.time;

nothrow: @nogc:

__gshared TickCounter tickCounter;

enum View {
  book,
  reading,
  options,
}

enum CLEAR_COLOR = 0xFFEEEEEE;

enum BACKGROUND_COLOR_BG            = C2D_Color32(0xF5, 0xF5, 0xF5, 255);
enum BACKGROUND_COLOR_STRIPES_DARK  = C2D_Color32(208,  208,  212,  255);
enum BACKGROUND_COLOR_STRIPES_LIGHT = C2D_Color32(197,  197,  189,  255);

enum DEFAULT_PAGE_TEXT_SIZE = 0.5;
enum DEFAULT_PAGE_MARGIN    = 8;

struct MainData {
  View curView = View.book;
  ScrollCache scrollCache;

  float size = 0;
  OpenBook book;
  Book curBook;
  LoadedPage loadedPage;
  int curChapter;

  float defaultPageTextSize = 0, defaultPageMargin = 0;

  bool frameNeedsRender;
}
MainData mainData;

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

  loadUiAssets();
  uiInit();

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

  initMainData(&mainData);

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

    mainGui(&mainData, &input);

    audioUpdate();

    //debug printf("\x1b[3;1HCPU:     %6.2f%%\x1b[K", C3D_GetProcessingTime()*6.0f);
    //debug printf("\x1b[4;1HGPU:     %6.2f%%\x1b[K", C3D_GetDrawingTime()*6.0f);
    //debug printf("\x1b[5;1HCmdBuf:  %6.2f%%\x1b[K", C3D_GetCmdBufUsage()*100.0f);

    // Render the scene
    C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
    {
      if (mainData.curView == View.reading) {
        scrollCacheBeginFrame(&mainData.scrollCache);
        scrollCacheRenderScrollUpdate(
          &mainData.scrollCache,
          mainData.loadedPage.scrollInfo,
          &renderPage, &mainData.loadedPage,
          CLEAR_COLOR,
        );
        scrollCacheEndFrame(&mainData.scrollCache);
      }

      C2D_TargetClear(topLeft, CLEAR_COLOR);
      C2D_SceneBegin(topLeft);
      drawBackground(GFXScreen.top, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);
      render(GFXScreen.top, GFX3DSide.left, _3DEnabled, slider);

      if (_3DEnabled) {
        C2D_TargetClear(topRight, CLEAR_COLOR);
        C2D_SceneBegin(topRight);
        drawBackground(GFXScreen.top, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);
        render(GFXScreen.top, GFX3DSide.right, _3DEnabled, slider);
      }

      C2D_TargetClear(bottom, CLEAR_COLOR);
      C2D_SceneBegin(bottom);
      drawBackground(GFXScreen.bottom, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);
      render(GFXScreen.bottom, GFX3DSide.left, false, 0);
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


void initMainData(MainData* mainData) { with (mainData) {
  curBook = Book.Joshua;
  curChapter = 1;
  book = openBibleBook(Translation.asv, curBook);
  defaultPageTextSize = DEFAULT_PAGE_TEXT_SIZE;
  defaultPageMargin   = DEFAULT_PAGE_MARGIN;
  loadPage(&loadedPage, book.chapters[curChapter], defaultPageTextSize, defaultPageMargin);
}}

void handleChapterSwitchHotkeys(MainData* mainData, Input* input) { with (mainData) {
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

    loadPage(&loadedPage, book.chapters[curChapter], defaultPageTextSize, defaultPageMargin);
    frameNeedsRender = true;
  }
  else if (chapterDiff) {
    unloadPage(&loadedPage);
    curChapter += chapterDiff;
    loadPage(&loadedPage, book.chapters[curChapter], defaultPageTextSize, defaultPageMargin);
    frameNeedsRender = true;
  }
}}

// Returns the ScrollInfo needed to update the reading view's scroll cache.
void mainGui(MainData* mainData, Input* input) {
  enum CommandCode {
    switch_view,
    open_book,
  }

  foreach (command; getCommands()) {
    final switch (cast(CommandCode) command.code) {
      case CommandCode.switch_view:
        mainData.curView = cast(View) command.value;
        break;
      case CommandCode.open_book:
        mainData.curView = View.reading;

        with (mainData) {
          unloadPage(&loadedPage);
          closeBibleBook(&book);
          curBook = cast(Book) command.value;
          book = openBibleBook(Translation.asv, curBook);
          curChapter = 1;
          loadPage(&loadedPage, book.chapters[curChapter], defaultPageTextSize, defaultPageMargin);
          resetScrollDiff(input);
          mainData.scrollCache.needsRepaint = true;
          frameNeedsRender = true;
        }

        break;
    }
  }

  // @TODO: Should this be handled as a UI command?
  if (mainData.curView == View.reading) {
    handleChapterSwitchHotkeys(mainData, input);
  }

  uiFrameStart();
  handleInput(input);

  auto mainLayout = ScopedCombinedScreenSplitLayout(UiId.combined_screen_layout_main, UiId.combined_screen_layout_left, UiId.combined_screen_layout_center, UiId.combined_screen_layout_right);
  mainLayout.startCenter();

  final switch (mainData.curView) {
    case View.book:
      UiBox* scrollLayoutBox;
      UiSignal scrollLayoutSignal;
      {
        auto scrollLayout = ScopedSelectScrollLayout(UiId.book_scroll_layout, &scrollLayoutSignal);
        auto style        = ScopedStyle(&BOOK_BUTTON_STYLE);

        scrollLayoutBox = scrollLayout.box;

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(UiId.book_screen_spacer, SCREEN_HEIGHT + 8);

        foreach (i, book; BOOK_NAMES) {
          if (button(cast(UiId) (UiId.book_bible_btn_first + i), book, 150).clicked) {
            sendCommand(CommandCode.open_book, i);
          }

          spacer(cast(UiId) (UiId.book_bible_btn_spacer_first + i), 8);
        }
      }

      {
        auto style = ScopedStyle(&BOTTOM_BUTTON_STYLE);
        if (bottomButton(UiId.book_options_btn, "Options").clicked) {
          sendCommand(CommandCode.switch_view, View.options);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout(UiId.book_right_split_layout_main, UiId.book_right_split_layout_top, UiId.book_right_split_layout_bottom);

        rightSplit.startTop();

        scrollIndicator(UiId.book_scroll_indicator, scrollLayoutBox, Justification.max, scrollLayoutSignal.pushingAgainstScrollLimit);
      }

      break;

    case View.reading:
      auto readPane = scrollableReadPane(UiId.reading_scroll_read_view, mainData.loadedPage, &mainData.scrollCache);
      mainData.loadedPage.scrollInfo = readPane.box.scrollInfo;

      {
        auto style = ScopedStyle(&BACK_BUTTON_STYLE);
        if (bottomButton(UiId.reading_back_btn, "Back").clicked || input.down(Key.b)) {
          sendCommand(CommandCode.switch_view, View.book);
          audioPlaySound(SoundEffect.button_back, 0.5);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout(UiId.reading_right_split_layout_main, UiId.reading_right_split_layout_top, UiId.reading_right_split_layout_bottom);

        rightSplit.startTop();

        scrollIndicator(UiId.reading_scroll_indicator, readPane.box, Justification.min, readPane.signal.pushingAgainstScrollLimit);
      }

      break;

    case View.options:
      {
        auto style = ScopedStyle(&BACK_BUTTON_STYLE);
        if (bottomButton(UiId.options_back_btn, "Back").clicked || input.down(Key.b)) {
          sendCommand(CommandCode.switch_view, View.book);
          audioPlaySound(SoundEffect.button_back, 0.5);
        }
      }
      break;
  }

  uiFrameEnd();
}
