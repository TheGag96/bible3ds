module bible.imgui;

alias imgui = bible.imgui;

import bible.input, bible.util, bible.audio, bible.bible;
import ctru, citro2d, citro3d;
import std.math;
import bible.imgui_render;
import bible.profiling;

@nogc: nothrow:

enum float ANIM_T_RATE          = 0.1;
enum       TOUCH_DRAG_THRESHOLD = 8;

enum RENDER_DEBUG_BOXES = false;

static immutable Vec2[GFXScreen.max+1] SCREEN_POS = [
  GFXScreen.top    : Vec2(0, 0),
  GFXScreen.bottom : Vec2((SCREEN_TOP_WIDTH-SCREEN_BOTTOM_WIDTH)/2, SCREEN_HEIGHT),
];

static immutable Rectangle[GFXScreen.max+1] SCREEN_RECT = [
  GFXScreen.top    : Rectangle(
    0, 0,
    SCREEN_TOP_WIDTH, SCREEN_HEIGHT
  ),
  GFXScreen.bottom : Rectangle(
    (SCREEN_TOP_WIDTH-SCREEN_BOTTOM_WIDTH)/2, SCREEN_HEIGHT,
    (SCREEN_TOP_WIDTH-SCREEN_BOTTOM_WIDTH)/2 + SCREEN_BOTTOM_WIDTH, SCREEN_HEIGHT * 2
  ),
];

enum MARGIN = 8.0f;
enum BOOK_BUTTON_WIDTH      = 200.0f;
enum BOOK_BUTTON_MARGIN     = 8.0f;
enum BOOK_BUTTON_COLOR      = C2D_Color32(0x00, 0x00, 0xFF, 0xFF);
enum BOOK_BUTTON_DOWN_COLOR = C2D_Color32(0x55, 0x55, 0xFF, 0xFF);
static immutable BoxStyle BOOK_BUTTON_STYLE = {
  colorText     : C2D_Color32(0, 0, 0, 255),
  colorBg       : BOOK_BUTTON_COLOR,
  colorBgHeld   : BOOK_BUTTON_DOWN_COLOR,
  margin        : BOOK_BUTTON_MARGIN,
  textSize      : 0.5f,
};

enum UiFlags : uint {
  clickable            = 1 << 0,
  view_scroll          = 1 << 1,
  manual_scroll_limits = 1 << 2,
  draw_text            = 1 << 3,
  select_children      = 1 << 4,
  selectable           = 1 << 5,
  horizontal_children  = 1 << 6,
  demand_focus         = 1 << 7,
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

enum Justification : ubyte { min, center, max }

enum OneFrameEvent {
  not_triggered, triggered, already_processed,
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

  int linesInPage;

  float textSize = 0, pageMargin = 0;
  float glyphWidth = 0, glyphHeight = 0;
}

struct ScrollInfo {
  float offset = 0, offsetLast = 0;
  float limitMin = 0, limitMax = 0;
  OneFrameEvent startedScrolling;  // @TODO: Remove these?
  OneFrameEvent scrollJustStopped;
}

struct BoxStyle {
  uint colorText, colorBg, colorBgHeld;
  float margin;
  float textSize = 0;
  SoundEffect pressedSound = SoundEffect.button_confirm;
  float pressedSoundVol = 0.5;
}
immutable DEFAULT_STYLE = BoxStyle.init;

struct UiBox {
  UiBox* first, last, next, prev, parent;
  UiBox* hashNext, hashPrev;
  UiBox* freeListNext;

  ulong hashKey;

  int childId;

  C2D_Text text;
  float textHeight = 0;
  int hoveredChild, selectedChild;

  ScrollInfo scrollInfo;
  ScrollCache* scrollCache;

  UiFlags flags;
  Justification justification;
  RenderCallback render;
  const(BoxStyle)* style;

  UiSize[Axis2.max+1] semanticSize;

  Vec2 computedRelPosition;
  Vec2 computedSize;
  Rectangle rect;

  uint lastFrameTouchedIndex;

  float hotT = 0, activeT = 0;

