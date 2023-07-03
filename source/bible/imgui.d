module bible.imgui;

alias imgui = bible.imgui;

import bible.input, bible.util, bible.audio, bible.bible;

@nogc: nothrow:

void usage() {
  enum View {
    book,
    reading,
    options
  }

  enum CommandCode {
    switch_view,
    open_book,
  }

  static Input input;
  static View currentView = View.book;
  static Book currentBook;

  foreach (command; imgui.getCommands()) {
    final switch (cast(CommandCode) command.code) {
      case CommandCode.switch_view:
        currentView = cast(View) command.value;
        break;
      case CommandCode.open_book:
        currentView = View.reading;
        currentBook = cast(Book) command.value;
        //openBook();
        break;
    }
  }

  imgui.uiFrameStart();
  imgui.handleInput(&input);

  final switch (currentView) {
    case View.book:
      static int lastSelection = 0;
      static int selection     = 0;

      imgui.pushVerticalLayout();
      scope (exit) imgui.popParent();

      {
        auto layoutComm = imgui.pushSelectScrollLayout();
        scope (exit) imgui.popParent();

        foreach (i, book; BOOK_NAMES) {
          if (imgui.button("book").clicked) {
            imgui.sendCommand(CommandCode.open_book, i);
          }
        }
      }

      if (imgui.bottomButton("Options").clicked) {
        imgui.sendCommand(CommandCode.switch_view, View.options);
      }

      break;

    case View.reading:
      imgui.pushVerticalLayout();
      scope (exit) imgui.popParent();

      imgui.scrollableReadPane();
      if (imgui.bottomButton("Back").clicked) {
        imgui.sendCommand(CommandCode.switch_view, View.book);
      }

      break;

    case View.options:
      imgui.pushVerticalLayout();
      scope (exit) imgui.popParent();

      if (imgui.bottomButton("Back").clicked) {
        imgui.sendCommand(CommandCode.switch_view, View.book);
      }
      break;
  }

  imgui.uiFrameEnd();
}

enum UiFlags : uint {
  clickable           = 1 << 0,
  view_scroll         = 1 << 1,
  draw_text           = 1 << 2,
  select_children     = 1 << 3,
  selectable          = 1 << 4,
  horizontal_children = 1 << 5,
}

enum UiGraphic : ubyte {
  none,
  button,
  bottom_button,
  bible_text,
  scroll_indicator,
}

enum UiSizeKind : ubyte {
  none,
  pixels,
  text_content,
  percent_of_parent,
  children_sum,
}

struct UiSize {
  UiSizeKind kind;
  float value      = 0;
  float strictness = 0;
}

enum Axis2 : ubyte { x, y }

enum OneFrameEvent {
  not_triggered, triggered, already_processed,
}

struct UiBox {
  UiBox* first, last, next, prev, parent;
  int childId;

  string text;
  //LoadedPage* loadedPage;
  int hoveredChild, selectedChild;

  float scrollOffset   = 0, scrollOffsetLast  = 0;
  float scrollLimitTop = 0, scrollLimitBottom = 0;
  OneFrameEvent startedScrolling;  // @TODO: Remove these?
  OneFrameEvent scrollJustStopped;

  UiFlags flags;
  UiGraphic graphic;

  UiSize[Axis2.max+1] semanticSize;

  Vec2 computedRelPosition;
  Vec2 computedSize;
  Rectangle rect;

  float hotT = 0, activeT = 0;
}

struct UiComm {
  UiBox* box;
  Vec2 touchPos, dragDelta;
  bool clicked, pressed, held, released, dragging, hovering, selected;
  int hoveredChild, selectedChild;
  bool pushingAgainstScrollLimit;
}



