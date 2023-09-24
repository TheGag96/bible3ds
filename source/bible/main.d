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
import bible.profiling;

//debug import bible.debugging;

import core.stdc.signal;
import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.time;

import ldc.llvmasm;

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

struct PageId {
  Translation translation;
  Book book;
  int chapter;
}

struct MainData {
  View curView = View.book;
  ScrollCache scrollCache;

  float size = 0;
  OpenBook book;
  PageId pageId;
  LoadedPage loadedPage;

  float defaultPageTextSize = 0, defaultPageMargin = 0;

  bool frameNeedsRender;
}
MainData mainData;

enum SOC_ALIGN      = 0x1000;
enum SOC_BUFFERSIZE = 0x100000;

uint* SOC_buffer = null;

extern(C) void* memalign(size_t, size_t);

extern(C) int main(int argc, char** argv) {
  threadOnException(&crashHandler,
                    RUN_HANDLER_ON_FAULTING_STACK,
                    WRITE_DATA_TO_FAULTING_STACK);

  gTempStorage = arenaMake(16*1024);

  // Init libs
  romfsInit();

  static if (PROFILING_ENABLED) {
    int ret;
    // allocate buffer for SOC service
    SOC_buffer = cast(uint*) memalign(SOC_ALIGN, SOC_BUFFERSIZE);

    assert(SOC_buffer, "memalign: failed to allocate\n");

    // Now intialise soc:u service
    if ((ret = socInit(SOC_buffer, SOC_BUFFERSIZE)) != 0) {
      assert(0);
    }

    link3dsStdio();
  }

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

  gTempStorage = arenaMake(16*1024);

  Result saveResult = saveFileInit();
  assert(!saveResult, "file creation failed");

  // Create screens
  C3D_RenderTarget* topLeft  = C2D_CreateScreenTarget(GFXScreen.top,    GFX3DSide.left);
  C3D_RenderTarget* topRight = C2D_CreateScreenTarget(GFXScreen.top,    GFX3DSide.right);
  C3D_RenderTarget* bottom   = C2D_CreateScreenTarget(GFXScreen.bottom, GFX3DSide.left);

  osTickCounterStart(&tickCounter);

  initMainData(&mainData);

  // Main loop
  while (aptMainLoop()) {
    beginProfile();

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
    arenaClear(&gTempStorage);

    mainGui(&mainData, &input);

    audioUpdate();

    //debug printf("\x1b[3;1HCPU:     %6.2f%%\x1b[K", C3D_GetProcessingTime()*6.0f);
    //debug printf("\x1b[4;1HGPU:     %6.2f%%\x1b[K", C3D_GetDrawingTime()*6.0f);
    //debug printf("\x1b[5;1HCmdBuf:  %6.2f%%\x1b[K", C3D_GetCmdBufUsage()*100.0f);

    {
      mixin(timeBlock("render"));


    // Render the scene
    {
      mixin(timeBlock("beginFrame"));
      C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
    }
    {
      if (mainData.curView == View.reading) {
        mixin(timeBlock("render > scroll cache"));

        scrollCacheBeginFrame(&mainData.scrollCache);
        scrollCacheRenderScrollUpdate(
          &mainData.scrollCache,
          mainData.loadedPage.scrollInfo,
          &renderPage, &mainData.loadedPage,
          CLEAR_COLOR,
        );
        scrollCacheEndFrame(&mainData.scrollCache);
      }

      {
        mixin(timeBlock("render > left"));
        C2D_TargetClear(topLeft, CLEAR_COLOR);
        C2D_SceneBegin(topLeft);
        drawBackground(GFXScreen.top, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);
        render(GFXScreen.top, GFX3DSide.left, _3DEnabled, slider);
      }

      if (_3DEnabled) {
        mixin(timeBlock("render > right"));
        C2D_TargetClear(topRight, CLEAR_COLOR);
        C2D_SceneBegin(topRight);
        drawBackground(GFXScreen.top, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);
        render(GFXScreen.top, GFX3DSide.right, _3DEnabled, slider);
      }

      {
        mixin(timeBlock("render > bottom"));
        C2D_TargetClear(bottom, CLEAR_COLOR);
        C2D_SceneBegin(bottom);
        drawBackground(GFXScreen.bottom, BACKGROUND_COLOR_BG, BACKGROUND_COLOR_STRIPES_DARK, BACKGROUND_COLOR_STRIPES_LIGHT);
        render(GFXScreen.bottom, GFX3DSide.left, false, 0);
      }
    }

    }
    C3D_FrameEnd(0);
    endProfileAndLog();
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
  enum SCROLL_CACHE_WIDTH  = cast(ushort) SCREEN_BOTTOM_WIDTH,
       SCROLL_CACHE_HEIGHT = cast(ushort) (2*SCREEN_HEIGHT);

  scrollCache = scrollCacheCreate(SCROLL_CACHE_WIDTH, SCROLL_CACHE_HEIGHT);

  defaultPageTextSize = DEFAULT_PAGE_TEXT_SIZE;
  defaultPageMargin   = DEFAULT_PAGE_MARGIN;
}}