  UiBox* related;  // General-purpose field to relate boxes to other boxes.
}

// @Note: Render scroll caches forced me to make the UiBox* parameter non-const. Can/should this be changed?
alias RenderCallback = void function(UiBox*, GFXScreen, GFX3DSide, bool, float, Vec2) @nogc nothrow;

struct UiSignal {
  UiBox* box;
  Vec2 touchPos, dragDelta;
  bool clicked, pressed, held, released, dragging, hovering, selected;
  int hoveredChild, selectedChild;
  bool pushingAgainstScrollLimit;
}

struct UiBoxAndSignal {
  UiBox* box;
  UiSignal signal;
}


void label(const(char)[] text, Justification justification = Justification.min) {
  UiBox* box = makeBox(UiFlags.draw_text, text);

  box.semanticSize[] = [UiSize(UiSizeKind.text_content, 0, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;
  box.justification  = justification;
  box.render         = &renderLabel;
}

enum BOTTOM_BUTTON_MARGIN     = 6.0f;
enum BOTTOM_BUTTON_COLOR      = C2D_Color32(0xCC, 0xCC, 0xCC, 0xFF);
enum BOTTOM_BUTTON_DOWN_COLOR = C2D_Color32(0x8C, 0x8C, 0x8C, 0xFF);

static immutable BoxStyle BOTTOM_BUTTON_STYLE = {
  colorText     : C2D_Color32(0x11, 0x11, 0x11, 255),
  colorBg       : BOTTOM_BUTTON_COLOR,
  colorBgHeld   : BOTTOM_BUTTON_DOWN_COLOR,
  margin        : BOTTOM_BUTTON_MARGIN,
  textSize      : 0.6f,
};

static immutable BoxStyle BACK_BUTTON_STYLE = () {
  BoxStyle result = BOTTOM_BUTTON_STYLE;
  // @Hack: Gets played manually by builder code so that it plays on pressing B. Consider revising...
  result.pressedSound    = SoundEffect.none;
  result.pressedSoundVol = 0.0;
  return result;
}();

UiSignal button(const(char)[] text, int size = 0) {
  UiBox* box = makeBox(UiFlags.clickable | UiFlags.draw_text | UiFlags.selectable, text);

  if (size == 0) {
    box.semanticSize[Axis2.x] = UiSize(UiSizeKind.text_content, 0, 1);
  }
  else {
    box.semanticSize[Axis2.x] = UiSize(UiSizeKind.pixels, size, 1);
  }

  box.semanticSize[Axis2.y] = UiSize(UiSizeKind.text_content, 0, 1);

  box.render = &renderNormalButton;

  return signalFromBox(box);
}

UiSignal bottomButton(const(char)[] text) {
  UiBox* box = makeBox(UiFlags.clickable | UiFlags.draw_text, text);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 1), UiSize(UiSizeKind.text_content, 0, 1)].s;
  box.render = &renderBottomButton;
  return signalFromBox(box);
}

void spacer(const(char)[] id, float size) {
  UiBox* box = makeBox(cast(UiFlags) 0, id);

  if (box.parent && (box.parent.flags & UiFlags.horizontal_children)) {
    box.semanticSize[Axis2.x] = UiSize(UiSizeKind.pixels, size);
    box.semanticSize[Axis2.y] = UiSize(UiSizeKind.percent_of_parent, 1, 1);
  }
  else {
    box.semanticSize[Axis2.x] = UiSize(UiSizeKind.percent_of_parent, 1, 1);
    box.semanticSize[Axis2.y] = UiSize(UiSizeKind.pixels, size);
  }
}

void scrollIndicator(const(char)[] id, UiBox* source, Justification justification, bool limitHit) {
  UiBox* box = makeBox(cast(UiFlags) 0, id);
  box.render = &renderScrollIndicator;

  // @TODO: Only vertical scroll indicators are supported at the moment.
  // @Note: The widget will fill the parent but will only draw as wide as the indicator texture.
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;

  box.justification = justification;
  box.related       = source;

  box.hotT = approach(box.hotT, 1.0f*limitHit, 2*ANIM_T_RATE);
}

struct ScopedSelectScrollLayout {
  @nogc: nothrow:

  UiBox* box;
  UiSignal* signalToWrite;

  @disable this();

  this(const(char)[] id, UiSignal* signalToWrite) {
    box = pushSelectScrollLayout(id);
    this.signalToWrite = signalToWrite;
  }

  ~this() {
    *signalToWrite = popParentAndSignal();
  }
}

UiBox* pushSelectScrollLayout(const(char)[] id) {
  UiBox* box = makeBox(UiFlags.select_children | UiFlags.view_scroll | UiFlags.demand_focus, id);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  box.justification  = Justification.center;
  pushParent(box);
  return box;
}

UiBox* makeLayout(const(char)[] id, Axis2 flowDirection) {
  UiBox* box = makeBox(cast(UiFlags) ((flowDirection == Axis2.x) * UiFlags.horizontal_children), id);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  box.justification  = Justification.center;
  return box;
}

UiBox* pushLayout(const(char)[] id, Axis2 flowDirection) {
  auto result = makeLayout(id, flowDirection);
  pushParent(result);
  return result;
}

struct ScopedLayout {
  @nogc: nothrow:

  @disable this();

  this(const(char)[] id, Axis2 flowDirection) {
    pushLayout(id, flowDirection);
  }

