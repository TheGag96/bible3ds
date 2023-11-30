/*
  Bible for 3DS
  Written by TheGag96
*/

module bible.main;

import ctru;
import citro3d;
import citro2d;

import bible.bible, bible.audio, bible.input, bible.util, bible.save;
import ui = bible.imgui;
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

struct PageId {
  Translation translation;
  Book book;
  int chapter;
}

struct UiView {
  ui.UiData uiData;
  alias uiData this;

  Rectangle rect;
}

alias ModalCallback = bool function(MainData* mainData, UiView* uiView);

struct MainData {
  View curView;
  UiView[View.max+1] views;
  UiView modal;
  ModalCallback modalCallback;
  bool renderModal;
  ui.ScrollCache scrollCache;

  float size = 0;

  PageId pageId;
  ui.LoadedPage loadedPage;

  float defaultPageTextSize = 0, defaultPageMargin = 0;

  bool frameNeedsRender;

  BibleLoadData bible;

  ui.ColorTable colorTable;
  bool fadingBetweenThemes;
  ui.BoxStyle styleButtonBook, styleButtonBottom, styleButtonBack;
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

  gNullInput = cast(Input*) &gNullInputStore;

  gTempStorage = arenaMake(16*1024);

  // Init libs
  romfsInit();

  Result saveResult = saveFileInit();
  assert(!saveResult, "file creation failed");

  // Try to start loading the Bible as soon as possible asynchronously
  startAsyncBibleLoad(&mainData.bible, gSaveFile.settings.translation);

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

  ui.loadAssets();

  Input input;

  audioInit();

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

