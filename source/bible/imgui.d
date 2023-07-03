module bible.imgui;

alias imgui = bible.imgui;

import bible.input, bible.util, bible.audio, bible.bible;

@nogc: nothrow:

// @TODO: Replace this with hashing system
enum UiId : ushort {
  book_main_layout,
  book_scroll_layout,
  book_scroll_indicator,
  book_options_btn,
  book_bible_btn_first,
  book_bible_btn_last = book_bible_btn_first + BOOK_NAMES.length - 1,
  reading_main_layout,
  reading_scroll_read_view,
  reading_scroll_indicator,
  reading_back_btn,
  options_main_layout,
  options_back_btn,
}

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

      imgui.pushVerticalLayout(UiId.book_main_layout);
      scope (exit) imgui.popParent();

      {
        auto layoutComm = imgui.pushSelectScrollLayout(UiId.book_scroll_layout);
        scope (exit) imgui.popParent();

        foreach (i, book; BOOK_NAMES) {
          if (imgui.button(cast(UiId) (UiId.book_bible_btn_first + i), "book").clicked) {
            imgui.sendCommand(CommandCode.open_book, i);
          }
        }
      }

      if (imgui.bottomButton(UiId.book_options_btn, "Options").clicked) {
        imgui.sendCommand(CommandCode.switch_view, View.options);
      }

      break;

    case View.reading:
      imgui.pushVerticalLayout(UiId.reading_main_layout);
      scope (exit) imgui.popParent();

      imgui.scrollableReadPane(UiId.book_scroll_layout);
      if (imgui.bottomButton(UiId.reading_back_btn, "Back").clicked) {
        imgui.sendCommand(CommandCode.switch_view, View.book);
      }

      break;

    case View.options:
      imgui.pushVerticalLayout(UiId.options_main_layout);
      scope (exit) imgui.popParent();

      if (imgui.bottomButton(UiId.options_back_btn, "Back").clicked) {
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
  UiId id;
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

  uint lastFrameTouchedIndex;

  float hotT = 0, activeT = 0;
}

struct UiComm {
  UiBox* box;
  Vec2 touchPos, dragDelta;
  bool clicked, pressed, held, released, dragging, hovering, selected;
  int hoveredChild, selectedChild;
  bool pushingAgainstScrollLimit;
}



