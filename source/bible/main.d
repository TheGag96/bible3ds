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
  search,
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
  View[8] viewStack;
  size_t viewStackIndex;
  UiView[View.max+1] views;
  UiView modal;
  ModalCallback modalCallback;
  bool renderModal;
  ui.ScrollCache scrollCache;

  float size = 0;

  bool needLoadPage;
  PageId pageId, pendingPageId;
  int jumpVerseRequest;
  ui.LoadedPage loadedPage;

  bool frameNeedsRender;

  Thread threadHandleJob;

  JobHandle!bibleLoad jobBibleLoad;
  BibleLoadData* bible;

  ui.ColorTable colorTable;
  bool fadingBetweenThemes;
  ui.BoxStyle styleButtonBook, styleButtonBottom, styleButtonBack, styleButtonList, stylePage, styleVerse;

  JobHandle!bibleSearch jobBibleSearch;
  Arena searchArena;
  BibleSearchResults* searchResults;
}
MainData mainData;

struct SearchResult {
  SearchResult* next;
  BibleLoc loc;
  char[] locString;
  char[] verseText;
}

enum SOC_ALIGN      = 0x1000;
enum SOC_BUFFERSIZE = 0x100000;

uint* SOC_buffer = null;

extern(C) void* memalign(size_t, size_t);

extern(C) int main(int argc, char** argv) {
  threadOnException(&crashHandler,
                    RUN_HANDLER_ON_FAULTING_STACK,
                    WRITE_DATA_TO_FAULTING_STACK);

  gNullInput = cast(Input*) &gNullInputStore;

  gTempStorage = arenaMake(kilobytes(16));

  // Init libs
  romfsInit();

  Result saveResult = saveFileInit();
  assert(!saveResult, "file creation failed");

  LightLock_Init(&sMutexBibleData);
  LightSemaphore_Init(&sWorkToDoSem, initial_count : 0, max_count : sWorkQueue.length);
  LightSemaphore_Init(&sWorkingSem,  initial_count : 1, max_count : 1);

  sArenaBibleLoad = arenaMake(megabytes(16));

  mainData.threadHandleJob = threadCreate(&threadWork, null, kilobytes(16), 0x31, -2, true);

  // Try to start loading the Bible as soon as possible asynchronously
  mainData.jobBibleLoad = startJob!bibleLoad(gSaveFile.settings.translation);

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

  // Start profiling here, which will make the first frame of profile data bogus.
  // Below, endProfileAndLog is called before syncing to the frame, followed by another beginProfile call. The point is
  // to not include the time waiting to sync to the frame prior to drawing in the profile data.
  beginProfile();

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
    arenaClear(&gTempStorage);

    void* bibleLoadJustDone;
    getJobResult!bibleLoad(  &mainData.jobBibleLoad,   &bibleLoadJustDone);
    auto searchResultsOld = mainData.searchResults;
    getJobResult!bibleSearch(&mainData.jobBibleSearch, &mainData.searchResults);
    bool bibleSearchJustDone = searchResultsOld != mainData.searchResults;

    // Idle optimization
    // @TODO: Make smarter / less brittle with regard to animations!
    if (input.framesNoInput > 60 && !bibleLoadJustDone && !bibleSearchJustDone) {
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

      // Render the scene
      // Don't include time spent waiting in C3D_FrameBegin in the profiling data.
      endProfileAndLog();
      C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
      beginProfile();

      mixin(timeBlock("render"));
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
        C3D_StencilTest(false, GPUTestFunc.always, 0, 0, 0);
        C3D_SetScissor(GPUScissorMode.disable, 0, 0, 0, 0);
        if (mainData.renderModal) ui.render(modalUiData, GFXScreen.top, GFX3DSide.left, _3DEnabled, slider, 0.1);
        ui.drawBackground(
          GFXScreen.top, GFX3DSide.left, slider, mainData.colorTable[ui.Color.bg_bg],
          mainData.colorTable[ui.Color.bg_stripes_dark], mainData.colorTable[ui.Color.bg_stripes_light], 0,
        );
        ui.render(mainUiData,  GFXScreen.top, GFX3DSide.left, _3DEnabled, slider);
      }

      if (_3DEnabled) {
        mixin(timeBlock("render > right"));
        C2D_TargetClear(topRight, mainData.colorTable[ui.Color.clear_color]);
        C2D_SceneBegin(topRight);
        C3D_StencilTest(false, GPUTestFunc.always, 0, 0, 0);
        C3D_SetScissor(GPUScissorMode.disable, 0, 0, 0, 0);
        if (mainData.renderModal) ui.render(modalUiData, GFXScreen.top, GFX3DSide.right, _3DEnabled, slider, 0.1);
        ui.drawBackground(
          GFXScreen.top, GFX3DSide.right, slider, mainData.colorTable[ui.Color.bg_bg],
          mainData.colorTable[ui.Color.bg_stripes_dark], mainData.colorTable[ui.Color.bg_stripes_light], 0,
        );
        ui.render(mainUiData,  GFXScreen.top, GFX3DSide.right, _3DEnabled, slider);
      }

      {
        mixin(timeBlock("render > bottom"));
        C2D_TargetClear(bottom, mainData.colorTable[ui.Color.clear_color]);
        C2D_SceneBegin(bottom);
        C3D_StencilTest(false, GPUTestFunc.always, 0, 0, 0);
        C3D_SetScissor(GPUScissorMode.disable, 0, 0, 0, 0);
        if (mainData.renderModal) ui.render(modalUiData, GFXScreen.bottom, GFX3DSide.left, false, 0, 0.1);
        ui.drawBackground(
          GFXScreen.bottom, GFX3DSide.left, slider, mainData.colorTable[ui.Color.bg_bg],
          mainData.colorTable[ui.Color.bg_stripes_dark], mainData.colorTable[ui.Color.bg_stripes_light], 0
        );
        ui.render(mainUiData,  GFXScreen.bottom, GFX3DSide.left, false, 0);
      }
    }

    {
      mixin(timeBlock("C3D_FrameEnd"));
      C3D_FrameEnd(0);
    }
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

  colorTable = COLOR_THEMES[gSaveFile.settings.colorTheme];

  styleButtonBook                    = ui.BoxStyle.init;
  styleButtonBook.colors             = colorTable;
  styleButtonBook.margin             = Vec2(BOOK_BUTTON_MARGIN);
  styleButtonBook.textSize           = 0.5f;

  styleButtonBottom                  = styleButtonBook;
  styleButtonBottom.margin           = Vec2(BOTTOM_BUTTON_MARGIN);
  styleButtonBottom.textSize         = 0.6f;

  styleButtonList                  = styleButtonBook;
  styleButtonList.margin           = Vec2(4);
  styleButtonList.textSize         = DEFAULT_PAGE_TEXT_SIZE;

  // @Hack: Gets played manually by builder code so that it plays on pressing B. Consider revising...
  styleButtonBack                    = styleButtonBottom;
  styleButtonBack.soundButtonPressed = SoundPlay(SoundEffect.none, 0);

  stylePage                          = styleButtonBook;
  stylePage.margin                   = Vec2(DEFAULT_PAGE_MARGIN);
  stylePage.textSize                 = DEFAULT_PAGE_TEXT_SIZE;

  styleVerse                         = styleButtonBook;
  styleVerse.soundButtonDown         = SoundPlay.init;
  styleVerse.soundButtonPressed      = SoundPlay.init;
  styleVerse.soundButtonOff          = SoundPlay.init;

  searchArena                        = arenaMake(kilobytes(128));
}}