  ~this() {
    popParent();
  }
}

// Makes a layout encompassing the bounding box of the top and bottom screens together, splitting into 3 columns with
// the center one being the width of the bottom screen.
struct ScopedCombinedScreenSplitLayout {
  @nogc: nothrow:

  UiBox* main, left, center, right;

  @disable this();

  this(const(char)[] mainId, const(char)[] leftId, const(char)[] centerId, const(char)[] rightId) {
    main   = pushLayout(mainId,   Axis2.x);
    left   = makeLayout(leftId,   Axis2.y);
    center = makeLayout(centerId, Axis2.y);
    right  = makeLayout(rightId,  Axis2.y);
    // @TODO: Fix layout violation resolution so that the left and right sizes are figured out automatically...
    main.semanticSize[Axis2.x]   = UiSize(UiSizeKind.pixels, SCREEN_TOP_WIDTH,  1);
    main.semanticSize[Axis2.y]   = UiSize(UiSizeKind.pixels, SCREEN_HEIGHT * 2, 1);
    left.semanticSize[Axis2.x]   = UiSize(UiSizeKind.pixels, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2,  1);
    left.semanticSize[Axis2.y]   = UiSize(UiSizeKind.pixels, SCREEN_HEIGHT * 2, 1);
    center.semanticSize[Axis2.x] = UiSize(UiSizeKind.pixels, SCREEN_BOTTOM_WIDTH, 1);
    center.semanticSize[Axis2.y] = UiSize(UiSizeKind.pixels, SCREEN_HEIGHT * 2,   1);
    right.semanticSize[Axis2.x]  = UiSize(UiSizeKind.pixels, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2,  1);
    right.semanticSize[Axis2.y]  = UiSize(UiSizeKind.pixels, SCREEN_HEIGHT * 2, 1);
  }

  void startLeft()   { gUiData.curBox = left;   }
  void startCenter() { gUiData.curBox = center; }
  void startRight()  { gUiData.curBox = right;  }

  ~this() {
    gUiData.curBox = main;
    popParent();
  }
}

// Makes a layout splitting the screen in two vertically.
struct ScopedDoubleScreenSplitLayout {
  @nogc: nothrow:

  UiBox* main, top, bottom;

  @disable this();

  this(const(char)[] mainId, const(char)[] topId, const(char)[] bottomId) {
    main   = pushLayout(mainId,   Axis2.y);
    top    = makeLayout(topId,    Axis2.x);
    bottom = makeLayout(bottomId, Axis2.x);
    // @TODO: Fix layout violation resolution so that the top and bottom sizes are figured out automatically...
    main.semanticSize[Axis2.x]   = UiSize(UiSizeKind.percent_of_parent, 1, 0);
    main.semanticSize[Axis2.y]   = UiSize(UiSizeKind.pixels, SCREEN_HEIGHT * 2, 1);
    top.semanticSize[Axis2.x]    = UiSize(UiSizeKind.percent_of_parent, 1, 0);
    top.semanticSize[Axis2.y]    = UiSize(UiSizeKind.pixels, SCREEN_HEIGHT, 1);
    bottom.semanticSize[Axis2.x] = UiSize(UiSizeKind.percent_of_parent, 1, 0);
    bottom.semanticSize[Axis2.y] = UiSize(UiSizeKind.pixels, SCREEN_HEIGHT, 1);
  }

  void startTop()    { gUiData.curBox = top;    }
  void startBottom() { gUiData.curBox = bottom; }

  ~this() {
    gUiData.curBox = main;
    popParent();
  }
}

UiBoxAndSignal scrollableReadPane(const(char)[] id, in LoadedPage loadedPage, ScrollCache* scrollCache) {
  UiBox* box = makeBox(UiFlags.view_scroll | UiFlags.manual_scroll_limits | UiFlags.demand_focus, id);
  box.semanticSize[] = [UiSize(UiSizeKind.percent_of_parent, 1, 0), UiSize(UiSizeKind.percent_of_parent, 1, 0)].s;
  box.scrollCache    = scrollCache;
  box.render         = &scrollCacheDraw;

  box.scrollInfo.limitMin = 0;

  auto height = box.rect.bottom - box.rect.top;
  box.scrollInfo.limitMax = max(loadedPage.actualLineNumberTable.length * loadedPage.glyphHeight + loadedPage.pageMargin * 2 - height, 0);

  return UiBoxAndSignal(box, signalFromBox(box));
}

struct ScopedStyle {
  @nogc: nothrow:

  const(BoxStyle)* oldStyle;

  @disable this();

  this(const(BoxStyle)* newStyle) {
    oldStyle      = gUiData.style;
    gUiData.style = newStyle;
  }

  ~this() {
    gUiData.style = oldStyle;
  }
}

struct UiCommand {
  uint code, value;
}

struct UiData {
  //UiBox[512] boxes;
  TemporaryStorage!(16*1024) tempAlloc;
  UiHashTable boxes;