UiComm button(UiId id, string text) {
  UiBox* box = makeBox(id, UiFlags.clickable | UiFlags.draw_text, UiGraphic.button, text);

  box.semanticSize[] = [UiSize(UiSizeKind.text_content, 0, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;

  return commFromBox(box);
}

UiComm bottomButton(UiId id, string text) {
  UiBox* box = makeBox(id, UiFlags.clickable | UiFlags.draw_text, UiGraphic.bottom_button, text);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;
  return commFromBox(box);
}

UiComm pushSelectScrollLayout(UiId id) {
  UiBox* box = makeBox(id, UiFlags.select_children | UiFlags.view_scroll, UiGraphic.none, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  pushParent(box);
  return commFromBox(box);
}

void pushVerticalLayout(UiId id) {
  UiBox* box = makeBox(id, cast(UiFlags) 0, UiGraphic.none, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  pushParent(box);
}

void scrollableReadPane(UiId id) {
  UiBox* box = makeBox(id, UiFlags.view_scroll, UiGraphic.bible_text, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
}


struct UiCommand {
  uint code, value;
}

struct UiData {
  Input* input;

  UiBox[100] boxes;
  UiBox* root, curBox;
  uint frameIndex;

  UiCommand[100] commands;
  size_t numCommands;

  UiBox* hot, active;
}

UiData gUiData;

UiBox* makeBox(UiId id, UiFlags flags, UiGraphic graphic, string text) { with (gUiData) {
  UiBox* result = &boxes[id];
  if (frameIndex != result.lastFrameTouchedIndex) {
    *result = UiBox.init;
  }
  result.lastFrameTouchedIndex = frameIndex;

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
    assert(!root, "Somehow, a second root is trying to be added to the UI tree. Don't do that!");
    root   = result;
    curBox = result;
  }

  result.id      = id;
  result.childId = result.prev == null ? 0 : result.prev.childId + 1;
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
  curBox   = null;
}}

void handleInput(Input* newInput) { with (gUiData) {
  input = newInput;
}}

void uiFrameEnd() { with (gUiData) {
  // Ryan Fleury's offline layout algorithm (from https://www.rfleury.com/p/ui-part-2-build-it-every-frame-immediate):
  //
  // 1. (Any order) Calculate “standalone” sizes. These are sizes that do not depend on other widgets and can be
  //    calculated purely with the information that comes from the single widget that is having its size calculated.
  // 2. (Pre-order) Calculate “upwards-dependent” sizes. These are sizes that strictly depend on an ancestor’s size,
  //    other than ancestors that have “downwards-dependent” sizes on the given axis.
  // 3. (Post-order) Calculate “2downwards-dependent” sizes. These are sizes that depend on sizes of descendants.
  // 4. (Pre-order) Solve violations. For each level in the hierarchy, this will verify that the children do not extend
  //    past the boundaries of a given parent (unless explicitly allowed to do so; for example, in the case of a parent
  //    that is scrollable on the given axis), to the best of the algorithm’s ability. If there is a violation, it will
  //    take a proportion of each child widget’s size (on the given axis) proportional to both the size of the
  //    violation, and (1-strictness), where strictness is that specified in the semantic size on the child widget for
  //    the given axis.
  // 5. (Pre-order) Finally, given the calculated sizes of each widget, compute the relative positions of each widget
  //    (by laying out on an axis which can be specified on any parent node). This stage can also compute the final
  //    screen-coordinates rectangle.

  // Step 1 (standalone sizes)
  preOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      final switch (box.semanticSize[axis].kind) {
        case UiSizeKind.none:
          box.computedSize[axis] = 0;
          break;
        case UiSizeKind.pixels:
          box.computedSize[axis] = box.semanticSize[axis].value;
          break;
        case UiSizeKind.text_content:
          if (axis == Axis2.x) {
            box.computedSize[axis] = box.text.length * 10; // @TODO
          }
          else {
            box.computedSize[axis] = 10; // @TODO
          }
          break;
        case UiSizeKind.percent_of_parent:
        case UiSizeKind.children_sum:
          break;
      }
    }
  });

  // Step 2 (upwards-dependent sizes)
  preOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      final switch (box.semanticSize[axis].kind) {
        case UiSizeKind.percent_of_parent:
          float parentSize;
          if (box.parent) {
            parentSize = box.parent.computedSize[axis];
          }
          else {
            parentSize = axis == Axis2.x ? SCREEN_BOTTOM_WIDTH : SCREEN_HEIGHT; // @TODO
          }

          box.computedSize[axis] = parentSize * box.semanticSize[axis].value;
          break;

        case UiSizeKind.none:
        case UiSizeKind.pixels:
        case UiSizeKind.text_content:
        case UiSizeKind.children_sum:
          break;
      }
    }
  });


  // Step 3 (downwards-dependent sizes)
  postOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      final switch (box.semanticSize[axis].kind) {
        case UiSizeKind.children_sum:
          float sum = 0;

          foreach (child; eachChild(box)) {
            sum += child.computedSize[axis];
          }

          box.computedSize[axis] = sum;
          break;

        case UiSizeKind.none:
        case UiSizeKind.pixels:
        case UiSizeKind.text_content:
        case UiSizeKind.percent_of_parent:
          break;
      }
    }
  });

  // Step 4 (solve violations)
  preOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      if (axis == Axis2.y && (box.flags & UiFlags.view_scroll)) continue;  // Assume there really are no violations if you can scroll

      float sum = 0;
      foreach (child; eachChild(box)) {
        sum += child.computedSize[axis];
      }

      float difference = sum - box.computedSize[axis];
      if (difference > 0) {
        foreach (child; eachChild(box)) {
          float partToRemove        = difference * (1-child.strictness);
          child.computedSize[axis] -= partToRemove;
          difference               -= partToRemove;
        }
      }
    }
  });

  // Step 5 (compute positions)
  preOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      box.computedRelPosition[axis] = 0;

      if (box.parent) {
        if (!!(box.parent.flags & UiFlags.horizontal_children) == (axis == Axis2.x)) {
          if (box.prev) {
            // @TODO: Padding
            box.computedRelPosition[axis] += box.prev.computedRelPosition[axis] + box.prev.computedSize[axis];
          }
        }
      }
    }

    box.rect = Rectangle(box.computedRelPosition[Axis2.x], box.computedRelPosition[Axis2.y],
                         box.computedSize[Axis2.x],        box.computedSize[Axis2.y]);

    if (box.parent) {
      box.rect.left   += box.parent.rect.left;
      box.rect.top    += box.parent.rect.top;
      box.rect.right  += box.rect.left;
      box.rect.bottom += box.rect.bottom;

      if (box.parent.flags & UiFlags.view_scroll) {
        box.computedRelPosition[Axis2.y] -= box.scrollOffset;
      }
    }
  });

  frameIndex++;
}}

void preOrderApply(UiBox* box, scope void delegate(UiBox* box) @nogc nothrow func) {
  auto runner = box;
  while (runner != null) {
    func(runner);
    if (runner.first) {
      runner = runner.first;
    }
    else if (runner.next) {
      runner = runner.next;
    }
    else {
      while (true) {
        runner = runner.parent;
        if (!runner) return;
        if (runner.next) {
          runner = runner.next;
          break;
        }
      }
    }
  }
}

void postOrderApply(UiBox* box, scope void delegate(UiBox* box) @nogc nothrow func) {
  auto runner = box;
  while (runner != null) {
    if (runner.first) {
      runner = runner.first;
    }
    else if (runner.next) {
      func(runner);
      runner = runner.next;
    }
    else {
      func(runner);
      while (true) {
        runner = runner.parent;
        if (!runner) return;
        func(runner);
        if (runner.next) {
          runner = runner.next;
          break;
        }
      }
    }
  }
}

auto eachChild(UiBox* box) {
  static struct Range {
    @nogc: nothrow:

    UiBox* runner;

    UiBox* front()    { return runner; }
    bool   empty()    { return runner == null; }
    void   popFront() { runner = runner.next; }
  }

  return Range(box.first);
}

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

void render() { with (gUiData) {

}}