void loadBiblePage(MainData* mainData, PageId newPageId) { with (mainData) {
  if (newPageId == pageId) return;

  unloadPage(&loadedPage);

  if (!book.rawFile || newPageId.translation != pageId.translation || newPageId.book != pageId.book) {
    closeBibleBook(&book);
    book = openBibleBook(newPageId.translation, newPageId.book);
  }

  if (newPageId.chapter < 0) {
    newPageId.chapter = book.chapters.length + newPageId.chapter;
  }

  loadPage(&loadedPage, book.chapters[newPageId.chapter], defaultPageTextSize, defaultPageMargin);
  scrollCache.needsRepaint = true;
  frameNeedsRender = true;

  // @Hack: Is there any better way to do this?
  auto readViewPane = gUiData.boxes["reading_scroll_read_view"];
  if (readViewPane) {
    readViewPane.scrollInfo.offset     = 0;
    readViewPane.scrollInfo.offsetLast = 0;
  }

  pageId = newPageId;
}}

void handleChapterSwitchHotkeys(MainData* mainData, Input* input) { with (mainData) {
  int chapterDiff, bookDiff;
  if (input.down(Key.l)) {
    if (pageId.chapter == 1) {
      if (pageId.book != Book.min) {
        bookDiff = -1;
      }
    }
    else {
      chapterDiff = -1;
    }
  }
  else if (input.down(Key.r)) {
    if (pageId.chapter == book.chapters.length-1) {
      if (pageId.book != Book.max) {
        bookDiff = 1;
      }
    }
    else {
      chapterDiff = 1;
    }
  }

  PageId newPageId = pageId;

  if (bookDiff) {
    newPageId.book = cast(Book) (newPageId.book + bookDiff);

    if (bookDiff > 0) {
      newPageId.chapter = 1;
    }
    else {
      newPageId.chapter = -1;  // Resolved in loadBiblePage
    }
  }
  else if (chapterDiff) {
    newPageId.chapter += chapterDiff;
  }

  loadBiblePage(mainData, newPageId);
}}