  Input* input;
  UiBox* root, curBox;
  uint frameIndex;

  UiCommand[100] commands;
  size_t numCommands;

  UiBox* hot, active, focused;

  const(BoxStyle)* style;

  C2D_TextBuf textBuf;
}

UiData gUiData;

const(char)[] tprint(T...)(const(char)[] format, T args) {
  return gUiData.tempAlloc.printf(format.ptr, args);
}

// Returns ID part of string followed by non-ID
const(char)[][2] parseIdFromString(const(char)[] text) {
  const(char)[][2] result = [text, text];

  foreach (i; 0..text.length-1) {
    if (text[i] == '#' && text[i+1] == '#') {
      result[0]   = text[i+2..$];
      result[1]   = text[0..i];
      break;
    }
  }

  return result;
}

UiBox* makeBox(UiFlags flags, const(char)[] text) { with (gUiData) {
  const(char)[][2] idAndNon = parseIdFromString(text);
  const(char)[] id = idAndNon[0], displayText = idAndNon[1];

  UiBox* result = hashTableFindOrAlloc(&boxes, id);
  result.lastFrameTouchedIndex = frameIndex;

  result.first   = null;
  result.last    = null;
  result.next    = null;
  result.prev    = null;
  result.related = null;

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

  result.childId = result.prev == null ? 0 : result.prev.childId + 1;
  result.flags   = flags;
  result.style   = gUiData.style;

  if ((flags & UiFlags.draw_text) && displayText.length) {
    C2D_TextParse(&result.text, textBuf, displayText);
    float width, height;
    C2D_TextGetDimensions(&result.text, result.style.textSize, result.style.textSize, &width, &height);
    result.text.width = width;
    result.textHeight = height;
  }


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

UiSignal popParentAndSignal() {
  return signalFromBox(popParent());
}

void uiInit() { with (gUiData) {
  textBuf = C2D_TextBufNew(16384);
  boxes   = hashTableMake(maxElements: 512, tableElements: 128);
  tempAlloc.init();
}}

void uiFrameStart() { with (gUiData) {
  auto uiFrameStart = TimeBlock.make!("uiFrameStart");

  curBox      = null;
  root        = null;
  style       = &DEFAULT_STYLE;
  numCommands = 0;

  C2D_TextBufClear(textBuf);
}}

void handleInput(Input* newInput) { with (gUiData) {
  input = newInput;
}}

void uiFrameEnd() { with (gUiData) {
  auto uiFrameEnd = TimeBlock.make!("uiFrameEnd");

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
            box.computedSize[axis] = box.text.width + 2*box.style.margin;
          }
          else {
            box.computedSize[axis] = box.textHeight + 2*box.style.margin;
          }
          break;
        case UiSizeKind.percent_of_parent:
        case UiSizeKind.children_sum:
          break;
      }
    }

    return false;
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

    return false;
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
    if (box.flags & UiFlags.view_scroll) return false;  // Assume there really are no violations if you can scroll

    float sum = 0;
    foreach (child; eachChild(box)) {
      sum += child.computedSize[axis];
    }

    float difference = sum - box.computedSize[axis];
    if (difference > 0) {
      foreach (child; eachChild(box)) {
        float partToRemove        = min(difference * (1-child.semanticSize[axis].strictness), child.computedSize[axis]);
        child.computedSize[axis] -= partToRemove;
        difference               -= partToRemove;
      }
    }

    return false;
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

    box.rect = Rectangle(box.computedRelPosition[Axis2.x], box.computedRelPosition[Axis2.y],
                         box.computedRelPosition[Axis2.x], box.computedRelPosition[Axis2.y]);

    box.rect.right  += box.computedSize[Axis2.x];
    box.rect.bottom += box.computedSize[Axis2.y];

    if (box.parent) {
      if (box.parent.flags & UiFlags.view_scroll) {
        auto axisOfFlow = (box.parent.flags & UiFlags.horizontal_children) ? Axis2.x : Axis2.y;
        box.rect.min[axisOfFlow] -= box.parent.scrollInfo.offset;
        box.rect.max[axisOfFlow] -= box.parent.scrollInfo.offset;
      }

      box.rect.left   += box.parent.rect.left;
      box.rect.top    += box.parent.rect.top;
      box.rect.right  += box.parent.rect.left;
      box.rect.bottom += box.parent.rect.top;
    }

    return false;
  });

  hashTablePrune(&gUiData.boxes);
  gUiData.tempAlloc.reset();
  frameIndex++;
}}