void loadBiblePage(MainData* mainData) { with (mainData) {
  if (pendingPageId == pageId && !needLoadPage) return;

  OpenBook* book = &bible.books[pendingPageId.book];

  if (pendingPageId.chapter < 0) {
    pendingPageId.chapter = book.chapters.length + pendingPageId.chapter;
  }

  ui.loadPage(&loadedPage, book.chapters[pendingPageId.chapter], pendingPageId.chapter, &stylePage);
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

  pageId = pendingPageId;
  needLoadPage = false;
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

  if (pageId != newPageId) {
    mainData.needLoadPage  = true;
    mainData.pendingPageId = newPageId;
  }
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
    none,
    switch_view,
    go_to_previous_view,
    open_book,
    start_search,
  }

  static void sendOpenBookCommand(BibleLoc value, UiData* uiData = gUiData) {
    sendCommand(CommandCode.open_book, *cast(uint*)&value, uiData);
  }

  void doViewSwitch(View view) {
    if (view != mainData.curView && mainData.viewStackIndex < mainData.viewStack.length)
    {
      mainData.viewStack[mainData.viewStackIndex++] = mainData.curView;
    }
    mainData.curView = view;
  }

  enum LOAD_BOOK_PROGRESS = 0;

  mainData.bible = bibleDataGet();
  scope(exit) bibleDataRelease(&mainData.bible);

  Command command;
  while (true) {
    command = getCommand();
    if (!command.code) break;

    final switch (cast(CommandCode) command.code) {
      case CommandCode.none: break;
      case CommandCode.switch_view:
        doViewSwitch(cast(View) command.value);
        break;
      case CommandCode.go_to_previous_view:
        auto thing = &mainData;
        if (mainData.viewStackIndex > 0) {
          mainData.curView = mainData.viewStack[--mainData.viewStackIndex];
        }
        else {
          mainData.curView = cast(View) 0;
        }
        break;
      case CommandCode.open_book:
        doViewSwitch(View.reading);

        BibleLoc loc = *(cast(BibleLoc*) &command.value);

        if (loc.chapter == LOAD_BOOK_PROGRESS) {
          loc.chapter = gSaveFile.progress[loc.book].chapter;
          loc.verse   = gSaveFile.progress[loc.book].verse;
        }

        mainData.needLoadPage     = true;
        mainData.pendingPageId    = PageId(gSaveFile.settings.translation, loc.book, loc.chapter);
        mainData.jumpVerseRequest = loc.verse;
        break;
      case CommandCode.start_search:
        if (mainData.jobBibleSearch.value) {
          // @TODO: Ughhhhh waiting like this sucks but if I want to allocate the search string on the search arena, I
          // have no choice!!
          cancelJob(&mainData.jobBibleSearch);
          waitOnAllJobs();
        }

        arenaClear(&mainData.searchArena);
        const(char)[] searchString = getKeyboardInput(&mainData.searchArena);

        if (searchString.length) {
          mainData.searchResults = null;
          mainData.jobBibleSearch = startJob!bibleSearch(&mainData.searchArena, searchString);
          doViewSwitch(View.search);
        }
        break;
    }
  }

  // @TODO: Should this be handled as a UI command?
  if (!mainData.modalCallback && mainData.curView == View.reading && mainData.bible) {
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

      auto mainLayout = ScopedCombinedScreenSplitLayout(
        "lt_modal_main", "lt_modal_left", "lt_modal_center", "lt_modal_right"
      );
      mainLayout.startCenter();

      auto split = ScopedDoubleScreenSplitLayout(
        "lt_modal_split_main", "lt_modal_split_top", "lt_modal_split_bottom"
      );
      split.startBottom();
      split.bottom.justification = Justification.center;

      spacer();
      {
        auto modalLayout = ScopedLayout("lt_modal_container", Axis2.y);
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

  auto mainLayout = ScopedCombinedScreenSplitLayout("lt_main", "lt_left", "lt_center", "lt_right");
  mainLayout.startCenter();

  final switch (mainData.curView) {
    case View.book:
      Box* scrollLayoutBox;
      Signal scrollLayoutSignal;
      bool pushingAgainstScrollLimit = false;

      {
        auto scrollLayout = ScopedScrollLayout("lt_book_scroll", &scrollLayoutSignal, Axis2.y);

        scrollLayoutBox = scrollLayout.box;
        scrollLayoutBox.depth = -1;

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(SCREEN_HEIGHT + 8);

        {
          auto horziontalLayout = ScopedLayout("lt_book_grid_horiz", Axis2.x, justification : Justification.min, layoutKind : LayoutKind.fit_children);

          Signal leftColumnSignal;
          {
            auto leftColumn = ScopedSelectLayout("lt_book_grid_left", &leftColumnSignal, Axis2.y);

            foreach (i, book; BOOK_NAMES) {
              if (i % 2 == 0) {
                auto bookButton = button(book, 150, extraFlags : BoxFlags.selectable);

                // Select the first book button if nothing else is
                if (i == 0 && boxIsNull(gUiData.hot)) gUiData.hot = bookButton.box;

                if (bookButton.clicked) {
                  sendOpenBookCommand(BibleLoc(cast(Book)i, LOAD_BOOK_PROGRESS, 0));
                }

                spacer(8);
              }
            }
          }
          pushingAgainstScrollLimit |= leftColumnSignal.pushingAgainstScrollLimit;

          Signal rightColumnSignal;
          {
            auto rightColumn = ScopedSelectLayout("lt_book_grid_right", &rightColumnSignal, Axis2.y);

            foreach (i, book; BOOK_NAMES) {
              if (i % 2 == 1) {
                auto bookButton = button(book, 150, extraFlags : BoxFlags.selectable);
                if (bookButton.clicked) {
                  sendOpenBookCommand(BibleLoc(cast(Book)i, LOAD_BOOK_PROGRESS, 0));
                }

                spacer(8);
              }
            }
          }
          pushingAgainstScrollLimit |= rightColumnSignal.pushingAgainstScrollLimit;

          // Allow hopping columns
          Box* oppositeColumn = gUiData.hot.parent == leftColumnSignal.box ? rightColumnSignal.box : leftColumnSignal.box;
          if (gUiData.input.scrollMethodCur != ScrollMethod.touch && gUiData.input.downOrRepeat(Key.left | Key.right)) {
            gUiData.hot = getChild(oppositeColumn, gUiData.hot.childId);
            audioPlaySound(SoundEffect.button_move, 0.05);
          }
        }
      }
      pushingAgainstScrollLimit |= scrollLayoutSignal.pushingAgainstScrollLimit;

      {
        auto bottomLayout = ScopedLayout(
          "lt_book_bottom", Axis2.x, Justification.center, LayoutKind.fit_children
        );
        auto style = ScopedStyle(&mainData.styleButtonBottom);

        if (bottomButton("Options").clicked) {
          sendCommand(CommandCode.switch_view, View.options);
        }

        if (bottomButton("Bookmarks").clicked) {
          openModal(mainData, (MainData* mainData, UiView* uiView) {
            bool result = false;

            Signal scrollSignal;
            {
              auto scrollLayout = ScopedScrollLayout("lt_chapter_scroll", &scrollSignal, Axis2.y, Justification.min,    LayoutKind.fill_parent);

              label("Bookmarks", Justification.center).semanticSize[Axis2.x] = SIZE_FILL_PARENT;

              foreach (i, bookmark; gSaveFile.bookmarks[0..gSaveFile.numBookmarks]) {
                if (listButton(tprint("%s %d:%d##bookmark_%d", BOOK_NAMES[bookmark.book].ptr, bookmark.chapter, bookmark.verse, i)).clicked) {
                  sendOpenBookCommand(
                    BibleLoc(bookmark.book, bookmark.chapter, bookmark.verse),
                    &mainData.views[View.book].uiData
                  );
                  result = true;
                }
              }
            }

            if (gUiData.input.down(Key.b) && boxIsNull(gUiData.active)) {
              result = true;

              audioPlaySound(SoundEffect.button_back, 0.5);
            }

            return result;
          });
        }

        if (bottomButton("Search").clicked) {
          sendCommand(CommandCode.start_search, 0);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout("lt_book_right_split_main", "lt_book_right_split_top", "lt_book_split_bottom");

        rightSplit.startTop();

        scrollIndicator("book_scroll_indicator", scrollLayoutBox, Justification.max, pushingAgainstScrollLimit);
      }

      break;

    case View.reading:
      if (mainData.bible) {
        loadBiblePage(mainData);

        Signal readPaneSignal;
        with (mainData.loadedPage) {
          // @HACK: Cancel selecting a verse with circle/D-pad
          //        May need to reconsider this UX / fold some new behavior into the core code.
          if (boxIsNull(gUiData.active) && input.scrollMethodCur == ScrollMethod.none && input.down(Key.up | Key.down)) {
            gUiData.hot = gNullBox;
          }

          auto readPane = ScopedScrollableReadPane("reading_scroll_read_view", &readPaneSignal, mainData.loadedPage, &mainData.scrollCache, &mainData.jumpVerseRequest);
          readPane.box.depth = -1;

          auto verseStyle = ScopedStyle(&mainData.styleVerse);

          spacer(style.margin.y + glyphSize.y + SCREEN_HEIGHT);

          // Overlay invisible boxes on top of each verse
          auto curVerseStart = actualLineNumberTable[1];
          int firstVerseLine = 1;
          int curVerse;
          foreach (i; 2..actualLineNumberTable.length + 1) {  // Spooky-but-intentional + 1
            if (i == actualLineNumberTable.length ||
                actualLineNumberTable[i].textLineIndex != curVerseStart.textLineIndex)
            {
              auto height =  (i - firstVerseLine) * glyphSize.y;
              int verse = curVerseStart.textLineIndex;
              if (i != actualLineNumberTable.length) {
                curVerseStart = actualLineNumberTable[i];
              }
              firstVerseLine = i;

              // Generate a unique verse ID for each selectable. If they were just by verse or chapter, then these might
              // carry state between chapter/book switches.
              BibleLoc verseLoc = { mainData.pageId.book, cast(ubyte) mainData.pageId.chapter, cast(ushort) verse };
              uint verseUnique = *cast(uint*)&verseLoc;
              auto button = button(tnum("##read_pane_verse_", verseUnique), extraFlags : BoxFlags.selectable | BoxFlags.select_toggle | BoxFlags.select_falling_edge);
              button.box.render = &renderVerse;
              button.box.userVal = verse;
              button.box.semanticSize = [SIZE_FILL_PARENT, Size(SizeKind.pixels, height)].s;
            }
          }
        }
        mainData.loadedPage.scrollInfo = readPaneSignal.box.scrollInfo;

        // @HACK: Cancel selecting a verse with touch scrolling
        if (input.scrollMethodCur == ScrollMethod.touch) {
          gUiData.hot = gNullBox;
        }

        {
          auto bottomLayout = ScopedLayout("lt_reading_bottom", Axis2.x, Justification.center, LayoutKind.fit_children);
          auto bottomStyle  = ScopedStyle(&mainData.styleButtonBottom);

          {
            auto backStyle = ScopedStyle(&mainData.styleButtonBack);

            if (bottomButton("Back").clicked || (gUiData.input.down(Key.b) && boxIsNull(gUiData.active))) {
              auto scrollInfo = &mainData.loadedPage.scrollInfo;

              auto foundIndex = mainData.loadedPage.actualLineNumberTable.length-1;
              foreach (i, ref lineEntry; mainData.loadedPage.actualLineNumberTable) {
                if (lineEntry.realPos > scrollInfo.offset) {
                  foundIndex = i;
                  break;
                }
              }
              if (foundIndex > 0) foundIndex--;
              int curVerse = mainData.loadedPage.actualLineNumberTable[foundIndex].textLineIndex;

              gSaveFile.progress[mainData.pageId.book] = Progress(cast(ubyte) mainData.pageId.chapter, cast(ubyte) curVerse);
              saveSettings();

              sendCommand(CommandCode.go_to_previous_view, 0);
              audioPlaySound(SoundEffect.button_back, 0.5);
            }
          }

          if (bottomButton("Chapters").clicked) {
            openModal(mainData, (MainData* mainData, UiView* uiView) {
              enum CHAPTERS_PER_ROW    = 5;
              enum CHAPTER_BUTTON_SIZE = 40;

              bool result = false;

              Signal scrollSignal;
              auto scrollLayout = ScopedScrollLayout("lt_chapter_scroll", &scrollSignal, Axis2.y, Justification.min,    LayoutKind.fill_parent);
              auto horizLayout  = ScopedLayout(      "lt_chapter_horiz",                 Axis2.x, Justification.center, LayoutKind.fit_children);
              auto vertLayout   = ScopedLayout(      "lt_chapter_vert",                  Axis2.y, Justification.center, LayoutKind.grow_children);

              auto numChapters = mainData.bible.books[mainData.pageId.book].chapters.length - 1; // Minus 1 because the 0th chapter is a dummy
              auto numRows = (numChapters + CHAPTERS_PER_ROW - 1) / CHAPTERS_PER_ROW;

              label("Chapters");

              foreach (row; 0..numRows) {
                spacer(4);

                {
                  auto rowLayout = ScopedLayout(tnum("lt_chapter_row_", row), Axis2.x, Justification.center, LayoutKind.grow_children);
                  // @TODO: Reconsider the meaning of LayoutKind.grow_children to do this instead?
                  rowLayout.box.semanticSize[] = SIZE_CHILDREN_SUM;

                  auto numInRow = min(numChapters - CHAPTERS_PER_ROW * row, CHAPTERS_PER_ROW);
                  foreach (chapter; row * CHAPTERS_PER_ROW + 1..row * CHAPTERS_PER_ROW + numInRow + 1) {
                    if (chapter != row * CHAPTERS_PER_ROW + 1) spacer(2);

                    auto chapterButton = button(tnum(chapter));
                    chapterButton.box.semanticSize[] = Size(SizeKind.pixels, CHAPTER_BUTTON_SIZE, 1);

                    if (chapterButton.clicked) {
                      sendOpenBookCommand(
                        BibleLoc(mainData.pageId.book, cast(ubyte) chapter, 0),
                        &mainData.views[View.reading].uiData,
                      );
                      result = true;
                    }
                  }

                  // @HACK: Add empty spaces to fill the rest of the row
                  foreach (i; 0..CHAPTERS_PER_ROW - numInRow) {
                    spacer(2 + CHAPTER_BUTTON_SIZE);
                  }
                }
              }

              spacer(4);

              if (gUiData.input.down(Key.b) && boxIsNull(gUiData.active)) {
                result = true;

                audioPlaySound(SoundEffect.button_back, 0.5);
              }

              return result;
            });
          }

          if (gUiData.hot.parent == readPaneSignal.box) {
            // Verse selected
            size_t bookmarkIndex = size_t.max;
            Bookmark potentialBookmark = Bookmark(
              mainData.pageId.book, Progress(cast(ubyte) mainData.pageId.chapter, cast(ubyte) gUiData.hot.userVal)
            );
            foreach (i, ref bookmark; gSaveFile.bookmarks[0..gSaveFile.numBookmarks]) {
              if (bookmark == potentialBookmark) {
                bookmarkIndex = i;
                break;
              }
            }

            if (bookmarkIndex == size_t.max) {
              if (bottomButton("Bookmark").clicked) {
                // @TODO Do something different at boomark limit...
                if (gSaveFile.numBookmarks < gSaveFile.bookmarks.length) {
                  gSaveFile.bookmarks[gSaveFile.numBookmarks++] = potentialBookmark;
                }
                saveSettings();
              }
            }
            else {
              if (bottomButton("Unbookmark").clicked) {
                foreach (i; bookmarkIndex..gSaveFile.numBookmarks-1) {
                  gSaveFile.bookmarks[i] = gSaveFile.bookmarks[i+1];
                }
                gSaveFile.numBookmarks--;
                saveSettings();
              }
            }
          }
        }

        mainLayout.startRight();

        {
          auto rightSplit = ScopedDoubleScreenSplitLayout("lt_reading_right_split_main", "lt_reading_right_split_top", "lt_reading_right_split_bottom");

          rightSplit.startTop();

          scrollIndicator("reading_scroll_indicator", readPaneSignal.box, Justification.min, readPaneSignal.pushingAgainstScrollLimit);
        }
      }
      else {
        // Bible data is still loading.
        // @TODO: Prettify
        {
          auto searchingLayout = ScopedLayout("lt_loading", Axis2.y);
          searchingLayout.semanticSize[Axis2.y] = Size(SizeKind.pixels, SCREEN_HEIGHT, 1);

          spacer();
          label("Loading...");
          spacer();
        }

        spacer();

        {
          auto bottomLayout = ScopedLayout("lt_reading_bottom", Axis2.x, Justification.center, LayoutKind.fit_children);
          auto bottomStyle  = ScopedStyle(&mainData.styleButtonBottom);

          {
            auto backStyle = ScopedStyle(&mainData.styleButtonBack);

            if (bottomButton("Back").clicked || (gUiData.input.down(Key.b) && boxIsNull(gUiData.active))) {
              sendCommand(CommandCode.go_to_previous_view, 0);
              audioPlaySound(SoundEffect.button_back, 0.5);
            }
          }
        }
      }


      break;

    case View.options:
      Box* scrollLayoutBox;
      Signal scrollLayoutSignal;
      {
        auto scrollLayout = ScopedSelectScrollLayout("lt_options_scroll", &scrollLayoutSignal, Axis2.y, Justification.min);
        auto style        = ScopedStyle(&mainData.styleButtonBook);

        scrollLayoutBox = scrollLayout.box;

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(SCREEN_HEIGHT + 8);

        void settingsListEntry(const(char)[] labelText, const(char)[] valueText, ModalCallback callback) {
          {
            auto layout = ScopedLayout(tconcat("lt_settings_entry_", labelText), Axis2.x, Justification.min, LayoutKind.fit_children);

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

          if (button("Close").clicked || (gUiData.input.down(Key.b) && boxIsNull(gUiData.active))) {
            result = true;
            audioPlaySound(SoundEffect.button_back, 0.5);

            if (!mainData.bible || mainData.bible.translation != gSaveFile.settings.translation) {
              cancelJob(&mainData.jobBibleLoad);
              mainData.jobBibleLoad = startJob!bibleLoad(gSaveFile.settings.translation);
            }
          }

          return result;
        });

        settingsListEntry("Color Theme", COLOR_THEME_NAMES[gSaveFile.settings.colorTheme], (mainData, uiView) {
          bool result = false;

          nColumnGrid("lt_color_theme_", 2, enumRange!ColorTheme, (ColorTheme colorTheme) {
            if (colorThemePreviewButton(colorTheme).clicked) {
              gSaveFile.settings.colorTheme = colorTheme;

              mainData.fadingBetweenThemes      = true;
              mainData.scrollCache.needsRepaint = true;
            }
            spacer(4);
          });

          if (button("Close").clicked || (gUiData.input.down(Key.b) && boxIsNull(gUiData.active))) {
            result = true;
            audioPlaySound(SoundEffect.button_back, 0.5);
          }

          return result;
        });
      }

      {
        auto style = ScopedStyle(&mainData.styleButtonBack);
        if (bottomButton("Back").clicked || (gUiData.input.down(Key.b) && boxIsNull(gUiData.active))) {
          audioPlaySound(SoundEffect.button_back, 0.5);
          saveSettings();

          sendCommand(CommandCode.go_to_previous_view, 0);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout("lt_options_right_split_main", "lt_options_right_split_top", "lt_options_right_split_bottom");

        rightSplit.startTop();

        scrollIndicator("book_scroll_indicator", scrollLayoutBox, Justification.max, scrollLayoutSignal.pushingAgainstScrollLimit);
      }
      break;

    case View.search:
      Box* scrollLayoutBox;
      Signal scrollLayoutSignal;

      if (mainData.searchResults) {
        mixin(timeBlock("search result ui"));

        enum float  SEARCH_RESULT_BUTTON_SIZE = 46;
        enum size_t SEARCH_RESULTS_PER_SCREEN = cast(size_t) (2 * SCREEN_HEIGHT / SEARCH_RESULT_BUTTON_SIZE) + 2;

        auto scrollLayout = ScopedSelectScrollLayout("search_scroll_layout", &scrollLayoutSignal, Axis2.y, Justification.min);
        scrollLayoutBox = scrollLayout.box;

        auto resultsRange = linkedRange(mainData.searchResults.list);
        int i = 0;

        int numToSkip = clamp(cast(int) (max(scrollLayoutBox.scrollInfo.offset - SCREEN_HEIGHT, 0) / SEARCH_RESULT_BUTTON_SIZE) - 1, 0, cast(int) mainData.searchResults.count);

        {
          mixin(timeBlock("search result ll skip"));
          foreach (a; 0..numToSkip) {
            resultsRange.popFront;
          }
          i += numToSkip;
        }

        // Really easy lo-fi way to force the book buttons to be selectable on the bottom screen
        spacer(SCREEN_HEIGHT + SEARCH_RESULT_BUTTON_SIZE * numToSkip);

        float maxTextWidth = SCREEN_BOTTOM_WIDTH - 2 * mainData.styleButtonList.margin.x;
        foreach (result; resultsRange) {
          Box* layoutBox;
          {
            auto style = ScopedStyle(&mainData.styleButtonList);
            auto layout = ScopedListButtonLayout(
              tnum("searchres_", i),
              Axis2.y, Justification.min, LayoutKind.grow_children, BoxFlags.bible_text
            );
            layoutBox = layout.box;
            layoutBox.semanticSize[Axis2.y] = Size(SizeKind.pixels, SEARCH_RESULT_BUTTON_SIZE, 1);

            label(result.locString);

            auto verseFirstLine = C2D_CalcTextWrapFirstLine(
              null, mainData.styleButtonList.textSize,
              result.verseText, maxTextWidth, C2D_ParseFlags.bible
            );
            label(verseFirstLine);
          }

          if (signalFromBox(layoutBox).clicked) {
            sendOpenBookCommand(result.loc);
          }

          i++;
          if (i > numToSkip + SEARCH_RESULTS_PER_SCREEN) break;
        }

        float bottomSpacer = max(SEARCH_RESULT_BUTTON_SIZE * (cast(int) mainData.searchResults.count - i), 0);
        spacer(bottomSpacer);
      }
      else {
        // @TODO: Prettify
        {
          auto searchingLayout = ScopedLayout("lt_searching", Axis2.y);
          searchingLayout.semanticSize[Axis2.y] = Size(SizeKind.pixels, SCREEN_HEIGHT, 1);

          spacer();
          label("Searching...");
          spacer();
        }

        spacer();
      }

      {
        auto style = ScopedStyle(&mainData.styleButtonBack);
        if (bottomButton("Back").clicked || input.down(Key.b)) {
          sendCommand(CommandCode.go_to_previous_view, 0);
          audioPlaySound(SoundEffect.button_back, 0.5);
        }
      }

      mainLayout.startRight();

      {
        auto rightSplit = ScopedDoubleScreenSplitLayout("search_right_split_layout_main", "search_right_split_layout_top", "search_right_split_layout_bottom");

        rightSplit.startTop();

        scrollIndicator("search_scroll_indicator", scrollLayoutBox, Justification.max, scrollLayoutSignal.pushingAgainstScrollLimit);
      }
      break;
  }

  frameEnd();
}

ui.Signal colorThemePreviewButton(ColorTheme colorTheme) {
  import bible.imgui;

  void fakeBottomButton(const(char)[] text) {
    Box* box = makeBox(BoxFlags.draw_text, text);

    box.semanticSize[] = [SIZE_FILL_PARENT, Size(SizeKind.text_content, 0, 1)].s;
    box.justification = Justification.center;
    box.render = &renderBottomButton;
  }

  static Vec2 renderPlainBackground(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 drawOffset, float z) {
    auto rect = box.rect + drawOffset;
    C2D_DrawRectSolid(rect.left, rect.top, z, rect.right - rect.left, rect.bottom - rect.top, box.style.colors[Color.clear_color]);
    return Vec2(0);
  }

  Box* layoutBox;
  {
    auto previewStyle = push!BoxStyle(&gUiData.frameArena);
    *previewStyle = mainData.styleButtonBook;
    previewStyle.colors = COLOR_THEMES[colorTheme];
    previewStyle.margin   *= 4.0/5;
    previewStyle.textSize *= 0.9;

    auto previewStyleBottom = push!BoxStyle(&gUiData.frameArena);
    *previewStyleBottom = mainData.styleButtonBottom;
    previewStyleBottom.colors = COLOR_THEMES[colorTheme];
    previewStyleBottom.margin   *= 4.0/5;
    previewStyleBottom.textSize *= 0.9;

    auto style = ScopedStyle(previewStyle);

    auto layout = ScopedButtonLayout(
      tnum("btn_lt_color_theme_preview_", colorTheme),
      Axis2.y, Justification.center, LayoutKind.grow_children
    );
    layoutBox = layout.box;

    spacer(8);

    {
      auto innerLayout1 = ScopedLayout(
        tnum("lt_color_theme_preview_inner_1_", colorTheme),
        Axis2.x, Justification.center, LayoutKind.fit_children
      );

      spacer(8);
      {
        auto innerLayout2 = ScopedLayout(
          tnum("lt_color_theme_preview_inner_2_", colorTheme),
          Axis2.y, Justification.min, LayoutKind.grow_children
        );
        innerLayout2.render = &renderPlainBackground;

        {
          auto innerLayout3 = ScopedLayout(
            tnum("lt_color_theme_preview_inner_3_", colorTheme),
            Axis2.x, Justification.min, LayoutKind.fit_children
          );
          innerLayout3.scrollInfo.limitMin = 0;
          innerLayout3.scrollInfo.limitMax = 1;

          label("In the beginning...").semanticSize[Axis2.x] = SIZE_FILL_PARENT;

          scrollIndicator("", innerLayout3.box, Justification.max, false).semanticSize[Axis2.x] = Size(SizeKind.pixels, 1, 1);
        }

        {
          auto bottomStyle = ScopedStyle(previewStyleBottom);
          fakeBottomButton("Options##");
        }
      }
      spacer(8);
    }

    label(COLOR_THEME_NAMES[colorTheme]);
  }

  return signalFromBox(layoutBox);
}

// @TODO: Consider not doing the range looping here and making the caller do it?
void nColumnGrid(Range, Value)(const(char)[] idPrefix, int numCols, Range range, scope void delegate(Value value) @nogc nothrow func) {
  import bible.imgui;

  auto horziontalLayout = ScopedLayout(tconcat(idPrefix, "grid"), Axis2.x, justification : Justification.min, layoutKind : LayoutKind.fit_children);

  foreach (a; 0..numCols) {
    auto inner = ScopedLayout(tprint("%sgrid_inner_%d", idPrefix.ptr, a), Axis2.y);

    int b = 0;
    foreach (value; range) {
      if (b % numCols == a) {
        func(value);
      }

      b++;
    }
  }
}

char[] getKeyboardInput(Arena* arena, size_t maxCharacters = 64) {
  import core.stdc.string : strlen;

  SWKBDState swkbd;
  swkbdInit(&swkbd, SWKBDType.western, 2, -1);
  swkbdSetValidation(&swkbd, SWKBDValidInput.notempty_notblank, 0, 0);
  swkbdSetFeatures(&swkbd, SWKBD_DARKEN_TOP_SCREEN | SWKBD_ALLOW_HOME | SWKBD_ALLOW_RESET | SWKBD_ALLOW_POWER);

  ubyte[] buffer = remaining(arena)[0..min($, maxCharacters+1)];  // Leave room for the null-terminator
  char[]  str    = (cast(char*) buffer.ptr)[0..buffer.length];

  bool shouldQuit = false;
  do {
    swkbdSetInitialText(&swkbd, "");
    SWKBDButton button = swkbdInputText(&swkbd, str.ptr, str.length);

    if (button != SWKBDButton.none) break;

    SWKBDResult res = swkbdGetResult(&swkbd);
    if (res == SWKBDResult.resetpressed) {
      shouldQuit = true;
      aptSetChainloaderToSelf();
      break;
    }
    else if (res != SWKBDResult.homepressed && res != SWKBDResult.powerpressed) break; // An actual error happened

    shouldQuit = !aptMainLoop();
  } while (!shouldQuit);

  str = str[0..strlen(str.ptr)];
  pushBytes(arena, str.length, ArenaFlags.no_init);

  return str;
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
  ColorTheme.night   : "Night",
];

immutable ui.ColorTable[ColorTheme.max+1] COLOR_THEMES = [
  ColorTheme.neutral : [
    ui.Color.clear_color                      : C2D_Color32(0xEE, 0xEE, 0xEE, 0xFF),
    ui.Color.text                             : C2D_Color32(0x00, 0x00, 0x00, 0xFF),
    ui.Color.bg_bg                            : C2D_Color32(0xF5, 0xF5, 0xF5, 0xFF),
    ui.Color.bg_stripes_dark                  : C2D_Color32(0xD0, 0xD0, 0xD4, 0xFF),
    ui.Color.bg_stripes_light                 : C2D_Color32(0xBD, 0xBD, 0xC5, 0xFF),
    ui.Color.button_normal                    : C2D_Color32(0xFF, 0xFF, 0xFF, 0xFF),
    ui.Color.button_sel_indicator             : C2D_Color32(0x14, 0xB8, 0x24, 0xE0),
    ui.Color.button_bottom_top                : C2D_Color32(0xF3, 0xF4, 0xF6, 0xFF),
    ui.Color.button_bottom_bottom             : C2D_Color32(0xC4, 0xC5, 0xC8, 0xFF),
    ui.Color.button_bottom_base               : C2D_Color32(0xD8, 0xDB, 0xE1, 0xFF),

    // Dark bottom button
    //ui.Color.button_bottom_top                : C2D_Color32(0xB6, 0xB6, 0xBA, 0xFF),
    //ui.Color.button_bottom_bottom             : C2D_Color32(0x48, 0x48, 0x4C, 0xFF),
    //ui.Color.button_bottom_base               : C2D_Color32(0x66, 0x66, 0x6E, 0xFF),
    //ui.Color.button_bottom_text               : C2D_Color32(0xF2, 0xF2, 0xF7, 0xFF),
    //ui.Color.button_bottom_text_bevel         : C2D_Color32(0x11, 0x11, 0x11, 0xFF),

    ui.Color.button_bottom_line               : C2D_Color32(0x8B, 0x8B, 0x8C, 0xFF),
    ui.Color.button_bottom_pressed_top        : C2D_Color32(0x6E, 0x6E, 0x6A, 0xFF),
    ui.Color.button_bottom_pressed_bottom     : C2D_Color32(0xC0, 0xC0, 0xBC, 0xFF),
    ui.Color.button_bottom_pressed_base       : C2D_Color32(0xA5, 0xA5, 0x9E, 0xFF),
    ui.Color.button_bottom_pressed_line       : C2D_Color32(0x7B, 0x7B, 0x7B, 0xFF),
    ui.Color.button_bottom_text               : C2D_Color32(0x11, 0x11, 0x11, 0xFF),
    ui.Color.button_bottom_text_bevel         : C2D_Color32(0xFF, 0xFF, 0xFF, 0xFF),

    ui.Color.button_bottom_above_fade         : C2D_Color32(0xF2, 0xF2, 0xF7, 0x80),
    ui.Color.scroll_indicator                 : C2D_Color32(0x66, 0xAD, 0xC1, 0xFF),
    ui.Color.scroll_indicator_outline         : C2D_Color32(0xE1, 0xED, 0xF1, 0xFF),
    ui.Color.scroll_indicator_pushing         : C2D_Color32(0xDD, 0x80, 0x20, 0xFF),
    ui.Color.scroll_indicator_pushing_outline : C2D_Color32(0xE3, 0xAE, 0x78, 0xFF),
  ],
  ColorTheme.warm : [
    ui.Color.clear_color                      : C2D_Color32(0xE6, 0xDA, 0xB6, 0xFF),
    ui.Color.text                             : C2D_Color32(0x00, 0x00, 0x00, 0xFF),
    ui.Color.bg_bg                            : C2D_Color32(0xF5, 0xE9, 0xC4, 0xFF),
    ui.Color.bg_stripes_dark                  : C2D_Color32(0xD4, 0xC4, 0xAA, 0xFF),
    ui.Color.bg_stripes_light                 : C2D_Color32(0xBF, 0xB4, 0x99, 0xFF),
    ui.Color.button_normal                    : C2D_Color32(0xFB, 0xF6, 0xE2, 0xFF),
    ui.Color.button_sel_indicator             : C2D_Color32(0x87, 0xAB, 0x40, 0xFF),

    ui.Color.button_bottom_top                : C2D_Color32(0xF4, 0xED, 0xD7, 0xFF),
    ui.Color.button_bottom_bottom             : C2D_Color32(0xC7, 0xC0, 0xA9, 0xFF),
    ui.Color.button_bottom_base               : C2D_Color32(0xE4, 0xDA, 0xBD, 0xFF),
    ui.Color.button_bottom_line               : C2D_Color32(0x9E, 0x98, 0x86, 0xFF),
    ui.Color.button_bottom_pressed_top        : C2D_Color32(0x6E, 0x6C, 0x64, 0xFF),
    ui.Color.button_bottom_pressed_bottom     : C2D_Color32(0xBF, 0xBD, 0xB2, 0xFF),
    ui.Color.button_bottom_pressed_base       : C2D_Color32(0xA6, 0xA3, 0x97, 0xFF),
    ui.Color.button_bottom_pressed_line       : C2D_Color32(0x7A, 0x79, 0x74, 0xFF),
    ui.Color.button_bottom_text               : C2D_Color32(0x11, 0x11, 0x11, 0xFF),
    ui.Color.button_bottom_text_bevel         : C2D_Color32(0xFF, 0xFF, 0xFF, 0xFF),

    ui.Color.button_bottom_above_fade         : C2D_Color32(0xE9, 0xE2, 0xD2, 0x80),
    ui.Color.scroll_indicator                 : C2D_Color32(0xCA, 0xC1, 0x5F, 0xFF),
    ui.Color.scroll_indicator_outline         : C2D_Color32(0xF0, 0xF1, 0xE1, 0xFF),
    ui.Color.scroll_indicator_pushing         : C2D_Color32(0xDD, 0x9A, 0x20, 0xFF),
    ui.Color.scroll_indicator_pushing_outline : C2D_Color32(0xE3, 0xBD, 0x78, 0xFF),
  ],
  ColorTheme.night : [
    ui.Color.clear_color                      : C2D_Color32(0x27, 0x2A, 0x38, 0xFF),
    ui.Color.text                             : C2D_Color32(0xDD, 0xDD, 0xDD, 0xFF),
    ui.Color.bg_bg                            : C2D_Color32(0x2F, 0x32, 0x41, 0xFF),
    ui.Color.bg_stripes_dark                  : C2D_Color32(0x25, 0x26, 0x32, 0xFF),
    ui.Color.bg_stripes_light                 : C2D_Color32(0x3E, 0x41, 0x4F, 0xFF),
    ui.Color.button_normal                    : C2D_Color32(0x3D, 0x42, 0x52, 0xFF),
    ui.Color.button_sel_indicator             : C2D_Color32(0x14, 0xB8, 0x24, 0xE0),
    ui.Color.button_bottom_top                : C2D_Color32(0x4F, 0x52, 0x63, 0xFF),
    ui.Color.button_bottom_bottom             : C2D_Color32(0x40, 0x43, 0x4F, 0xFF),
    ui.Color.button_bottom_base               : C2D_Color32(0x4A, 0x4D, 0x5C, 0xFF),

    ui.Color.button_bottom_line               : C2D_Color32(0x42, 0x42, 0x46, 0xFF),
    ui.Color.button_bottom_pressed_top        : C2D_Color32(0x6E, 0x6E, 0x6A, 0xFF),
    ui.Color.button_bottom_pressed_bottom     : C2D_Color32(0xC0, 0xC0, 0xBC, 0xFF),
    ui.Color.button_bottom_pressed_base       : C2D_Color32(0xA5, 0xA5, 0x9E, 0xFF),
    ui.Color.button_bottom_pressed_line       : C2D_Color32(0x45, 0x45, 0x45, 0xFF),
    ui.Color.button_bottom_text               : C2D_Color32(0xF2, 0xF2, 0xF7, 0xFF),
    ui.Color.button_bottom_text_bevel         : C2D_Color32(0x11, 0x11, 0x11, 0xFF),

    ui.Color.button_bottom_above_fade         : C2D_Color32(0x26, 0x26, 0x35, 0x80),
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
enum BOTTOM_BUTTON_MARGIN   = 5.0f;