    if (mainData.curView == View.reading && input.framesNoInput > 60) {
      ////
      // Dormant frame
      ////

      // In attempt to save battery life, do basically nothing if we're reading and have received no input for a while.
      C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
      C3D_FrameEnd(0);
    }
    else {
      ////
      // Normal frame
      ////

      mainGui(&mainData, &input);

      audioUpdate();

      //debug printf("\x1b[3;1HCPU:     %6.2f%%\x1b[K", C3D_GetProcessingTime()*6.0f);
      //debug printf("\x1b[4;1HGPU:     %6.2f%%\x1b[K", C3D_GetDrawingTime()*6.0f);
      //debug printf("\x1b[5;1HCmdBuf:  %6.2f%%\x1b[K", C3D_GetCmdBufUsage()*100.0f);

      mixin(timeBlock("render"));

      // Render the scene
      {
        mixin(timeBlock("beginFrame"));
        C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
      }
      if (mainData.curView == View.reading) {
        mixin(timeBlock("render > scroll cache"));

        ui.scrollCacheBeginFrame(&mainData.scrollCache);
        ui.scrollCacheRenderScrollUpdate(
          &mainData.scrollCache,
          mainData.loadedPage.scrollInfo,
          &ui.renderPage, &mainData.loadedPage,
          mainData.colorTable[ui.Color.clear_color],
        );
        ui.scrollCacheEndFrame(&mainData.scrollCache);
      }

      auto mainUiData  = &mainData.views[mainData.curView].uiData;
      auto modalUiData = &mainData.modal.uiData;

      {
        mixin(timeBlock("render > left"));
        C2D_TargetClear(topLeft, mainData.colorTable[ui.Color.clear_color]);
        C2D_SceneBegin(topLeft);
        if (mainData.renderModal) ui.render(modalUiData, GFXScreen.top, GFX3DSide.left, _3DEnabled, slider, 0.1);
        ui.drawBackground(GFXScreen.top, mainData.colorTable[ui.Color.bg_bg], mainData.colorTable[ui.Color.bg_stripes_dark], mainData.colorTable[ui.Color.bg_stripes_light]);
        ui.render(mainUiData,  GFXScreen.top, GFX3DSide.left, _3DEnabled, slider);
      }

      if (_3DEnabled) {
        mixin(timeBlock("render > right"));
        C2D_TargetClear(topRight, mainData.colorTable[ui.Color.clear_color]);
        C2D_SceneBegin(topRight);
        if (mainData.renderModal) ui.render(modalUiData, GFXScreen.top, GFX3DSide.right, _3DEnabled, slider, 0.1);
        ui.drawBackground(GFXScreen.top, mainData.colorTable[ui.Color.bg_bg], mainData.colorTable[ui.Color.bg_stripes_dark], mainData.colorTable[ui.Color.bg_stripes_light]);
        ui.render(mainUiData,  GFXScreen.top, GFX3DSide.right, _3DEnabled, slider);
      }

      {
        mixin(timeBlock("render > bottom"));
        C2D_TargetClear(bottom, mainData.colorTable[ui.Color.clear_color]);
        C2D_SceneBegin(bottom);
        if (mainData.renderModal) ui.render(modalUiData, GFXScreen.bottom, GFX3DSide.left, false, 0, 0.1);
        ui.drawBackground(GFXScreen.bottom, mainData.colorTable[ui.Color.bg_bg], mainData.colorTable[ui.Color.bg_stripes_dark], mainData.colorTable[ui.Color.bg_stripes_light]);
        ui.render(mainUiData,  GFXScreen.bottom, GFX3DSide.left, false, 0);
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

  foreach (ref view; views) {
    ui.init(&view.uiData);
  }
  ui.init(&modal.uiData);

  scrollCache = ui.scrollCacheCreate(SCROLL_CACHE_WIDTH, SCROLL_CACHE_HEIGHT);

  defaultPageTextSize = DEFAULT_PAGE_TEXT_SIZE;
  defaultPageMargin   = DEFAULT_PAGE_MARGIN;

  colorTable = COLOR_THEMES[gSaveFile.settings.colorTheme];

  styleButtonBook                 = ui.BoxStyle.init;
  styleButtonBook.colors          = colorTable;
  styleButtonBook.margin          = BOOK_BUTTON_MARGIN;
  styleButtonBook.textSize        = 0.5f;

  styleButtonBottom               = styleButtonBook;
  styleButtonBottom.margin        = BOTTOM_BUTTON_MARGIN;
  styleButtonBottom.textSize      = 0.6f;

  // @Hack: Gets played manually by builder code so that it plays on pressing B. Consider revising...
  styleButtonBack                 = styleButtonBottom;
  styleButtonBack.pressedSound    = SoundEffect.none;
  styleButtonBack.pressedSoundVol = 0.0;
}}

void loadBiblePage(MainData* mainData, PageId newPageId) { with (mainData) {
  if (newPageId == pageId) return;

  OpenBook* book = &bible.books[newPageId.book];

  if (newPageId.chapter < 0) {
    newPageId.chapter = book.chapters.length + newPageId.chapter;
  }

  ui.loadPage(&loadedPage, book.chapters[newPageId.chapter], newPageId.chapter, defaultPageTextSize, Vec2(defaultPageMargin));
  scrollCache.needsRepaint = true;
  frameNeedsRender = true;

  // @Hack: Is there any better way to do this?
  auto readViewPane = mainData.views[View.reading].boxes["reading_scroll_read_view"];
  if (!ui.boxIsNull(readViewPane)) {
    readViewPane.scrollInfo.offset     = 0;
    readViewPane.scrollInfo.offsetLast = 0;
  }

  loadedPage.scrollInfo.offset     = 0;
  loadedPage.scrollInfo.offsetLast = 0;

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
    if (pageId.chapter == bible.books[pageId.book].chapters.length-1) {
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

void openModal(MainData* mainData, ModalCallback modalCallback) {
  mainData.modalCallback = modalCallback;
  ui.clear(&mainData.modal.uiData);
}

// Returns the ScrollInfo needed to update the reading view's scroll cache.
void mainGui(MainData* mainData, Input* input) {
  import bible.imgui;

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
        // @TODO: Do this without blocking UI
        waitAsyncBibleLoad(&mainData.bible);
        mainData.curView = View.reading;
        loadBiblePage(mainData, PageId(gSaveFile.settings.translation, cast(Book) command.value, 1));
        break;
    }
  }

  // @TODO: Should this be handled as a UI command?
  if (mainData.curView == View.reading) {
    handleChapterSwitchHotkeys(mainData, input);
  }

  // Do a smooth color fade between color themes
  if (mainData.fadingBetweenThemes) {
    bool changed = false;
    foreach (color; enumRange!(ui.Color)) {
      auto oldColor8     = mainData.colorTable[color];
      auto targetColor8  = COLOR_THEMES[gSaveFile.settings.colorTheme][color];
      auto newColorF     = rgba8ToRgbaF(oldColor8);
      auto targetColorF  = rgba8ToRgbaF(targetColor8);
      newColorF         += (targetColorF - newColorF) * 0.25;

      auto newColor8 = C2D_Color32f(newColorF.x, newColorF.y, newColorF.z, newColorF.w);

      if (newColor8 == oldColor8) {
        // Failsafe, since the fading is converting back and forth between integer and float and therefore may lock
        // into a point where the easing is too small to make a difference. Kinda crappy.
        newColor8 = targetColor8;
      }
      else {
        changed = true;
      }

      mainData.colorTable[color] = newColor8;
    }

    mainData.fadingBetweenThemes = changed;
  }

  Input* mainInput = input;
  if (mainData.modalCallback) {
    mainData.renderModal = true;

    frameStart(&mainData.modal.uiData, input);

    bool result;
    {
      // Set up some nice defaults, including being on the bottom screen with a background
      auto defaultStyle = ScopedStyle(&mainData.styleButtonBook);

      auto mainLayout = ScopedCombinedScreenSplitLayout("", "", "", "");
      mainLayout.startCenter();

      auto split = ScopedDoubleScreenSplitLayout("", "", "");
      split.startBottom();
      split.bottom.justification = Justification.center;

      spacer();
      {
        auto modalLayout = ScopedLayout("", Axis2.y);
        modalLayout.render = &renderModalBackground;
        modalLayout.semanticSize[Axis2.x] = Size(SizeKind.pixels, SCREEN_BOTTOM_WIDTH - 2*10, 1);
        modalLayout.semanticSize[Axis2.y] = Size(SizeKind.pixels, SCREEN_HEIGHT       - 2*10, 1);

        result = mainData.modalCallback(mainData, &mainData.modal);
      }
      spacer();
    }

    frameEnd();

    if (result) {
      // Don't set renderModal to false here so that we get one more frame to render
      mainData.modalCallback = null;
    }

    mainInput = gNullInput;
  }
  else {
    mainData.renderModal   = false;
  }

  frameStart(&mainData.views[mainData.curView].uiData, mainInput);

  auto defaultStyle = ScopedStyle(&mainData.styleButtonBook);

  auto mainLayout = ScopedCombinedScreenSplitLayout("combined_screen_layout_main", "combined_screen_layout_left", "combined_screen_layout_center", "combined_screen_layout_right");
  mainLayout.startCenter();

  final switch (mainData.curView) {
    case View.book:
      Box* scrollLayoutBox;
      Signal scrollLayoutSignal;
      bool pushingAgainstScrollLimit = false;

      {
        auto scrollLayout = ScopedScrollLayout("book_scroll_layout", &scrollLayoutSignal, Axis2.y);

        scrollLayoutBox = scrollLayout.box;

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(SCREEN_HEIGHT + 8);

        {
          auto horziontalLayout = ScopedLayout("", Axis2.x, justification : Justification.min, layoutKind : LayoutKind.fit_children);

          Signal leftColumnSignal;
          {
            auto leftColumn = ScopedSelectLayout("book_left_column", &leftColumnSignal, Axis2.y);

            foreach (i, book; BOOK_NAMES) {
              if (i % 2 == 0) {
                auto bookButton = button(book, 150);

                // Select the first book button if nothing else is
                if (i == 0 && boxIsNull(gUiData.hot)) gUiData.hot = bookButton.box;

                if (bookButton.clicked) {
                  sendCommand(CommandCode.open_book, i);
                }

                spacer(8);
              }
            }
          }
          pushingAgainstScrollLimit |= leftColumnSignal.pushingAgainstScrollLimit;

          Signal rightColumnSignal;
          {
            auto rightColumn = ScopedSelectLayout("book_right_column", &rightColumnSignal, Axis2.y);

            foreach (i, book; BOOK_NAMES) {
              if (i % 2 == 1) {
                auto bookButton = button(book, 150);
                if (bookButton.clicked) {
                  sendCommand(CommandCode.open_book, i);
                }

                spacer(8);
              }
            }
          }
          pushingAgainstScrollLimit |= rightColumnSignal.pushingAgainstScrollLimit;

          // Allow hopping columns
          Box* oppositeColumn = gUiData.hot.parent == leftColumnSignal.box ? rightColumnSignal.box : leftColumnSignal.box;
          if (!touchScrollOcurring(*input, Axis2.y) && input.downOrRepeat(Key.left | Key.right)) {
            gUiData.hot = getChild(oppositeColumn, gUiData.hot.childId);
            audioPlaySound(SoundEffect.button_move, 0.05);
          }
        }
      }
      pushingAgainstScrollLimit |= scrollLayoutSignal.pushingAgainstScrollLimit;

      {
        auto bottomLayout = ScopedLayout("", Axis2.x, Justification.center, LayoutKind.fit_children);
        auto style = ScopedStyle(&mainData.styleButtonBottom);

        if (bottomButton("Options").clicked) {
          sendCommand(CommandCode.switch_view, View.options);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout("book_right_split_layout_main", "book_right_split_layout_top", "book_right_split_layout_bottom");

        rightSplit.startTop();

        scrollIndicator("book_scroll_indicator", scrollLayoutBox, Justification.max, pushingAgainstScrollLimit);
      }

      break;

    case View.reading:
      auto readPane = scrollableReadPane("reading_scroll_read_view", mainData.loadedPage, &mainData.scrollCache);
      mainData.loadedPage.scrollInfo = readPane.box.scrollInfo;

      {
        auto style = ScopedStyle(&mainData.styleButtonBack);
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
      Box* scrollLayoutBox;
      Signal scrollLayoutSignal;
      {
        auto scrollLayout = ScopedSelectScrollLayout("options_scroll_layout", &scrollLayoutSignal, Axis2.y, Justification.min);
        auto style        = ScopedStyle(&mainData.styleButtonBook);

        scrollLayoutBox = scrollLayout.box;

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(SCREEN_HEIGHT + 8);

        void settingsListEntry(const(char)[] labelText, const(char)[] valueText, ModalCallback callback) {
          {
            auto layout = ScopedLayout("", Axis2.x, Justification.min, LayoutKind.fit_children);

            auto settingLabel = label(labelText);
            settingLabel.semanticSize[Axis2.x] = Size(SizeKind.percent_of_parent, 0.4, 1);

            auto settingButton = button(tprint("%s##%s_setting_btn", valueText.ptr, labelText.ptr));
            settingButton.box.semanticSize[Axis2.x] = SIZE_FILL_PARENT;
            settingButton.box.justification = Justification.min;

            if (settingButton.clicked) {
              openModal(mainData, callback);
            }

            spacer(8);
          }

          spacer(4);
        }

        settingsListEntry("Translation", TRANSLATION_NAMES_LONG[gSaveFile.settings.translation], (mainData, uiView) {
          bool result = false;

          foreach (i, translation; TRANSLATION_NAMES_LONG) {
            if (button(translation).clicked) {
              gSaveFile.settings.translation = cast(Translation) i;
            }

            spacer(4);
          }

          auto style = ScopedStyle(&mainData.styleButtonBack);
          if (button("Close").clicked || gUiData.input.down(Key.b)) {
            result = true;
            audioPlaySound(SoundEffect.button_back, 0.5);

            if (mainData.bible.translation != gSaveFile.settings.translation) {
              startAsyncBibleLoad(&mainData.bible, gSaveFile.settings.translation);
            }
          }

          return result;
        });

        settingsListEntry("Color Theme", COLOR_THEME_NAMES[gSaveFile.settings.colorTheme], (mainData, uiView) {
          bool result = false;

          foreach (colorTheme; enumRange!ColorTheme) {
            if (button(COLOR_THEME_NAMES[colorTheme]).clicked) {
              gSaveFile.settings.colorTheme = colorTheme;

              mainData.fadingBetweenThemes      = true;
              mainData.scrollCache.needsRepaint = true;
            }
            spacer(8);
          }

          auto style = ScopedStyle(&mainData.styleButtonBack);
          if (button("Close").clicked || gUiData.input.down(Key.b)) {
            result = true;
            audioPlaySound(SoundEffect.button_back, 0.5);

            if (mainData.bible.translation != gSaveFile.settings.translation) {
              startAsyncBibleLoad(&mainData.bible, gSaveFile.settings.translation);
            }
          }

          return result;
        });
      }

      {
        auto style = ScopedStyle(&mainData.styleButtonBack);
        if (bottomButton("Back").clicked || input.down(Key.b)) {
          audioPlaySound(SoundEffect.button_back, 0.5);
          saveSettings();

          sendCommand(CommandCode.switch_view, View.book);
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

  frameEnd();
}

extern(C) void crashHandler(ERRF_ExceptionInfo* excep, CpuRegisters* regs) {
  import ctru.console : consoleInit;
  import ctru.gfx     : GFXScreen;

  static immutable string[ERRF_ExceptionType.max+1] string_table = [
    ERRF_ExceptionType.prefetch_abort : "prefetch abort",
    ERRF_ExceptionType.data_abort     : "data abort",
    ERRF_ExceptionType.undefined      : "undefined instruction",
    ERRF_ExceptionType.vfp            : "vfp (floating point) exception",
  ];

  consoleInit(GFXScreen.bottom, null);
  printf("\x1b[1;1HException hit! - %s\n", string_table[excep.type].ptr);
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


/////////////////////////////////////
// Constants
/////////////////////////////////////

immutable string[ColorTheme.max+1] COLOR_THEME_NAMES = [
  ColorTheme.warm    : "Warm",
  ColorTheme.neutral : "Neutral",
];

immutable ui.ColorTable[ColorTheme.max+1] COLOR_THEMES = [
  ColorTheme.warm : [
    ui.Color.clear_color                      : C2D_Color32(0xED, 0xE7, 0xD5, 0xFF),
    ui.Color.text                             : C2D_Color32(0x00, 0x00, 0x00, 0xFF),
    ui.Color.bg_bg                            : C2D_Color32(0xF5, 0xEF, 0xDD, 0xFF),
    ui.Color.bg_stripes_dark                  : C2D_Color32(0xD4, 0xCC, 0xBF, 0xFF),
    ui.Color.bg_stripes_light                 : C2D_Color32(0xBF, 0xBA, 0xAC, 0xFF),
    ui.Color.button_normal                    : C2D_Color32(0xFB, 0xF7, 0xE9, 0xFF),
    ui.Color.button_sel_indicator             : C2D_Color32(0x00, 0xAA, 0x11, 0xFF),

    ui.Color.button_bottom_top                : C2D_Color32(0xBA, 0xB3, 0xA4, 0xFF),
    ui.Color.button_bottom_bottom             : C2D_Color32(0x4D, 0x49, 0x41, 0xFF),
    ui.Color.button_bottom_base               : C2D_Color32(0x6E, 0x67, 0x5B, 0xFF),
    ui.Color.button_bottom_line               : C2D_Color32(0x8C, 0x87, 0x7E, 0xFF),
    ui.Color.button_bottom_pressed_top        : C2D_Color32(0x6E, 0x6C, 0x64, 0xFF),
    ui.Color.button_bottom_pressed_bottom     : C2D_Color32(0xBF, 0xBD, 0xB2, 0xFF),
    ui.Color.button_bottom_pressed_base       : C2D_Color32(0xA6, 0xA3, 0x97, 0xFF),
    ui.Color.button_bottom_pressed_line       : C2D_Color32(0x7A, 0x79, 0x74, 0xFF),
    ui.Color.button_bottom_text               : C2D_Color32(0xF7, 0xF6, 0xF2, 0xFF),
    ui.Color.button_bottom_text_bevel         : C2D_Color32(0x11, 0x11, 0x11, 0xFF),

    // Health and safety colors
    //ui.Color.button_bottom_top                : C2D_Color32(244, 244, 240, 0xFF),
    //ui.Color.button_bottom_bottom             : C2D_Color32(199, 199, 195, 0xFF),
    //ui.Color.button_bottom_base               : C2D_Color32(228, 228, 220, 0xFF),
    //ui.Color.button_bottom_line               : C2D_Color32(158, 158, 157, 0xFF),
    //ui.Color.button_bottom_pressed_top        : C2D_Color32(0x6A, 0x6A, 0x6E, 0xFF),
    //ui.Color.button_bottom_pressed_bottom     : C2D_Color32(0xBE, 0xBE, 0xC2, 0xFF),
    //ui.Color.button_bottom_pressed_base       : C2D_Color32(0x8D, 0x8D, 0x96, 0xFF),
    //ui.Color.button_bottom_pressed_line       : C2D_Color32(0x81, 0x81, 0x82, 0xFF),
    //ui.Color.button_bottom_text               : C2D_Color32(0x11, 0x11, 0x11, 0xFF),
    //ui.Color.button_bottom_text_bevel         : C2D_Color32(0xFF, 0xFF, 0xFF, 0xFF),

    ui.Color.button_bottom_above_fade         : C2D_Color32(0xF2, 0xF2, 0xF7, 0x80),
    ui.Color.scroll_indicator                 : C2D_Color32(0xC1, 0xBF, 0x66, 0xFF),
    ui.Color.scroll_indicator_outline         : C2D_Color32(0xEF, 0xF1, 0xE1, 0xFF),
    ui.Color.scroll_indicator_pushing         : C2D_Color32(0xDD, 0x9A, 0x20, 0xFF),
    ui.Color.scroll_indicator_pushing_outline : C2D_Color32(0xE3, 0xBD, 0x78, 0xFF),
  ],
  ColorTheme.neutral : [
    ui.Color.clear_color                      : C2D_Color32(0xEE, 0xEE, 0xEE, 0xFF),
    ui.Color.text                             : C2D_Color32(0x00, 0x00, 0x00, 0xFF),
    ui.Color.bg_bg                            : C2D_Color32(0xF5, 0xF5, 0xF5, 0xFF),
    ui.Color.bg_stripes_dark                  : C2D_Color32(0xD0, 0xD0, 0xD4, 0xFF),
    ui.Color.bg_stripes_light                 : C2D_Color32(0xC5, 0xC5, 0xBD, 0xFF),
    ui.Color.button_normal                    : C2D_Color32(0xFF, 0xFF, 0xFF, 0xFF),
    ui.Color.button_sel_indicator             : C2D_Color32(0x00, 0xAA, 0x11, 0xFF),
    ui.Color.button_bottom_top                : C2D_Color32(0xB6, 0xB6, 0xBA, 0xFF),
    ui.Color.button_bottom_bottom             : C2D_Color32(0x48, 0x48, 0x4C, 0xFF),
    ui.Color.button_bottom_base               : C2D_Color32(0x66, 0x66, 0x6E, 0xFF),
    ui.Color.button_bottom_line               : C2D_Color32(0x8B, 0x8B, 0x8C, 0xFF),
    ui.Color.button_bottom_pressed_top        : C2D_Color32(0x6E, 0x6E, 0x6A, 0xFF),
    ui.Color.button_bottom_pressed_bottom     : C2D_Color32(0xC0, 0xC0, 0xBC, 0xFF),
    ui.Color.button_bottom_pressed_base       : C2D_Color32(0xA5, 0xA5, 0x9E, 0xFF),
    ui.Color.button_bottom_pressed_line       : C2D_Color32(0x7B, 0x7B, 0x7B, 0xFF),
    ui.Color.button_bottom_text               : C2D_Color32(0xF2, 0xF2, 0xF7, 0xFF),
    ui.Color.button_bottom_text_bevel         : C2D_Color32(0x11, 0x11, 0x11, 0xFF),
    ui.Color.button_bottom_above_fade         : C2D_Color32(0xF2, 0xF2, 0xF7, 0x80),
    ui.Color.scroll_indicator                 : C2D_Color32(0x66, 0xAD, 0xC1, 0xFF),
    ui.Color.scroll_indicator_outline         : C2D_Color32(0xE1, 0xED, 0xF1, 0xFF),
    ui.Color.scroll_indicator_pushing         : C2D_Color32(0xDD, 0x80, 0x20, 0xFF),
    ui.Color.scroll_indicator_pushing_outline : C2D_Color32(0xE3, 0xAE, 0x78, 0xFF),
  ],
];

enum DEFAULT_PAGE_TEXT_SIZE = 0.5;
enum DEFAULT_PAGE_MARGIN    = 8;

enum BOOK_BUTTON_WIDTH      = 200.0f;
enum BOOK_BUTTON_MARGIN     = 8.0f;
enum BOTTOM_BUTTON_MARGIN   = 6.0f;