// If func returns false, then children are skipped.
void preOrderApply(UiBox* box, scope bool delegate(UiBox* box) @nogc nothrow func) {
  auto runner = box;
  while (runner != null) {
    bool skipChildren = func(runner);
    if (!skipChildren && runner.first) {
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

UiSignal signalFromBox(UiBox* box) { with (gUiData) {
  UiSignal result;

  auto local = &gUiData;

  if ((box.flags & UiFlags.demand_focus) && active == null) {
    focused = box;
  }

  if (box.flags & (UiFlags.clickable | UiFlags.view_scroll)) {
    if (active == null && input.down(Key.touch)) {
      auto touchPoint = Vec2(input.touchRaw.px, input.touchRaw.py);

      // @Bug: This second check probably wouldn't work for nested scrollables if they were ever used.
      //       If you really wanted to make this work generally, you probably have to check this all the way up the UI hierarchy.
      if ( inside(box.rect - SCREEN_POS[GFXScreen.bottom], touchPoint) &&
           ( !box.parent || inside(box.parent.rect - SCREEN_POS[GFXScreen.bottom], touchPoint) ) )
      {
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

        // @Hack: Check for clickable, in case it's actually only scrollable. Should clickable/scrollable code be separated?
        if (box.flags & UiFlags.clickable) {
          audioPlaySound(SoundEffect.button_down, 0.25);
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
      auto parentFlowAxis = box.parent && (box.parent.flags & UiFlags.horizontal_children) ? Axis2.x : Axis2.y;
      if (box.parent && (box.parent.flags & UiFlags.view_scroll) && abs(input.touchDiff()[parentFlowAxis]) >= TOUCH_DRAG_THRESHOLD) {
        result.held        = false;
        result.released    = true;
        box.parent.hotT    = 1;
        box.parent.activeT = 1;
        active             = box.parent;
        hot                = box.parent;
        focused            = box.parent;
      }
      else if (inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.touchRaw.px, input.touchRaw.py))) {
        result.hovering = true;

        if ( (box.flags & UiFlags.clickable) &&
             !inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py)) )
        {
          audioPlaySound(SoundEffect.button_down, 0.25);
        }
      }
      else {
        result.released = inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py));

        if (result.released && (box.flags & UiFlags.clickable)) {
          audioPlaySound(SoundEffect.button_off, 0.25);
        }
      }
    }
    else if (active == box && input.prevHeld(Key.touch)) {
      active          = null;
      result.released = true;
      if (inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py))) {
        result.clicked  = true;

        if (box.flags & UiFlags.clickable) {
          audioPlaySound(box.style.pressedSound, box.style.pressedSoundVol);
        }
      }
    }
  }

  static UiBox* moveToSelectable(UiBox* box, int dir, scope bool delegate(UiBox*) @nogc nothrow check) {
    auto runner = box;

    if (dir == 1) {
      do {
        runner = runner.next;
      } while (runner != null && (!(runner.flags & UiFlags.selectable) || !check(runner)));
    }
    else {
      do {
        runner = runner.prev;
      } while (runner != null && (!(runner.flags & UiFlags.selectable) || !check(runner)));
    }

    return runner == null ? box : runner;
  }

  auto flowAxis = (box.flags & UiFlags.horizontal_children) ? Axis2.x : Axis2.y;
  bool needToScrollTowardsChild = false;
  UiBox* cursored = null;
  if ((box.flags & UiFlags.select_children) && box.first != null) {
    cursored = box.first;

    // Linear search our way to the current hovered child
    while (cursored && cursored.childId != box.hoveredChild) cursored = cursored.next;

    // If it's not there anymore, fallback to hovering the first selectable child if we can find it
    if (!cursored && box.first) {
      moveToSelectable(box.first, 1, a => true);
    }
  }

  if (cursored) { // We may not have found any hover target in the checks above
    Key forwardKey  = flowAxis == Axis2.x ? Key.right : Key.down;
    Key backwardKey = flowAxis == Axis2.x ? Key.left  : Key.up;

    // Assume that clickable boxes should scroll up to the bottom screen if we need to scroll to have it in view
    auto cursorBounds = flowAxis == Axis2.y && (cursored.flags & UiFlags.clickable) ?
                            clipWithinOther(box.rect, SCREEN_RECT[GFXScreen.bottom]) : box.rect;

    bool scrollOccurring = (box.flags & UiFlags.view_scroll) &&
                           ( input.scrollMethodCur == ScrollMethod.touch ||
                             ( input.scrollMethodCur == ScrollMethod.none &&
                               input.scrollVel[flowAxis] != 0 ) );
    if (scrollOccurring) {
      // Mimicking how the 3DS UI works, select nearest in-vew child while scrolling

      if (cursored.rect.max[flowAxis] > cursorBounds.max[flowAxis]) {
        cursored = moveToSelectable(cursored, -1, a => a.rect.max[flowAxis] <= cursorBounds.max[flowAxis]);
      }
      else if (cursored.rect.min[flowAxis] < cursorBounds.min[flowAxis]) {
        cursored = moveToSelectable(cursored, 1, a => a.rect.min[flowAxis] >= cursorBounds.min[flowAxis]);
      }
    }
    else if (input.down(backwardKey | forwardKey)) {
      int dir = input.down(backwardKey) ? -1 : 1;

      auto newCursored = moveToSelectable(cursored, dir, a => true);
      if (newCursored == cursored) {
        audioPlaySound(SoundEffect.scroll_stop, 0.1);
      }
      else {
        audioPlaySound(SoundEffect.button_move, 0.1);
      }
      cursored = newCursored;

      focused = box;  // @TODO: Is this a good way to solve scrolling to off-screen children?

      needToScrollTowardsChild = (box.flags & UiFlags.view_scroll) &&
                                 // @Hack: Deal with the fact that only part of the clickable area CAN be scrolled to.
                                 //        This kind of sucks.
                                 ( flowAxis != Axis2.y ||
                                   !(cursored.flags & UiFlags.clickable) ||
                                   box.scrollInfo.limitMin + SCREEN_POS[GFXScreen.bottom].y <
                                     box.rect.top + cursored.computedRelPosition[Axis2.y] ) &&
                                 ( cursored.rect.min[flowAxis] < cursorBounds.min[flowAxis] ||
                                   cursored.rect.max[flowAxis] > cursorBounds.max[flowAxis] );
    }

    box.hoveredChild = cursored.childId;
    if (!scrollOccurring) cursored.hotT = 1;
    hot = cursored; // @Note: There can only be one select_children box on screen, or else they conflict...

    // Signal pushing against scroll limit if we're holding a directional key and can't go any further
    {
      int dir = input.held(backwardKey) ? -1 : 1;

      if (input.held(forwardKey | backwardKey) && moveToSelectable(cursored, dir, a => true) == cursored) {
        result.pushingAgainstScrollLimit = true;
      }
    }
  }

  if ((box.flags & UiFlags.view_scroll) && focused == box) {
    uint allowedMethods = 1 << ScrollMethod.touch;

    // Don't allow scrolling with D-pad/circle-pad if we can select children with either of those
    // @TODO allow holding direction for some time to override this
    if (!(box.flags & UiFlags.select_children)) {
      allowedMethods = allowedMethods | (1 << ScrollMethod.dpad) | (1 << ScrollMethod.circle);
    }

    Rectangle cursorBounds;
    if (box.flags & UiFlags.select_children) {
      // Assume that clickable boxes should scroll up to the bottom screen if we need to scroll to have it in view
      cursorBounds = flowAxis == Axis2.y && (cursored.flags & UiFlags.clickable) ?
                         clipWithinOther(box.rect, SCREEN_RECT[GFXScreen.bottom]) : box.rect;

      // Scrolling towards off-screen children will occur if triggered by keying over to it until our target is on screen.
      if (input.scrollMethodCur == ScrollMethod.none && needToScrollTowardsChild) {
        input.scrollMethodCur = ScrollMethod.custom;
        input.scrollVel = 0;
      }
      else if ( input.scrollMethodCur == ScrollMethod.custom ) {
        if ( !cursored ||
             ( cursored.rect.min[flowAxis] >= cursorBounds.min[flowAxis] &&      // @Bug: Child that's bigger than parent will scroll forever!
               cursored.rect.max[flowAxis] <= cursorBounds.max[flowAxis] ) )
        {
          input.scrollMethodCur = ScrollMethod.none;
        }
      }
    }

    Vec2 scrollDiff;
    if (input.scrollMethodCur == ScrollMethod.custom) {
      scrollDiff[flowAxis] = cursored.rect.min[flowAxis] < cursorBounds.min[flowAxis] ? -5 : 5;
    }
    else {
      scrollDiff = updateScrollDiff(input, allowedMethods);
    }

    if (!(box.flags & UiFlags.manual_scroll_limits)) {
      box.scrollInfo.limitMin = 0;
      box.scrollInfo.limitMax = box.last
                                    ? box.last.computedRelPosition[flowAxis] + box.last.computedSize[flowAxis] - box.computedSize[flowAxis]
                                    : 0;
    }
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

      audioPlaySound(box.style.pressedSound, box.style.pressedSoundVol);
    }
    else if (input.prevDown(Key.a)) {
      active = null;
      result.released = true;
    }
  }

  return result;
}}

