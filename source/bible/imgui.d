module bible.imgui;

alias imgui = bible.imgui;

import bible.input, bible.util, bible.audio, bible.bible;
import std.math;

@nogc: nothrow:

enum float ANIM_T_RATE          = 0.1;
enum       TOUCH_DRAG_THRESHOLD = 8;

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

void usage(Input* input) {
  enum View {
    book,
    reading,
    options
  }

  enum CommandCode {
    switch_view,
    open_book,
  }

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
  imgui.handleInput(input);

  final switch (currentView) {
    case View.book:
      imgui.pushVerticalLayout(UiId.book_main_layout);
      scope (exit) imgui.popParent();

      {
        auto layoutComm = imgui.pushSelectScrollLayout(UiId.book_scroll_layout);
        scope (exit) imgui.popParentAndComm();

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
      if (imgui.bottomButton(UiId.reading_back_btn, "Back").clicked || input.down(Key.b)) {
        imgui.sendCommand(CommandCode.switch_view, View.book);
      }

      break;

    case View.options:
      imgui.pushVerticalLayout(UiId.options_main_layout);
      scope (exit) imgui.popParent();

      if (imgui.bottomButton(UiId.options_back_btn, "Back").clicked || input.down(Key.b)) {
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

enum Justification : ubyte { min, center, max }

enum OneFrameEvent {
  not_triggered, triggered, already_processed,
}

alias RenderCallback = void function(UiBox*) @nogc nothrow;

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
  Justification justification;
  RenderCallback render;

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
  UiBox* box = makeBox(id, UiFlags.clickable | UiFlags.draw_text | UiFlags.selectable, text);

  box.semanticSize[] = [UiSize(UiSizeKind.text_content, 0, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;

  return commFromBox(box);
}

UiComm bottomButton(UiId id, string text) {
  UiBox* box = makeBox(id, UiFlags.clickable | UiFlags.draw_text, text);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;
  return commFromBox(box);
}

UiBox* pushSelectScrollLayout(UiId id) {
  UiBox* box = makeBox(id, UiFlags.select_children | UiFlags.view_scroll, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  box.justification  = Justification.center;
  pushParent(box);
  return box;
}

void pushVerticalLayout(UiId id) {
  UiBox* box = makeBox(id, cast(UiFlags) 0, null);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  box.justification  = Justification.center;
  pushParent(box);
}

void scrollableReadPane(UiId id) {
  UiBox* box = makeBox(id, UiFlags.view_scroll, null);
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

  UiBox* hot, active, focused;
}

UiData gUiData;

UiBox* makeBox(UiId id, UiFlags flags, string text) { with (gUiData) {
  UiBox* result = &boxes[id];
  if (frameIndex-1 != result.lastFrameTouchedIndex) {
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
  result.text    = text;

  return result;
}}

void pushParent(UiBox* box) { with (gUiData) {
  assert(box, "Parameter shouldn't be null");
  assert(box.parent == curBox || box == curBox, "Parameter should either be the current UI node or one of its children");
  curBox = box;
}}

UiBox* popParent() { with (gUiData) {
  assert(curBox, "Trying to pop to the current UI node's parent, but it's null!");
  auto result = curBox;
  curBox = curBox.parent;
  return result;
}}

UiComm popParentAndComm() {
  return commFromBox(popParent());
}

void uiFrameStart() { with (gUiData) {
  curBox = null;
  root   = null;
}}

void handleInput(Input* newInput) { with (gUiData) {
  input = newInput;
}}

void uiFrameEnd() { with (gUiData) {
  if (hot     && hot.lastFrameTouchedIndex      != frameIndex) hot     = null;
  if (active  && active.lastFrameTouchedIndex   != frameIndex) active  = null;
  if (focused && focused .lastFrameTouchedIndex != frameIndex) focused = null;

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
            box.computedSize[axis] = box.text.length * 15; // @TODO
          }
          else {
            box.computedSize[axis] = 15; // @TODO
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
    Axis2 axis = (box.flags & UiFlags.horizontal_children) ? Axis2.x : Axis2.y;
    if (box.flags & UiFlags.view_scroll) return;  // Assume there really are no violations if you can scroll

    float sum = 0;
    foreach (child; eachChild(box)) {
      sum += child.computedSize[axis];
    }

    float difference = sum - box.computedSize[axis];
    if (difference > 0) {
      foreach (child; eachChild(box)) {
        float partToRemove        = difference * (1-child.semanticSize[axis].strictness);
        child.computedSize[axis] -= partToRemove;
        difference               -= partToRemove;
      }
    }
  });

  // Step 5 (compute positions)
  preOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      box.computedRelPosition[axis] = 0;

      if (box.parent) {
        if (!!(box.parent.flags & UiFlags.horizontal_children) == (axis == Axis2.x)) {
          // Order children one after the other in the axis towards the flow of child nodes
          if (box.prev) {
            // @TODO: Padding
            box.computedRelPosition[axis] += box.prev.computedRelPosition[axis] + box.prev.computedSize[axis];
          }
        }
        else {
          // Justify within the parent in the axis against flow of child nodes
          float factor;
          final switch (box.parent.justification) {
            case Justification.min:
              factor = 0;
              break;
            case Justification.center:
              factor = 0.5;
              break;
            case Justification.max:
              factor = 1;
              break;
          }
          box.computedRelPosition[axis] = factor * (box.parent.computedSize[axis] - box.computedSize[axis]);
        }
      }
    }

    box.rect = Rectangle(box.computedRelPosition[Axis2.x], box.computedRelPosition[Axis2.x],
                         box.computedRelPosition[Axis2.y], box.computedRelPosition[Axis2.y]);

    box.rect.right  += box.computedSize[Axis2.x];
    box.rect.bottom += box.computedSize[Axis2.y];

    if (box.parent) {
      if (box.parent.flags & UiFlags.view_scroll) {
        box.rect.top    -= box.parent.scrollOffset;
        box.rect.bottom -= box.parent.scrollOffset;
      }

      box.rect.left   += box.parent.rect.left;
      box.rect.top    += box.parent.rect.top;
      box.rect.right  += box.parent.rect.left;
      box.rect.bottom += box.parent.rect.top;
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

  //UiBox* active = active;

  if (box.flags & (UiFlags.clickable | UiFlags.view_scroll)) {
    if (active == null && input.down(Key.touch)) {
      if (insideOrOn(box.rect, Vec2(input.touchRaw.px, input.touchRaw.py))) {
        box.hotT        = 1;
        box.activeT     = 1;
        result.held     = true;
        result.pressed  = true;
        result.hovering = true;
        hot             = box;
        active          = box;
        focused         = box;

        if (box.parent && box.parent.flags & UiFlags.select_children) {
          box.parent.hoveredChild  = box.childId;
          box.parent.selectedChild = box.childId;
          result.selected          = true;
        }
      }
    }
    else if (active == box && input.held(Key.touch)) {
      box.hotT    = 1;
      box.activeT = 1;
      hot         = box;
      active      = box;
      focused     = box;
      result.held = true;

      // Allow scrolling the parent to kick in if we drag too far away
      if (box.parent && (box.parent.flags & UiFlags.view_scroll) && abs(input.touchDiff().y) >= TOUCH_DRAG_THRESHOLD) {
        result.held        = false;
        result.released    = true;
        box.parent.hotT    = 1;
        box.parent.activeT = 1;
        active             = box.parent;
        hot                = box.parent;
        focused            = box.parent;
      }
      else if (insideOrOn(box.rect, Vec2(input.touchRaw.px, input.touchRaw.py))) {
        result.hovering = true;
      }
      else {
        result.released = insideOrOn(box.rect, Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py));
      }
    }
    else if (active == box && input.prevHeld(Key.touch)) {
      active          = null;
      result.released = true;
      if (insideOrOn(box.rect, Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py))) {
        result.clicked  = true;
      }
    }
  }

  bool needToScrollTowardsChild = false;
  UiBox* cursored = null;
  if ((box.flags & UiFlags.select_children) && box.first != null) {
    cursored = box.first;

    // @TODO: Better figure out how to handle widgets going away
    while (cursored != null && cursored.childId != box.hoveredChild) cursored = cursored.next;
    assert(cursored != null, "The currently selected child doesn't exist exist anymore?");

    Key forwardKey  = (box.flags & UiFlags.horizontal_children) ? Key.right : Key.down;
    Key backwardKey = (box.flags & UiFlags.horizontal_children) ? Key.left  : Key.up;

    UiBox* moveToSelectable(UiBox* box, int dir, scope bool delegate(UiBox*) @nogc nothrow check) {
      auto runner = box;

      if (dir == 1) {
        do {
          runner = runner.next;
        } while (runner != null && !(runner.flags & UiFlags.selectable) && !check(runner));
      }
      else {
        do {
          runner = runner.prev;
        } while (runner != null && !(runner.flags & UiFlags.selectable) && !check(runner));
      }

      return runner == null ? box : runner;
    }

    bool scrollOccurring = (box.flags & UiFlags.view_scroll) &&
                           ( input.scrollMethodCur == ScrollMethod.touch ||
                             ( input.scrollMethodCur == ScrollMethod.none &&
                               input.scrollVel != 0 ) );

    if (scrollOccurring)
    {
      // Mimicking how the 3DS UI works, select nearest on-screen child while scrolling
      if (cursored.rect.bottom > box.rect.bottom) {
        cursored = moveToSelectable(cursored, -1, a => a.rect.bottom <= box.rect.bottom);
      }
      else if (cursored.rect.top < box.rect.top) {
        cursored = moveToSelectable(cursored, 1, a => a.rect.top >= box.rect.top);
      }
    }
    else if (input.down(backwardKey)) {
      cursored = moveToSelectable(cursored, -1, a => true);
      focused = box;  // @TODO: Is this a good way to solve scrolling to off-screen children?
      needToScrollTowardsChild = (box.flags & UiFlags.view_scroll) &&
                                 ( cursored.rect.top    < box.rect.top ||
                                   cursored.rect.bottom > box.rect.bottom );
    }
    else if (input.down(forwardKey)) {
      cursored = moveToSelectable(cursored, 1, a => true);
      focused = box;  // @TODO: Is this a good way to solve scrolling to off-screen children?
      needToScrollTowardsChild = (box.flags & UiFlags.view_scroll) &&
                                 ( cursored.rect.top    < box.rect.top ||
                                   cursored.rect.bottom > box.rect.bottom );
    }

    box.hoveredChild = cursored.childId;
    if (!scrollOccurring) cursored.hotT = 1;
    hot = cursored; // @Note: There can only be one select_children box on screen, or else they conflict...
  }

  if ((box.flags & UiFlags.view_scroll) && focused == box) {
    uint allowedMethods = 1 << ScrollMethod.touch;

    // Don't allow scrolling with D-pad/circle-pad if we can select children with either of those
    // @TODO allow holding direction for some time to override this
    if (!(box.flags & UiFlags.select_children)) {
      allowedMethods = allowedMethods | (1 << ScrollMethod.dpad) | (1 << ScrollMethod.circle);
    }

    // Scrolling towards off-screen children will occur if triggered by keying over to it until our target is on screen.
    if (input.scrollMethodCur == ScrollMethod.none && needToScrollTowardsChild) {
      input.scrollMethodCur = ScrollMethod.custom;
      input.scrollVel = 0;
    }
    else if ( input.scrollMethodCur == ScrollMethod.custom &&
              ( !cursored ||
                ( cursored.rect.top    >= box.rect.top &&      // @Bug: Child that's bigger than parent will scroll forever!
                  cursored.rect.bottom <= box.rect.bottom ) ) )
    {
      input.scrollMethodCur = ScrollMethod.none;
    }

    Vec2 scrollDiff;
    if (input.scrollMethodCur == ScrollMethod.custom) {
      scrollDiff.y = cursored.rect.top < box.rect.top ? -5 : 5;
    }
    else {
      scrollDiff = updateScrollDiff(input, allowedMethods);
    }

    box.scrollLimitTop    = 0;
    box.scrollLimitBottom = box.last ? box.last.computedRelPosition[Axis2.y] + box.last.computedSize[Axis2.y] : 0;
    respondToScroll(box, &result, scrollDiff);
  }

  if ((box.flags & UiFlags.selectable) && hot == box) {
    if (input.down(Key.a)) {
      active   = box;
      focused  = box;
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
  import ctru, citro3d, citro2d;

  static immutable uint[] COLORS = [
    C2D_Color32(0xFF, 0x00, 0x00, 0xFF),
    C2D_Color32(0x00, 0xFF, 0x00, 0xFF),
    C2D_Color32(0x00, 0x00, 0xFF, 0xFF),
    C2D_Color32(0x88, 0x00, 0xAA, 0xFF),
  ];

  preOrderApply(root, (box) {
    if (box.parent && !intersects(box.rect, box.parent.rect)) {
      return;
    }

    auto color = COLORS[box.id % COLORS.length];

    if (box.render) {
      box.render(box);
    }

    if (box.flags & UiFlags.clickable) {
      C2D_DrawRectSolid(box.rect.left, box.rect.top, 0, box.rect.right - box.rect.left, box.rect.bottom - box.rect.top, color);
    }
    else {
      C2D_DrawRectSolid(box.rect.left,  box.rect.top,    0, box.rect.right - box.rect.left, 1, color);
      C2D_DrawRectSolid(box.rect.left,  box.rect.bottom, 0, box.rect.right - box.rect.left, 1, color);
      C2D_DrawRectSolid(box.rect.left,  box.rect.top,    0, 1, box.rect.bottom - box.rect.top, color);
      C2D_DrawRectSolid(box.rect.right, box.rect.top,    0, 1, box.rect.bottom - box.rect.top, color);
    }

    if (box.parent && (box.parent.flags & UiFlags.select_children) && (box.flags & UiFlags.selectable) && box.hotT > 0) {
      auto indicColor = C2D_Color32f(0x00, 0xAA/255.0, 0x11/255.0, box.hotT);
      C2D_DrawRectSolid(box.rect.left-2,  box.rect.top-2,    0, box.rect.right - box.rect.left + 2*2, 2, indicColor);
      C2D_DrawRectSolid(box.rect.left-2,  box.rect.bottom,   0, box.rect.right - box.rect.left + 2*2, 2, indicColor);
      C2D_DrawRectSolid(box.rect.left-2,  box.rect.top-2,    0, 2, box.rect.bottom - box.rect.top + 2*2, indicColor);
      C2D_DrawRectSolid(box.rect.right,   box.rect.top-2,    0, 2, box.rect.bottom - box.rect.top + 2*2, indicColor);
    }

    box.hotT    = approach(box.hotT,    0, ANIM_T_RATE);
    box.activeT = approach(box.activeT, 0, ANIM_T_RATE);
  });
}}