// Returns the ScrollInfo needed to update the reading view's scroll cache.
void mainGui(MainData* mainData, Input* input) {
  mixin(timeBlock("mainGui"));

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
        loadBiblePage(mainData, PageId(gSaveFile.settings.translation, cast(Book) command.value, 1));
        break;
    }
  }

  // @TODO: Should this be handled as a UI command?
  if (mainData.curView == View.reading) {
    handleChapterSwitchHotkeys(mainData, input);
  }

  uiFrameStart();
  handleInput(input);

  auto mainLayout = ScopedCombinedScreenSplitLayout("combined_screen_layout_main", "combined_screen_layout_left", "combined_screen_layout_center", "combined_screen_layout_right");
  mainLayout.startCenter();

  final switch (mainData.curView) {
    case View.book:
      UiBox* scrollLayoutBox;
      UiSignal scrollLayoutSignal;
      {
        auto scrollLayout = ScopedSelectScrollLayout("book_scroll_layout", &scrollLayoutSignal);
        auto style        = ScopedStyle(&BOOK_BUTTON_STYLE);

        scrollLayoutBox = scrollLayout.box;

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(SCREEN_HEIGHT + 8);

        foreach (i, book; BOOK_NAMES) {
          if (button(book, 150).clicked) {
            sendCommand(CommandCode.open_book, i);
          }

          spacer(8);
        }

        int x= 3;
      }

      {
        auto style = ScopedStyle(&BOTTOM_BUTTON_STYLE);
        if (bottomButton("Options").clicked) {
          sendCommand(CommandCode.switch_view, View.options);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout("book_right_split_layout_main", "book_right_split_layout_top", "book_right_split_layout_bottom");

        rightSplit.startTop();

        scrollIndicator("book_scroll_indicator", scrollLayoutBox, Justification.max, scrollLayoutSignal.pushingAgainstScrollLimit);
      }

      break;

    case View.reading:
      auto readPane = scrollableReadPane("reading_scroll_read_view", mainData.loadedPage, &mainData.scrollCache);
      mainData.loadedPage.scrollInfo = readPane.box.scrollInfo;

      {
        auto style = ScopedStyle(&BACK_BUTTON_STYLE);
        if (bottomButton("Back").clicked || input.down(Key.b)) {
          sendCommand(CommandCode.switch_view, View.book);
          audioPlaySound(SoundEffect.button_back, 0.5);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout("reading_right_split_layout_main", "reading_right_split_layout_top", "reading_right_split_layout_bottom");

        rightSplit.startTop();

        scrollIndicator("reading_scroll_indicator", readPane.box, Justification.min, readPane.signal.pushingAgainstScrollLimit);
      }

      break;

    case View.options:
      UiBox* scrollLayoutBox;
      UiSignal scrollLayoutSignal;
      {
        auto scrollLayout = ScopedSelectScrollLayout("options_scroll_layout", &scrollLayoutSignal);
        auto style        = ScopedStyle(&BOOK_BUTTON_STYLE);
        scrollLayout.box.justification = Justification.min;

        scrollLayoutBox = scrollLayout.box;

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(SCREEN_HEIGHT + 8);

        label("Translation");

        foreach (i, translation; TRANSLATION_NAMES_LONG) {
          if (button(translation).clicked) {
            gSaveFile.settings.translation = cast(Translation) i;
          }

          spacer(8);
        }
      }

      {
        auto style = ScopedStyle(&BACK_BUTTON_STYLE);
        if (bottomButton("Back").clicked || input.down(Key.b)) {
          sendCommand(CommandCode.switch_view, View.book);
          audioPlaySound(SoundEffect.button_back, 0.5);
          saveSettings();
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout("options_right_split_layout_main", "options_right_split_layout_top", "options_right_split_layout_bottom");

        rightSplit.startTop();

        scrollIndicator("book_scroll_indicator", scrollLayoutBox, Justification.max, scrollLayoutSignal.pushingAgainstScrollLimit);
      }
      break;
  }

  uiFrameEnd();
}

extern(C) void crashHandler(ERRF_ExceptionInfo* excep, CpuRegisters* regs) {
  import ctru.console : consoleInit;
  import ctru.gfx     : GFXScreen;

  consoleInit(GFXScreen.bottom, null);
  printf("\x1b[1;1HException hit!\n");
  printf("PC\t= %08X, LR  \t= %08X\n", regs.pc, regs.lr);
  printf("SP\t= %08X, CPSR\t= %08X\n", regs.sp, regs.cpsr);

  foreach (i, x; regs.r) {
    printf("R%d\t= %08X\n", i, x);
  }

  printf("\n\nPress Start to exit...\n");

  //wait for key press and exit (so we can read the error message)
  while (aptMainLoop()) {
    hidScanInput();

    if ((hidKeysDown() & (1<<3))) {
      exit(0);
    }
  }
}