void respondToScroll(UiBox* box, UiSignal* result, Vec2 scrollDiff) { with (gUiData) { with (box.scrollInfo) {
  enum SCROLL_TICK_DISTANCE = 60;

  auto flowAxis = (box.flags & UiFlags.horizontal_children) ? Axis2.x : Axis2.y;

  offsetLast = offset;

  if (input.scrollMethodCur == ScrollMethod.touch) {
    if (!input.down(Key.touch)) {
      offset += scrollDiff[flowAxis];
    }
  }
  else {
    offset += scrollDiff[flowAxis];
  }

  if (offset < limitMin) {
    offset = limitMin;
    input.scrollVel = 0;
  }
  else if (offset > limitMax) {
    offset = limitMax;
    input.scrollVel = 0;
  }


  ////
  // handle scrolling events
  ////

  if (offset == limitMin || offset == limitMax) {
    if ( scrollJustStopped == OneFrameEvent.not_triggered &&
         offset != offsetLast )
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
       offset != offsetLast )
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

  if (floor(offset/SCROLL_TICK_DISTANCE) != floor(offsetLast/SCROLL_TICK_DISTANCE)) {
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

void render(GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState) { with (gUiData) {
  static immutable uint[] COLORS = [
    C2D_Color32(0xFF, 0x00, 0x00, 0xFF),
    C2D_Color32(0x00, 0xFF, 0x00, 0xFF),
    C2D_Color32(0x00, 0x00, 0xFF, 0xFF),
    C2D_Color32(0x88, 0x00, 0xAA, 0xFF),
  ];

  Vec2 screenPos = SCREEN_POS[screen];

  preOrderApply(root, (box) {
    if ( ( box.parent && !intersects(box.rect, box.parent.rect) ) ||
         !intersects(box.rect, SCREEN_RECT[screen]) )
    {
      return true; // children will be skipped
    }

    auto color = COLORS[box.hashKey % COLORS.length];

    if (box.render) {
      box.render(box, screen, side, _3DEnabled, slider3DState, screenPos);
    }
    else if (RENDER_DEBUG_BOXES) {
      if (box.flags & UiFlags.clickable) {
        C2D_DrawRectSolid(box.rect.left - screenPos.x, box.rect.top - screenPos.y, 0, box.rect.right - box.rect.left, box.rect.bottom - box.rect.top, color);
      }
      else {
        C2D_DrawRectSolid(box.rect.left - screenPos.x,  box.rect.top - screenPos.y,    0, box.rect.right - box.rect.left-1, 1, color);
        C2D_DrawRectSolid(box.rect.left - screenPos.x,  box.rect.bottom - screenPos.y-1, 0, box.rect.right - box.rect.left-1, 1, color);
        C2D_DrawRectSolid(box.rect.left - screenPos.x,  box.rect.top - screenPos.y,    0, 1, box.rect.bottom - box.rect.top-1, color);
        C2D_DrawRectSolid(box.rect.right - screenPos.x-1, box.rect.top - screenPos.y,    0, 1, box.rect.bottom - box.rect.top-1, color);
      }

      if (box.parent && (box.parent.flags & UiFlags.select_children) && (box.flags & UiFlags.selectable) && box.hotT > 0) {
        auto indicColor = C2D_Color32f(0x00, 0xAA/255.0, 0x11/255.0, box.hotT);
        C2D_DrawRectSolid(box.rect.left-2 - screenPos.x,  box.rect.top-2 - screenPos.y,    0, box.rect.right - box.rect.left + 2*2, 2, indicColor);
        C2D_DrawRectSolid(box.rect.left-2 - screenPos.x,  box.rect.bottom - screenPos.y,   0, box.rect.right - box.rect.left + 2*2, 2, indicColor);
        C2D_DrawRectSolid(box.rect.left-2 - screenPos.x,  box.rect.top-2 - screenPos.y,    0, 2, box.rect.bottom - box.rect.top + 2*2, indicColor);
        C2D_DrawRectSolid(box.rect.right - screenPos.x,   box.rect.top-2 - screenPos.y,    0, 2, box.rect.bottom - box.rect.top + 2*2, indicColor);
      }
    }

    return false;
  });

  // Update animation info once per frame
  // Making this separate from the first traversal because we might skip children in that one, and this should happen
  // for all boxes even if they're culled
  // @Speed: Is this slow?
  if (screen == GFXScreen.bottom) {
    preOrderApply(root, (box) {
      box.hotT    = approach(box.hotT,    0, ANIM_T_RATE);
      box.activeT = approach(box.activeT, 0, ANIM_T_RATE);

      return false;
    });
  }
}}

void loadPage(LoadedPage* page, char[][] pageLines, float textScale, float margin) { with (page) {
  if (!textArray.length) textArray = allocArray!C2D_Text(512);
  if (!textBuf)          textBuf   = C2D_TextBufNew(16384);

  page.linesInPage = pageLines.length;
  page.textSize    = textScale;
  page.pageMargin  = margin;

  if (wrapInfos.length < pageLines.length) {
    freeArray(wrapInfos);
    wrapInfos = allocArray!C2D_WrapInfo(pageLines.length);
  }
  else {
    //reuse memory if possible
    wrapInfos = wrapInfos[0..pageLines.length];
  }

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextParse(&textArray[lineNum], textBuf, pageLines[lineNum]);
    wrapInfos[lineNum] = C2D_CalcWrapInfo(&textArray[lineNum], textScale, SCREEN_BOTTOM_WIDTH - 2 * margin);
  }

  auto actualNumLines = pageLines.length;
  foreach (ref wrapInfo; wrapInfos) {
    actualNumLines += wrapInfo.words[$-1].newLineNumber;
  }

  C2D_TextGetDimensions(&textArray[0], textScale, textScale, &glyphWidth, &glyphHeight);

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

  //mainData.scrollCache.needsRepaint = true;
}}

void unloadPage(LoadedPage* page) { with (page) {
  if (textBuf) C2D_TextBufClear(textBuf);
}}

struct UiHashTable {
  UiBox*[] table;

  UiBox[] pool;
  size_t poolPos;
  UiBox* firstFree;

  @nogc: nothrow:
  UiBox* opIndex(const(char)[] text) {
    auto key   = uiBoxHash(text);
    auto index = cast(size_t) (key % this.table.length);

    UiBox* runner = this.table[index];
    while (runner && runner.hashKey != key) {
      runner = runner.hashNext;
    }

    return runner;
  }

  debug {
    struct PerfStats {
      uint collisions;
      uint longestChain;
    }
    PerfStats perfStats;
  }
}

ulong uiBoxHash(const(char)[] text) {
  // @TODO: This hash sucks!!!! Replace it!
  ulong hash = 5381;

  foreach (c; cast(const(ubyte)[]) text) {
    hash = hash * 33 ^ c;
  }

  return hash;
}

UiHashTable hashTableMake(size_t maxElements, size_t tableElements) {
  UiHashTable result;

  // @TODO: Use arenas instead
  result.pool  = allocArray!(UiBox,  true)(maxElements);
  result.table = allocArray!(UiBox*, true)(tableElements);

  return result;
}

void hashTableFree(UiHashTable* hashTable) {
  freeArray(hashTable.pool);
  freeArray(hashTable.table);
  *hashTable = UiHashTable.init;
}

UiBox* hashTableFindOrAlloc(UiHashTable* hashTable, const(char)[] text) {
  auto timeThis = TimeBlock.make!("hashTableFindOrAlloc");

  auto key      = uiBoxHash(text);
  auto index    = cast(size_t) (key % hashTable.table.length);
  UiBox* runner = hashTable.table[index], last = null;
  UiBox* result;

  bool fillingSlot = runner == null;
  if (runner) {
    debug hashTable.perfStats.collisions++;

    // Look for the end of the chain or a box with our key, if it's there
    debug uint chainLength = 0;
    while (runner) {
      if (runner.hashKey == key) {
        result = runner;
        break;
      }
      last   = runner;
      runner = runner.hashNext;
      debug chainLength++;
    }

    debug if (chainLength > hashTable.perfStats.longestChain) {
      hashTable.perfStats.longestChain = chainLength;
    }
  }

  if (!result) {
    // Looks like we must add to the end of the chain, so allocate on the free list
    if (hashTable.firstFree) {
      result              = hashTable.firstFree;
      hashTable.firstFree = hashTable.firstFree.freeListNext;
    }
    else {
      assert(hashTable.poolPos < hashTable.pool.length);
      result = &hashTable.pool[hashTable.poolPos];
      hashTable.poolPos++;
    }

    if (fillingSlot) {
      hashTable.table[index] = result;
    }

    *result = UiBox.init;
    result.hashKey  = key;
    if (last) last.hashNext = result;
    result.hashPrev = last;
    result.hashNext = null;
  }

  return result;
}

void hashTableRemove(UiHashTable* hashTable, UiBox* box) {
  assert(box >= hashTable.pool.ptr && box < hashTable.pool.ptr + hashTable.pool.length);

  if (box.hashPrev) {
    box.hashPrev.hashNext = box.hashNext;
  }

  if (box.hashNext) {
    box.hashNext.hashPrev = box.hashPrev;
  }

  box.freeListNext    = hashTable.firstFree;
  hashTable.firstFree = box;

  box.hashKey = 0;

  // @Note: Doesn't update the table array - only hashTablePrune knows enough to do that without a loop. Is this a bad API?
}

void hashTablePrune(UiHashTable* hashTable) {
  auto hashTablePrune = TimeBlock.make!("hashTablePrune");

  foreach (ref box; hashTable.table) {
    auto runner = box;

    while (runner) {
      if (runner.lastFrameTouchedIndex != gUiData.frameIndex) {
        hashTableRemove(hashTable, runner);
        if (box == runner) box = runner.next;
      }
      runner = runner.next;
    }
  }
}