UiComm button(string text) {
  UiBox* box = makeBox(UiFlags.clickable | UiFlags.draw_text, UiGraphic.button, text);

  box.semanticSize[] = [UiSize(UiSizeKind.text_content, 0, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;

  return commFromBox(box);
}

UiComm bottomButton(string text) {
  UiBox* box = makeBox(UiFlags.clickable | UiFlags.draw_text, UiGraphic.bottom_button, text);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;
  return commFromBox(box);
}

UiComm pushSelectScrollLayout() {
  UiBox* box = makeBox(UiFlags.select_children | UiFlags.view_scroll, UiGraphic.none, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  pushParent(box);
  return commFromBox(box);
}

void pushVerticalLayout() {
  UiBox* box = makeBox(cast(UiFlags) 0, UiGraphic.none, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  pushParent(box);
}

void scrollableReadPane() {
  UiBox* box = makeBox(UiFlags.view_scroll, UiGraphic.bible_text, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
}


struct UiCommand {
  uint code, value;
}

struct UiData {
  Input* input;

  UiBox[100] boxes;
  size_t boxIndex;
  UiBox* curBox;

  UiCommand[100] commands;
  size_t numCommands;

  UiBox* hot, active;
}

UiData gUiData;

UiBox* makeBox(UiFlags flags, UiGraphic graphic, string text) { with (gUiData) {
  UiBox* result = &boxes[boxIndex];
  boxIndex++;

  result.first = null;
  result.last  = null;
  result.next  = null;
  result.prev  = null;

  if (curBox) {
    if (curBox.first) {
      curBox.last.next = result;
      result.prev      = curBox.last;
      curBox.last      = result;
    }
    else {
      curBox.first = result;
      curBox.last  = result;
    }

    result.parent = curBox;
  }
  else {
    curBox = result;
  }

  result.flags   = flags;
  result.graphic = graphic;
  result.text    = text;

  return result;
}}

void pushParent(UiBox* box) { with (gUiData) {
  assert(box, "Parameter shouldn't be null");
  assert(box.parent == curBox || box == curBox, "Parameter should either be the current UI node or one of its children");
  curBox = box;
}}

void popParent() { with (gUiData) {
  assert(curBox, "Trying to pop to the current UI node's parent, but it's null!");
  curBox = curBox.parent;
}}

void uiFrameStart() { with (gUiData) {
  boxIndex = 0;
  curBox   = null;
}}

void handleInput(Input* newInput) { with (gUiData) {
  input = newInput;
}}

void uiFrameEnd() { with (gUiData) {

}}

UiComm commFromBox(UiBox* box) { with (gUiData) {
  UiComm result;

  if (box.flags & (UiFlags.clickable | UiFlags.view_scroll)) {
    if (input.down(Key.touch)) {
      if (insideOrOn(box.rect, Vec2(input.touchRaw.px, input.touchRaw.py))) {
        box.hotT    = 1;
        box.activeT = 1;
        result.held     = true;
        result.pressed  = true;
        result.hovering = true;
        active = box;

        if (box.parent && box.parent.flags & UiFlags.select_children) {
          box.parent.hoveredChild  = box.childId;
          box.parent.selectedChild = box.childId;
          result.selected = true;
        }
      }
    }
    else if (active == box && input.held(Key.touch)) {
      result.held = true;
      if (insideOrOn(box.rect, Vec2(input.touchRaw.px, input.touchRaw.py))) {
        result.hovering = true;
      }
      else {
        result.released = insideOrOn(box.rect, Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py));
      }
    }
    else if (active == box && input.prevHeld(Key.touch)) {
      if (insideOrOn(box.rect, Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py))) {
        active          = null;
        result.clicked  = true;
        result.released = true;
      }
    }
  }

  if ((box.flags & UiFlags.view_scroll) && result.held) {
    auto scrollDiff = updateScrollDiff(input);
    respondToScroll(box, &result, scrollDiff);
  }

  if ((box.flags & UiFlags.select_children) && box.first != null) {
    UiBox* selection = box.first;
    while (selection != null && selection.childId != box.hoveredChild) selection = selection.next;
    assert(selection != null, "The currently selected child doesn't exist exist anymore?");

    Key forwardKey  = (box.flags & UiFlags.horizontal_children) ? Key.right : Key.down;
    Key backwardKey = (box.flags & UiFlags.horizontal_children) ? Key.left  : Key.up;

    if (input.down(backwardKey)) {
      UiBox* runner = selection.prev;

      while (runner != null && !(runner.flags & UiFlags.selectable)) {
        runner = runner.prev;
      }

      if (runner != null) {
        selection = runner;
      }
    }
    else if (input.down(forwardKey)) {
      UiBox* runner = selection.next;

      while (runner != null && !(runner.flags & UiFlags.selectable)) {
        runner = runner.next;
      }

      if (runner != null) {
        selection = runner;
      }
    }

    box.hoveredChild = selection.childId;
    selection.hotT = 1;
    hot = selection; // @Note: There can only be one select_children box on screen, or else they conflict...
  }

  if ((box.flags & UiFlags.selectable) && hot == box) {
    if (input.down(Key.a)) {
      active = box;
      box.activeT = 1;
      result.clicked  = true;
      result.pressed  = true;
      result.held     = true;
      result.hovering = true;

      if (box.parent && box.parent.flags & UiFlags.select_children) {
        box.parent.hoveredChild  = box.childId;
        box.parent.selectedChild = box.childId;
        result.selected = true;
      }
    }
    else if (input.prevDown(Key.a)) {
      active = null;
      result.released = true;
    }
  }

  return result;
}}

void respondToScroll(UiBox* box, UiComm* result, Vec2 scrollDiff) { with (gUiData) { with (box) {
  enum SCROLL_TICK_DISTANCE = 60;

  scrollOffsetLast = scrollOffset;

  if (input.scrollMethodCur == ScrollMethod.touch) {
    if (!input.down(Key.touch)) {
      scrollOffset += scrollDiff.y;
    }
  }
  else {
    scrollOffset += scrollDiff.y;
  }

  if (scrollOffset < scrollLimitTop) {
    scrollOffset = scrollLimitTop;
    input.scrollVel = 0;
  }
  else if (scrollOffset > scrollLimitBottom) {
    scrollOffset = scrollLimitBottom;
    input.scrollVel = 0;
  }


  ////
  // handle scrolling events
  ////

  if (scrollOffset == scrollLimitTop || scrollOffset == scrollLimitBottom) {
    if ( scrollJustStopped == OneFrameEvent.not_triggered &&
         scrollOffset != scrollOffsetLast )
    {
      scrollJustStopped = OneFrameEvent.triggered;
    }

    if ( input.scrollMethodCur != ScrollMethod.none &&
         input.scrollMethodCur != ScrollMethod.custom )
    {
      result.pushingAgainstScrollLimit = true;
    }
  }
  else {
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
    audioPlaySound(SoundEffect.scroll_tick, 0.1);
    startedScrolling = OneFrameEvent.already_processed;
  }

  if (floor(scrollOffset/SCROLL_TICK_DISTANCE) != floor(scrollOffsetLast/SCROLL_TICK_DISTANCE)) {
    audioPlaySound(SoundEffect.scroll_tick, 0.05);
  }

  if (scrollJustStopped == OneFrameEvent.triggered) {
    audioPlaySound(SoundEffect.scroll_stop, 0.1);
    scrollJustStopped = OneFrameEvent.already_processed;
  }
}}}

UiCommand[] getCommands() { with (gUiData) {
  return commands[0..numCommands];
}}

void sendCommand(uint code, uint value) { with (gUiData) {
  assert(numCommands < commands.length, "Too many UI commands in one frame!");
  commands[numCommands] = UiCommand(code, value);
  numCommands++;
}}

void render() {

}