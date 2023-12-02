module bible.imgui;

public import bible.imgui_render;

import bible.input, bible.util, bible.audio, bible.bible;
import ctru, citro2d, citro3d;
import std.math;
import bible.profiling;

@nogc: nothrow:

enum float ANIM_T_RATE          = 0.1;
enum       TOUCH_DRAG_THRESHOLD = 8;

enum float SCROLL_EASE_RATE = 0.3;

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

enum BoxFlags : uint {
  none                 = 0,
  clickable            = 1 << 0,
  view_scroll          = 1 << 1,
  manual_scroll_limits = 1 << 2,
  draw_text            = 1 << 3,
  select_children      = 1 << 4,
  selectable           = 1 << 5,
  horizontal_children  = 1 << 6,
  demand_focus         = 1 << 7,
}

enum SizeKind : ubyte {
  none,
  pixels,
  text_content,
  percent_of_parent,
  children_sum,
}

struct Size {
  SizeKind kind;
  float value      = 0;
  float strictness = 0;
}

enum SIZE_FILL_PARENT  = Size(SizeKind.percent_of_parent, 1, 0);
enum SIZE_CHILDREN_SUM = Size(SizeKind.children_sum,      0, 1);

enum Justification : ubyte { min, center, max }

enum OneFrameEvent {
  not_triggered, triggered, already_processed,
}

struct LoadedPage {
  Arena arena;

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

  float textSize = 0;
  Vec2 pageMargin;
  Vec2 glyphSize;
}

struct ScrollInfo {
  float offset = 0, offsetLast = 0;
  float limitMin = 0, limitMax = 0;
  OneFrameEvent startedScrolling;  // @TODO: Remove these?
  OneFrameEvent scrollJustStopped;
}

enum Color : ubyte {
  clear_color,
  text,
  bg_bg,
  bg_stripes_dark,
  bg_stripes_light,
  button_normal,
  button_sel_indicator,
  button_bottom_top,
  button_bottom_base,
  button_bottom_bottom,
  button_bottom_line,
  button_bottom_pressed_top,
  button_bottom_pressed_base,
  button_bottom_pressed_bottom,
  button_bottom_pressed_line,
  button_bottom_text,
  button_bottom_text_bevel,
  button_bottom_above_fade,
  scroll_indicator,
  scroll_indicator_outline,
  scroll_indicator_pushing,
  scroll_indicator_pushing_outline,
}
alias ColorTable = uint[Color.max+1];

struct BoxStyle {
  // Must be the length of ColorTable.
  // Not making it ColorTable* because it's easy to screw up access by indexing the pointer instead of the table.
  uint[] colors;

  float margin = 0;
  float textSize = 0;
  SoundEffect pressedSound = SoundEffect.button_confirm;
  float pressedSoundVol = 0.5;
}
immutable DEFAULT_STYLE = BoxStyle.init;

struct Box {
  Box* first, last, next, prev, parent;
  Box* hashNext, hashPrev;
  Box* freeListNext;

  ulong hashKey;

  ushort childId, numChildren;

  debug const(char)[] debugString;  // Only valid during the frame it's set!
  C2D_Text text;
  float textHeight = 0;
  int hoveredChild, selectedChild;

  ScrollInfo scrollInfo;
  ScrollCache* scrollCache;

  BoxFlags flags;
  Justification justification;
  RenderCallback render;
  const(BoxStyle)* style;

  Size[Axis2.max+1] semanticSize;

  Vec2 computedRelPosition;
  Vec2 computedSize;
  Rectangle rect;

  uint lastFrameTouchedIndex;

  float hotT = 0, activeT = 0;

  Box* related;  // General-purpose field to relate boxes to other boxes.
}
pragma(msg, "Size of Box: ", Box.sizeof);

__gshared const Box gNullBoxStore = {
  first: cast(Box*) &gNullBoxStore, last: cast(Box*) &gNullBoxStore, next: cast(Box*) &gNullBoxStore, prev: cast(Box*) &gNullBoxStore, parent: cast(Box*) &gNullBoxStore,
  hashNext: cast(Box*) &gNullBoxStore, hashPrev: cast(Box*) &gNullBoxStore,
  freeListNext: cast(Box*) &gNullBoxStore,
  related: cast(Box*) &gNullBoxStore,
};
__gshared Box* gNullBox;
pragma (inline, true) bool boxIsNull(Box* box) => box is null || box is gNullBox;

// @Note: Render scroll caches forced me to make the Box* parameter non-const. Can/should this be changed?
alias RenderCallback = void function(Box* box, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, Vec2 screenPos, float z) @nogc nothrow;

struct Signal {
  Box* box;
  Vec2 touchPos, dragDelta;
  bool clicked, pressed, held, released, dragging, hovering, selected;
  int hoveredChild, selectedChild;
  bool pushingAgainstScrollLimit;
}

struct BoxAndSignal {
  Box* box;
  Signal signal;
}

bool isAncestorOf(Box* younger, Box* older) {
  younger = younger.parent;
  while (!boxIsNull(younger)) {
    if (younger == older) {
      return true;
    }
    younger = younger.parent;
  }

  return false;
}

Box* boxOrAncestorWithFlags(Box* box, BoxFlags flags) {
  while (!boxIsNull(box)) {
    if ((box.flags & flags) == flags) {
      return box;
    }
    box = box.parent;
  }

  return gNullBox;
}

bool touchInsideBoxAndAncestors(Box* box, Vec2 touchPoint) {
  Vec2 touchOnBottom = touchPoint + SCREEN_POS[GFXScreen.bottom];

  while (!boxIsNull(box)) {
    if (!inside(box.rect, touchOnBottom)) {
      return false;
    }
    box = box.parent;
  }

  return true;
}

Box* getChild(Box* box, int childId) {
  if (childId >= box.numChildren) return gNullBox;

  box = box.first;
  for (ushort i = 0; i < childId; i++) {
    box = box.next;
  }

  return box;
}

Box* label(const(char)[] text, Justification justification = Justification.min) {
  Box* box = makeBox(BoxFlags.draw_text, text);

  box.semanticSize[] = [Size(SizeKind.text_content, 0, 1), Size(SizeKind.text_content, 0, 1)].s;
  box.justification  = justification;
  box.render         = &renderLabel;

  return box;
}

Signal button(const(char)[] text, int size = 0, Justification justification = Justification.center) {
  Box* box = makeBox(BoxFlags.clickable | BoxFlags.draw_text | BoxFlags.selectable, text);

  if (size == 0) {
    box.semanticSize[Axis2.x] = Size(SizeKind.text_content, 0, 1);
  }
  else {
    box.semanticSize[Axis2.x] = Size(SizeKind.pixels, size, 1);
  }

  box.semanticSize[Axis2.y] = Size(SizeKind.text_content, 0, 1);

  box.justification = justification;
  box.render        = &renderNormalButton;

  return signalFromBox(box);
}

Signal bottomButton(const(char)[] text) {
  Box* box = makeBox(BoxFlags.clickable | BoxFlags.draw_text, text);
  box.semanticSize[] = [SIZE_FILL_PARENT, Size(SizeKind.text_content, 0, 1)].s;
  box.justification = Justification.center;
  box.render = &renderBottomButton;
  return signalFromBox(box);
}

void spacer(float size = 0) {
  Box* box = makeBox(cast(BoxFlags) 0, "");

  auto flowSize = size == 0 ? SIZE_FILL_PARENT : Size(SizeKind.pixels, size, 1);
  auto oppSze   = SIZE_FILL_PARENT;

  if (box.parent.flags & BoxFlags.horizontal_children) {
    box.semanticSize[Axis2.x] = flowSize;
    box.semanticSize[Axis2.y] = oppSze;
  }
  else {
    box.semanticSize[Axis2.x] = oppSze;
    box.semanticSize[Axis2.y] = flowSize;
  }
}

void scrollIndicator(const(char)[] id, Box* source, Justification justification, bool limitHit) {
  Box* box = makeBox(cast(BoxFlags) 0, id);
  box.render = &renderScrollIndicator;

  // @TODO: Only vertical scroll indicators are supported at the moment.
  // @Note: The widget will fill the parent but will only draw as wide as the indicator texture.
  box.semanticSize[] = [SIZE_FILL_PARENT, SIZE_FILL_PARENT].s;

  box.justification = justification;
  box.related       = source;

  box.hotT = approach(box.hotT, 1.0f*limitHit, 2*ANIM_T_RATE);
}

enum LayoutKind {
  grow_children,  // Grows as children are added.
  fit_children,   // Fits children within the parent in the direction of flow, matches the largest child size in the other.
  fill_parent,    // Tries to fit to the parent size in both directions.
}

Box* makeLayout(
  const(char)[] id,
  Axis2 flowDirection,
  Justification justification = Justification.center,
  LayoutKind layoutKind = LayoutKind.init,
  BoxFlags flags = BoxFlags.init,
) {
  Box* box = makeBox(cast(BoxFlags) ((flowDirection == Axis2.x) * BoxFlags.horizontal_children) | flags, id);

  Size flowAxisSize, oppAxisSize;
  final switch (layoutKind) {
    case LayoutKind.grow_children:
      flowAxisSize = SIZE_CHILDREN_SUM;
      oppAxisSize  = SIZE_FILL_PARENT;
      break;
    case LayoutKind.fit_children:
      flowAxisSize = SIZE_FILL_PARENT;
      oppAxisSize  = SIZE_CHILDREN_SUM;
      break;
    case LayoutKind.fill_parent:
      flowAxisSize = SIZE_FILL_PARENT;
      oppAxisSize  = SIZE_FILL_PARENT;
      break;
  }

  if (flowDirection == Axis2.x) {
    box.semanticSize[] = [flowAxisSize, oppAxisSize].s;
  }
  else { // y
    box.semanticSize[] = [oppAxisSize, flowAxisSize].s;
  }
  box.justification = justification;
  return box;
}

Box* pushLayout(
  const(char)[] id,
  Axis2 flowDirection,
  Justification justification = Justification.center,
  LayoutKind layoutKind = LayoutKind.init,
  BoxFlags flags = BoxFlags.init,
) {
  auto result = makeLayout(id, flowDirection, justification, layoutKind, flags);
  pushParent(result);
  return result;
}

struct ScopedLayout {
  @nogc: nothrow:

  Box* box;
  alias box this;

  @disable this();

  pragma (inline, true)
  this(
    const(char)[] id,
    Axis2 flowDirection,
    Justification justification = Justification.center,
    LayoutKind layoutKind = LayoutKind.init,
    BoxFlags flags = BoxFlags.init,
  ) {
    box = pushLayout(id, flowDirection, justification, layoutKind, flags);
  }

  pragma (inline, true)
  ~this() {
    popParent();
  }
}

struct ScopedSignalLayout(BoxFlags defaultFlags = BoxFlags.init, LayoutKind defaultLayoutKind = LayoutKind.init) {
  @nogc: nothrow:

  Box* box;
  alias box this;
  Signal* signalToWrite;

  @disable this();

  pragma (inline, true)
  this(
    const(char)[] id,
    Signal* signalToWrite,
    Axis2 flowDirection,
    Justification justification = Justification.center,
    LayoutKind layoutKind = defaultLayoutKind,
    BoxFlags flags = BoxFlags.init,
  ) {
    box = pushLayout(id, flowDirection, justification, layoutKind, flags | defaultFlags);
    this.signalToWrite = signalToWrite;
  }

  pragma (inline, true)
  ~this() {
    *signalToWrite = popParentAndSignal();
  }
}

alias ScopedScrollLayout       = ScopedSignalLayout!(BoxFlags.view_scroll | BoxFlags.demand_focus, LayoutKind.fill_parent);
alias ScopedSelectLayout       = ScopedSignalLayout!(BoxFlags.select_children, LayoutKind.grow_children);
alias ScopedSelectScrollLayout = ScopedSignalLayout!(BoxFlags.view_scroll | BoxFlags.demand_focus | BoxFlags.select_children, LayoutKind.fill_parent);

// Makes a layout encompassing the bounding box of the top and bottom screens together, splitting into 3 columns with
// the center one being the width of the bottom screen.
struct ScopedCombinedScreenSplitLayout {
  @nogc: nothrow:

  Box* main, left, center, right;

  @disable this();

  pragma (inline, true)
  this(const(char)[] mainId, const(char)[] leftId, const(char)[] centerId, const(char)[] rightId) {
    main   = pushLayout(mainId,   Axis2.x);
    left   = makeLayout(leftId,   Axis2.y);
    center = makeLayout(centerId, Axis2.y);
    right  = makeLayout(rightId,  Axis2.y);
    // @TODO: Fix layout violation resolution so that the left and right sizes are figured out automatically...
    main.semanticSize[Axis2.x]   = Size(SizeKind.pixels, SCREEN_TOP_WIDTH,  1);
    main.semanticSize[Axis2.y]   = Size(SizeKind.pixels, SCREEN_HEIGHT * 2, 1);
    left.semanticSize[Axis2.x]   = Size(SizeKind.pixels, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2,  1);
    left.semanticSize[Axis2.y]   = Size(SizeKind.pixels, SCREEN_HEIGHT * 2, 1);
    center.semanticSize[Axis2.x] = Size(SizeKind.pixels, SCREEN_BOTTOM_WIDTH, 1);
    center.semanticSize[Axis2.y] = Size(SizeKind.pixels, SCREEN_HEIGHT * 2,   1);
    right.semanticSize[Axis2.x]  = Size(SizeKind.pixels, (SCREEN_TOP_WIDTH - SCREEN_BOTTOM_WIDTH)/2,  1);
    right.semanticSize[Axis2.y]  = Size(SizeKind.pixels, SCREEN_HEIGHT * 2, 1);
  }

  pragma (inline, true)
  void startLeft()   { gUiData.curBox = left;   }
  pragma (inline, true)
  void startCenter() { gUiData.curBox = center; }
  pragma (inline, true)
  void startRight()  { gUiData.curBox = right;  }

  pragma (inline, true)
  ~this() {
    gUiData.curBox = main;
    popParent();
  }
}

// Makes a layout splitting the screen in two vertically.
struct ScopedDoubleScreenSplitLayout {
  @nogc: nothrow:

  Box* main, top, bottom;

  @disable this();

  pragma (inline, true)
  this(const(char)[] mainId, const(char)[] topId, const(char)[] bottomId) {
    main   = pushLayout(mainId,   Axis2.y);
    top    = makeLayout(topId,    Axis2.x);
    bottom = makeLayout(bottomId, Axis2.x);
    // @TODO: Fix layout violation resolution so that the top and bottom sizes are figured out automatically...
    main.semanticSize[Axis2.x]   = SIZE_FILL_PARENT;
    main.semanticSize[Axis2.y]   = Size(SizeKind.pixels, SCREEN_HEIGHT * 2, 1);
    top.semanticSize[Axis2.x]    = SIZE_FILL_PARENT;
    top.semanticSize[Axis2.y]    = Size(SizeKind.pixels, SCREEN_HEIGHT, 1);
    bottom.semanticSize[Axis2.x] = SIZE_FILL_PARENT;
    bottom.semanticSize[Axis2.y] = Size(SizeKind.pixels, SCREEN_HEIGHT, 1);
  }

  pragma (inline, true)
  void startTop()    { gUiData.curBox = top;    }
  pragma (inline, true)
  void startBottom() { gUiData.curBox = bottom; }

  pragma (inline, true)
  ~this() {
    gUiData.curBox = main;
    popParent();
  }
}

BoxAndSignal scrollableReadPane(const(char)[] id, in LoadedPage loadedPage, ScrollCache* scrollCache) {
  Box* box = makeBox(BoxFlags.view_scroll | BoxFlags.manual_scroll_limits | BoxFlags.demand_focus, id);
  box.semanticSize[] = [SIZE_FILL_PARENT, SIZE_FILL_PARENT].s;
  box.scrollCache    = scrollCache;
  box.render         = &scrollCacheDraw;

  box.scrollInfo.limitMin = 0;

  auto height             = box.rect.bottom - box.rect.top;
  // Add the size of the box on the bottom screen back to the scroll limit so that you can always scroll all the
  // content to the top of the screen.
  auto extraBottomScreen  = size(clipWithinOther(box.rect, SCREEN_RECT[GFXScreen.bottom])).y;
  box.scrollInfo.limitMax = max(loadedPage.actualLineNumberTable.length * loadedPage.glyphSize.y
                                + loadedPage.pageMargin.y * 2 - height + extraBottomScreen, 0);

  return BoxAndSignal(box, signalFromBox(box));
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

struct Command {
  uint code, value;
}

struct UiData {
  Arena uiArena, frameArena;  // frameArena is cleared each frame
  BoxHashTable boxes;

  Input* input;
  Box* root, curBox;
  uint frameIndex;

  Command[100] commands;
  size_t numCommands;

  Box* hot, active, focused;

  const(BoxStyle)* style;

  C2D_TextBuf textBuf;
}

__gshared UiData* gUiData;

pragma(inline, true)
const(char)[] tprint(T...)(const(char)[] format, T args) {
  return arenaPrintf(&gUiData.frameArena, format.ptr, args);
}

// Returns ID part of string followed by non-ID
const(char)[][2] parseIdFromString(const(char)[] text) {
  const(char)[][2] result = [text, text];

  if (text.length) {
    foreach (i; 0..text.length-1) {
      if (text[i] == '#' && text[i+1] == '#') {
        result[0]   = text[i+2..$];
        result[1]   = text[0..i];
        break;
      }
    }
  }

  return result;
}

Box* makeBox(BoxFlags flags, const(char)[] text) { with (gUiData) {
  const(char)[][2] idAndNon = parseIdFromString(text);
  const(char)[] id = idAndNon[0], displayText = idAndNon[1];

  Box* result = hashTableFindOrAlloc(&boxes, id);
  result.lastFrameTouchedIndex = frameIndex;
  debug result.debugString = text;

  result.first   = gNullBox;
  result.last    = gNullBox;
  result.next    = gNullBox;
  result.prev    = gNullBox;
  result.parent  = gNullBox;
  result.related = gNullBox;

  result.render  = null;

  if (!boxIsNull(curBox)) {
    if (!boxIsNull(curBox.first)) {
      curBox.last.next = result;
      result.prev      = curBox.last;
      curBox.last      = result;
    }
    else {
      curBox.first = result;
      curBox.last  = result;
    }
    curBox.numChildren++;

    result.parent = curBox;
  }
  else {
    assert(boxIsNull(root), "Somehow, a second root is trying to be added to the UI tree. Don't do that!");
    root   = result;
    curBox = result;
  }

  result.childId     = cast(ushort) (boxIsNull(result.prev) ? 0 : result.prev.childId + 1);
  result.numChildren = 0;
  result.flags       = flags;
  result.style       = gUiData.style;

  if ((flags & BoxFlags.draw_text) && displayText.length) {
    C2D_TextParse(&result.text, textBuf, displayText);
    float width, height;
    C2D_TextGetDimensions(&result.text, result.style.textSize, result.style.textSize, &width, &height);
    result.text.width = width;
    result.textHeight = height;
  }

  return result;
}}

void pushParent(Box* box) { with (gUiData) {
  assert(!boxIsNull(box), "Parameter shouldn't be null");
  assert(box.parent == curBox || box == curBox, "Parameter should either be the current UI node or one of its children");
  assert(box.hashKey, "Anonymous box attempted to be pushed as parent! It's not a good idea to contain other boxes " ~
                      "within an anonymous one because the calculated size doesn't carry from frame to frame, and " ~
                      "so interactable boxes underneath it might not work properly.");
  curBox = box;
}}

Box* popParent() { with (gUiData) {
  assert(!boxIsNull(curBox), "Trying to pop to the current UI node's parent, but it's null!");
  auto result = curBox;
  curBox = curBox.parent;
  return result;
}}

Signal popParentAndSignal() {
  return signalFromBox(popParent());
}

void init(UiData* uiData, size_t arenaSize = 1*1024*1024) { with (uiData) {
  uiArena     = arenaMake(arenaSize);
  textBuf     = C2D_TextBufNew(&uiArena, 16384);
  boxes       = hashTableMake(arena: &uiArena, maxElements: 512, tableElements: 128, tempElements: 256);
  frameArena = arenaPushArena(&uiArena, 16*1024);

  if (!gNullBox) {
    gNullBox = cast(Box*) &gNullBoxStore;
  }

  hot     = gNullBox;
  focused = gNullBox;
  active  = gNullBox;
}}

void clear(UiData* uiData) { with (uiData) {
  curBox      = gNullBox;
  root        = gNullBox;
  style       = &DEFAULT_STYLE;
  numCommands = 0;

  hot     = gNullBox;
  focused = gNullBox;
  active  = gNullBox;

  hashTableClear(&boxes);
  arenaClear(&frameArena);
  C2D_TextBufClear(textBuf);

  frameIndex = 0;
}}

void frameStart(UiData* uiData, Input* input) {
  gUiData = uiData;
  uiData.input   = input;

  with (uiData) {
    curBox      = gNullBox;
    root        = gNullBox;
    style       = &DEFAULT_STYLE;
    numCommands = 0;

    C2D_TextBufClear(textBuf);
    hashTablePrune(&boxes);

    // hashKey being 0 means that they were anonymous boxes, which just got deleted from the hashTablePrune call.
    if (!boxIsNull(hot)     && (hot.lastFrameTouchedIndex     != frameIndex || hot.hashKey     == 0)) hot     = gNullBox;
    if (!boxIsNull(active)  && (active.lastFrameTouchedIndex  != frameIndex || active.hashKey  == 0)) active  = gNullBox;
    if (!boxIsNull(focused) && (focused.lastFrameTouchedIndex != frameIndex || focused.hashKey == 0)) focused = gNullBox;

    arenaClear(&frameArena);
    frameIndex++;
  }
}

void handleInput(Input* newInput) { with (gUiData) {
}}

void frameEnd() { with (gUiData) {
  mixin(timeBlock("frameEnd"));

  // Ryan Fleury's offline layout algorithm (from https://www.rfleury.com/p/ui-part-2-build-it-every-frame-immediate):
  //
  // 1. (Any order) Calculate “standalone” sizes. These are sizes that do not depend on other widgets and can be
  //    calculated purely with the information that comes from the single widget that is having its size calculated.
  // 2. (Pre-order) Calculate “upwards-dependent” sizes. These are sizes that strictly depend on an ancestor’s size,
  //    other than ancestors that have “downwards-dependent” sizes on the given axis.
  // 3. (Post-order) Calculate “downwards-dependent” sizes. These are sizes that depend on sizes of descendants.
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
        case SizeKind.none:
          box.computedSize[axis] = 0;
          break;
        case SizeKind.pixels:
          box.computedSize[axis] = box.semanticSize[axis].value;
          break;
        case SizeKind.text_content:
          if (axis == Axis2.x) {
            box.computedSize[axis] = box.text.width + 2*box.style.margin;
          }
          else {
            box.computedSize[axis] = box.textHeight + 2*box.style.margin;
          }
          break;
        case SizeKind.percent_of_parent:
        case SizeKind.children_sum:
          break;
      }
    }

    return false;
  });

  // Step 2 (upwards-dependent sizes)
  preOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      final switch (box.semanticSize[axis].kind) {
        case SizeKind.percent_of_parent:
          float parentSize;
          if (boxIsNull(box.parent)) {
            parentSize = axis == Axis2.x ? SCREEN_BOTTOM_WIDTH : SCREEN_HEIGHT; // @TODO
          }
          else {
            parentSize = box.parent.computedSize[axis];
          }

          box.computedSize[axis] = parentSize * box.semanticSize[axis].value;
          break;

        case SizeKind.none:
        case SizeKind.pixels:
        case SizeKind.text_content:
        case SizeKind.children_sum:
          break;
      }
    }

    return false;
  });


  // Step 3 (downwards-dependent sizes)
  postOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      final switch (box.semanticSize[axis].kind) {
        case SizeKind.children_sum:
          if (!!(box.flags & BoxFlags.horizontal_children) == (axis == Axis2.x)) {
            // In the direction of flow, we actually sum the children, as they're arranged one after the other.
            float sum = 0;

            foreach (child; eachChild(box)) {
              sum += child.computedSize[axis];
            }

            box.computedSize[axis] = sum;
          }
          else {
            // Against the direction of flow, children_sum will result in the size of the largest child box.
            float largest = 0;

            foreach (child; eachChild(box)) {
              if (child.computedSize[axis] > largest) {
                largest = child.computedSize[axis];
              }
            }

            box.computedSize[axis] = largest;
          }
          break;

        case SizeKind.none:
        case SizeKind.pixels:
        case SizeKind.text_content:
        case SizeKind.percent_of_parent:
          break;
      }
    }
  });

  // Step 4 (solve violations)
  preOrderApply(root, (box) {
    if (boxIsNull(box.first)) return false;  // Assume there really are no violations if there's no children

    Axis2 flowAxis = (box.flags & BoxFlags.horizontal_children) ? Axis2.x : Axis2.y;

    foreach (axis; enumRange!Axis2) {
      if (axis == flowAxis) {
        // On the axis of flow, we need to sum children to determine overages.

        // Assume there really are no violations if you can scroll in this direction
        if ((box.flags & BoxFlags.view_scroll)) continue;

        float sum = 0;
        foreach (child; eachChild(box)) {
          sum += child.computedSize[axis];
        }

        // If the children break past the size of parent...
        float limit = box.computedSize[axis];
        float difference = sum - limit;
        if (difference > 0) {
          int x;

          // Limit the desired total further by subtracting away the space that the child boxes aren't willing to give up
          foreach (child; eachChild(box)) {
            float notWillingToGiveUp = child.computedSize[axis] * child.semanticSize[axis].strictness;
            sum   -= notWillingToGiveUp;
            limit -= notWillingToGiveUp;
          }

          // Downsize all children by taking off from what they're willing to give up, proportional to how much they
          // contribute to the overage
          foreach (child; eachChild(box)) {
            child.computedSize[axis] -= child.computedSize[axis] * (1 - child.semanticSize[axis].strictness) / sum * difference;
          }
        }
      }
      else {
        // Against the axis of flow, children individually may overage and need to be corrected.
        // At the moment, just hard limit them to the parent size.
        foreach (child; eachChild(box)) {
          if (child.computedSize[axis] > box.computedSize[axis]) {
            child.computedSize[axis] = box.computedSize[axis];
          }
        }
      }
    }

    return false;
  });

  // Step 5 (compute positions)
  preOrderApply(root, (box) {
    foreach (axis; enumRange!Axis2) {
      box.computedRelPosition[axis] = 0;

      if (!boxIsNull(box.parent)) {
        if (!!(box.parent.flags & BoxFlags.horizontal_children) == (axis == Axis2.x)) {
          // Order children one after the other in the axis towards the flow of child nodes
          // @TODO: Padding
          box.computedRelPosition[axis] += box.prev.computedRelPosition[axis] + box.prev.computedSize[axis];
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


    if (box.parent.flags & BoxFlags.view_scroll) {
      auto flowAxis = (box.parent.flags & BoxFlags.horizontal_children) ? Axis2.x : Axis2.y;
      box.rect.min[flowAxis] -= box.parent.scrollInfo.offset;
      box.rect.max[flowAxis] -= box.parent.scrollInfo.offset;
    }

    box.rect.left   += box.parent.rect.left;
    box.rect.top    += box.parent.rect.top;
    box.rect.right  += box.parent.rect.left;
    box.rect.bottom += box.parent.rect.top;

    return false;
  });

  // Extra step: Figure out scroll limits for scrollables, only after computing the size and position of all boxes
  preOrderApply(root, (box) {
    if (box.flags & BoxFlags.view_scroll && !(box.flags & BoxFlags.manual_scroll_limits)) {
      auto flowAxis = (box.flags & BoxFlags.horizontal_children) ? Axis2.x : Axis2.y;
      box.scrollInfo.limitMin = 0;
      box.scrollInfo.limitMax = max(
        boxIsNull(box.last)
          ? 0
          : box.last.computedRelPosition[flowAxis] + box.last.computedSize[flowAxis] - box.computedSize[flowAxis],
        0
      );
    }

    return false;
  });
}}

// If func returns false, then children are skipped.
void preOrderApply(Box* box, scope bool delegate(Box* box) @nogc nothrow func) {
  auto runner = box;
  while (!boxIsNull(runner)) {
    bool skipChildren = func(runner);
    if (!skipChildren && !boxIsNull(runner.first)) {
      runner = runner.first;
    }
    else if (!boxIsNull(runner.next)) {
      runner = runner.next;
    }
    else {
      while (true) {
        runner = runner.parent;
        if (boxIsNull(runner)) return;
        if (!boxIsNull(runner.next)) {
          runner = runner.next;
          break;
        }
      }
    }
  }
}

void postOrderApply(Box* box, scope void delegate(Box* box) @nogc nothrow func) {
  auto runner = box;
  while (!boxIsNull(runner)) {
    if (!boxIsNull(runner.first)) {
      runner = runner.first;
    }
    else if (!boxIsNull(runner.next)) {
      func(runner);
      runner = runner.next;
    }
    else {
      func(runner);
      while (true) {
        runner = runner.parent;
        if (boxIsNull(runner)) return;
        func(runner);
        if (!boxIsNull(runner.next)) {
          runner = runner.next;
          break;
        }
      }
    }
  }
}

auto eachChild(Box* box) {
  static struct Range {
    @nogc: nothrow:

    Box* runner;

    Box* front()    { return runner; }
    bool empty()    { return boxIsNull(runner); }
    void popFront() { runner = runner.next; }
  }

  return Range(box.first);
}

Signal signalFromBox(Box* box) { with (gUiData) {
  Signal result;
  result.box = box;

  auto local = &gUiData;

  if ((box.flags & BoxFlags.demand_focus) && boxIsNull(focused) && boxIsNull(active)) {
    focused = box;
  }

  if (box.flags & (BoxFlags.clickable | BoxFlags.view_scroll)) {
    if (boxIsNull(active) && input.down(Key.touch)) {
      auto touchPoint = Vec2(input.touchRaw.px, input.touchRaw.py);

      if (touchInsideBoxAndAncestors(box, touchPoint)) {
        if (box.flags & (BoxFlags.selectable)) {
          box.hotT      = 1;
          hot           = box;
        }
        box.activeT     = 1;
        result.held     = true;
        result.pressed  = true;
        result.hovering = true;
        active          = box;

        auto ancestorToFocus = boxOrAncestorWithFlags(box, BoxFlags.demand_focus);
        if (!boxIsNull(ancestorToFocus)) focused = ancestorToFocus;

        if (!boxIsNull(box.parent)) {
          box.parent.hoveredChild  = box.childId;
          box.parent.selectedChild = box.childId;
          result.selected          = true;
        }

        // @Hack: Check for clickable, in case it's actually only scrollable. Should clickable/scrollable code be separated?
        if (box.flags & BoxFlags.clickable) {
          audioPlaySound(SoundEffect.button_down, 0.125);
        }
      }
    }
    else if (active == box && input.held(Key.touch)) {
      if (box.flags & (BoxFlags.selectable)) {
        box.hotT  = 1;
        hot       = box;
      }
      active      = box;
      result.held = true;

      // Allow scrolling an ancestor to kick in if we drag too far away
      auto scrollAncestor = boxOrAncestorWithFlags(box.parent, BoxFlags.view_scroll);
      auto parentFlowAxis = (scrollAncestor.flags & BoxFlags.horizontal_children) ? Axis2.x : Axis2.y;
      bool scrollInPlay   = scrollAncestor.scrollInfo.limitMin != scrollAncestor.scrollInfo.limitMax;
      if (!boxIsNull(scrollAncestor) && scrollInPlay && abs(input.touchDiff()[parentFlowAxis]) >= TOUCH_DRAG_THRESHOLD) {
        if (scrollAncestor.flags & (BoxFlags.selectable)) {
          scrollAncestor.hotT = 1;
          hot                 = scrollAncestor;
        }

        if (box.flags & BoxFlags.clickable) {
          audioPlaySound(SoundEffect.button_off, 0.125);
        }

        result.held            = false;
        result.released        = true;
        scrollAncestor.activeT = 1;
        active                 = scrollAncestor;
        focused                = scrollAncestor;
      }
      else if (inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.touchRaw.px, input.touchRaw.py))) {
        result.hovering = true;
        box.activeT     = 1;

        if ( (box.flags & BoxFlags.clickable) &&
             !inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py)) )
        {
          audioPlaySound(SoundEffect.button_down, 0.125);
        }
      }
      else {
        result.released = inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py));

        if (result.released && (box.flags & BoxFlags.clickable)) {
          audioPlaySound(SoundEffect.button_off, 0.125);
        }
      }
    }
    else if (active == box && input.prevHeld(Key.touch)) {
      active          = gNullBox;
      result.released = true;
      if (inside(box.rect - SCREEN_POS[GFXScreen.bottom], Vec2(input.prevTouchRaw.px, input.prevTouchRaw.py))) {
        result.clicked  = true;

        if (box.flags & BoxFlags.clickable) {
          audioPlaySound(box.style.pressedSound, box.style.pressedSoundVol);
        }
      }
    }
  }

  static Box* moveToSelectable(Box* box, int dir, scope bool delegate(Box*) @nogc nothrow check) {
    auto runner = box;

    if (dir == 1) {
      do {
        runner = runner.next;
      } while (!boxIsNull(runner) && (!(runner.flags & BoxFlags.selectable) || !check(runner)));
    }
    else {
      do {
        runner = runner.prev;
      } while (!boxIsNull(runner) && (!(runner.flags & BoxFlags.selectable) || !check(runner)));
    }

    return boxIsNull(runner) ? box : runner;
  }

  auto flowAxis = (box.flags & BoxFlags.horizontal_children) ? Axis2.x : Axis2.y;

  if (Box* cursored = ((box.flags & BoxFlags.select_children) && hot.parent == box) ? hot : null) {
    Key forwardKey  = flowAxis == Axis2.x ? Key.right : Key.down;
    Key backwardKey = flowAxis == Axis2.x ? Key.left  : Key.up;

    if (input.downOrRepeat(backwardKey | forwardKey)) {
      int dir = input.downOrRepeat(backwardKey) ? -1 : 1;

      auto newCursored = moveToSelectable(cursored, dir, a => true);
      if (newCursored == cursored) {
        audioPlaySound(SoundEffect.scroll_stop, 0.05);
      }
      else {
        audioPlaySound(SoundEffect.button_move, 0.05);
      }
      cursored = newCursored;
    }

    box.hoveredChild = cursored.childId;
    if (!touchScrollOcurring(*input, flowAxis)) cursored.hotT = 1;
    hot = cursored;

    // Signal pushing against scroll limit if we're holding a directional key and can't go any further
    {
      int dir = input.held(backwardKey) ? -1 : 1;

      if (input.held(forwardKey | backwardKey) && moveToSelectable(cursored, dir, a => true) == cursored) {
        result.pushingAgainstScrollLimit = true;
      }
    }
  }

  if ((box.flags & BoxFlags.view_scroll) && focused == box) {
    uint allowedMethods = 0;

    if (active == box) {
      allowedMethods |= 1 << ScrollMethod.touch;
    }

    // Don't allow scrolling with D-pad/circle-pad if we can select children with either of those
    // @TODO allow holding direction for some time to override this
    if (boxIsNull(hot)) {
      allowedMethods |= (1 << ScrollMethod.dpad) | (1 << ScrollMethod.circle);
    }

    Rectangle cursorBounds;
    bool needToScrollTowardsChild = false;
    if (isAncestorOf(hot, box))  {
      // Assume that clickable boxes should scroll up to the bottom screen if we need to scroll to have it in view
      cursorBounds = flowAxis == Axis2.y && (hot.flags & BoxFlags.clickable) ?
                        clipWithinOther(box.rect, SCREEN_RECT[GFXScreen.bottom]) : box.rect;

      auto runner = hot;
      float relToMe = 0;
      while (runner != box) {
        relToMe += runner.computedRelPosition[flowAxis];
        runner = runner.parent;
      }

      needToScrollTowardsChild = // @Hack: Deal with the fact that only part of the clickable area CAN be scrolled to.
                                 //        This kind of sucks.
                                 ( flowAxis != Axis2.y ||
                                   !(hot.flags & BoxFlags.clickable) ||
                                   box.scrollInfo.limitMin + SCREEN_POS[GFXScreen.bottom].y <
                                     box.rect.top + relToMe ) &&
                                 ( hot.rect.min[flowAxis] < cursorBounds.min[flowAxis] ||
                                   hot.rect.max[flowAxis] > cursorBounds.max[flowAxis] );
    }

    if (!inputIsNull(input) && (needToScrollTowardsChild || input.scrollMethodCur == ScrollMethod.custom)) {
      // Scrolling towards off-screen children will occur if triggered by keying over to it until our target is on screen.
      if (input.scrollMethodCur == ScrollMethod.none && input.scrollVel[flowAxis] == 0 && needToScrollTowardsChild) {
        input.scrollMethodCur = ScrollMethod.custom;
        input.scrollVel = 0;
      }
      else if ( input.scrollMethodCur == ScrollMethod.custom ) {
        if ( boxIsNull(hot) ||
             ( hot.rect.min[flowAxis] >= cursorBounds.min[flowAxis] &&      // @Bug: Child that's bigger than parent will scroll forever!
               hot.rect.max[flowAxis] <= cursorBounds.max[flowAxis] ) )
        {
          input.scrollMethodCur = ScrollMethod.none;
        }
      }
    }

    Vec2 scrollDiff;
    if (input.scrollMethodCur == ScrollMethod.custom) {
      // Scroll (with easing) towards off-box child
      scrollDiff[flowAxis] = SCROLL_EASE_RATE * ( (hot.rect.min[flowAxis] < cursorBounds.min[flowAxis])
                                                    ? (hot.rect.min[flowAxis] - cursorBounds.min[flowAxis])
                                                    : (hot.rect.max[flowAxis] - cursorBounds.max[flowAxis]) );
    }
    else if (!inputIsNull(input)) {
      scrollDiff = updateScrollDiff(input, allowedMethods);
    }

    respondToScroll(box, &result, scrollDiff);

    if (needToScrollTowardsChild && touchScrollOcurring(*input, flowAxis)) {
      // Mimicking how the 3DS UI works, select nearest in-view child while scrolling

      if (hot.rect.max[flowAxis] > cursorBounds.max[flowAxis]) {
        hot = moveToSelectable(hot, -1, a => a.rect.max[flowAxis] <= cursorBounds.max[flowAxis]);
      }
      else if (hot.rect.min[flowAxis] < cursorBounds.min[flowAxis]) {
        hot = moveToSelectable(hot, 1, a => a.rect.min[flowAxis] >= cursorBounds.min[flowAxis]);
      }
    }
  }

  if ((box.flags & BoxFlags.selectable) && hot == box && (boxIsNull(active) || active == box)) {
    if (input.down(Key.a)) {
      active          = box;
      box.activeT     = 1;
      result.clicked  = true;
      result.pressed  = true;
      result.held     = true;
      result.hovering = true;

      if (box.parent.flags & BoxFlags.select_children) {
        box.parent.hoveredChild  = box.childId;
        box.parent.selectedChild = box.childId;
        result.selected = true;
      }

      audioPlaySound(box.style.pressedSound, box.style.pressedSoundVol);
    }
    // @HACK: Checking for prevDown is unreliable if selecting the button caused us to switch views, which means we
    //        would have missed processing that input frame. We have to just force the box off of active unless we
    //        check all other cases that could make it need to stay active (right now, touch screen is the only other one).
    else if (active == box && !result.held) {
      active = gNullBox;
      result.released = true;
    }
  }

  return result;
}}

void respondToScroll(Box* box, Signal* result, Vec2 scrollDiff) { with (gUiData) { with (box.scrollInfo) {
  enum SCROLL_TICK_DISTANCE = 60;

  if (inputIsNull(input)) return;

  auto flowAxis = (box.flags & BoxFlags.horizontal_children) ? Axis2.x : Axis2.y;

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
    audioPlaySound(SoundEffect.scroll_tick, 0.025);
    startedScrolling = OneFrameEvent.already_processed;
  }

  if (floor(offset/SCROLL_TICK_DISTANCE) != floor(offsetLast/SCROLL_TICK_DISTANCE)) {
    audioPlaySound(SoundEffect.scroll_tick, 0.0125);
  }

  if (scrollJustStopped == OneFrameEvent.triggered) {
    audioPlaySound(SoundEffect.scroll_stop, 0.05);
    scrollJustStopped = OneFrameEvent.already_processed;
  }
}}}

Command[] getCommands(UiData* uiData = gUiData) { with (uiData) {
  if (uiData) {
    return commands[0..numCommands];
  }
  else {
    return [];
  }
}}

void sendCommand(uint code, uint value) { with (gUiData) {
  assert(numCommands < commands.length, "Too many UI commands in one frame!");
  commands[numCommands] = Command(code, value);
  numCommands++;
}}

void render(UiData* uiData, GFXScreen screen, GFX3DSide side, bool _3DEnabled, float slider3DState, float z = 0) { with (uiData) {
  static immutable uint[] COLORS = [
    C2D_Color32(0xFF, 0x00, 0x00, 0xFF),
    C2D_Color32(0x00, 0xFF, 0x00, 0xFF),
    C2D_Color32(0x00, 0x00, 0xFF, 0xFF),
    C2D_Color32(0x88, 0x00, 0xAA, 0xFF),
  ];

  gUiData = uiData;

  Vec2 screenPos = SCREEN_POS[screen];

  preOrderApply(root, (box) {
    if ( ( !boxIsNull(box.parent) && !intersects(box.rect, box.parent.rect) ) ||
         !intersects(box.rect, SCREEN_RECT[screen]) )
    {
      return true; // children will be skipped
    }

    auto color = COLORS[box.hashKey % COLORS.length];

    if (box.render) {
      box.render(box, screen, side, _3DEnabled, slider3DState, screenPos, z);
    }
    else if (RENDER_DEBUG_BOXES) {
      if (box.flags & BoxFlags.clickable) {
        C2D_DrawRectSolid(box.rect.left - screenPos.x, box.rect.top - screenPos.y, 0, box.rect.right - box.rect.left, box.rect.bottom - box.rect.top, color);
      }
      else {
        C2D_DrawRectSolid(box.rect.left - screenPos.x,  box.rect.top - screenPos.y,    0, box.rect.right - box.rect.left-1, 1, color);
        C2D_DrawRectSolid(box.rect.left - screenPos.x,  box.rect.bottom - screenPos.y-1, 0, box.rect.right - box.rect.left-1, 1, color);
        C2D_DrawRectSolid(box.rect.left - screenPos.x,  box.rect.top - screenPos.y,    0, 1, box.rect.bottom - box.rect.top-1, color);
        C2D_DrawRectSolid(box.rect.right - screenPos.x-1, box.rect.top - screenPos.y,    0, 1, box.rect.bottom - box.rect.top-1, color);
      }

      if ((box.parent.flags & BoxFlags.select_children) && (box.flags & BoxFlags.selectable) && box.hotT > 0) {
        auto indicColor = C2D_Color32f(0x00, 0xAA/255.0, 0x11/255.0, box.hotT);
        C2D_DrawRectSolid(box.rect.left-2 - screenPos.x,  box.rect.top-2 - screenPos.y,    0, box.rect.right - box.rect.left + 2*2, 2, indicColor);
        C2D_DrawRectSolid(box.rect.left-2 - screenPos.x,  box.rect.bottom - screenPos.y,   0, box.rect.right - box.rect.left + 2*2, 2, indicColor);
        C2D_DrawRectSolid(box.rect.left-2 - screenPos.x,  box.rect.top-2 - screenPos.y,    0, 2, box.rect.bottom - box.rect.top + 2*2, indicColor);
        C2D_DrawRectSolid(box.rect.right - screenPos.x,   box.rect.top-2 - screenPos.y,    0, 2, box.rect.bottom - box.rect.top + 2*2, indicColor);
      }

      if (box.flags & BoxFlags.draw_text) {
        auto rect = box.rect - screenPos;

        float textX = (rect.left + rect.right)/2  - box.text.width/2;
        float textY = (rect.top  + rect.bottom)/2 - box.textHeight/2;

        C2D_DrawText(
          &box.text, C2D_WithColor, GFXScreen.top, textX, textY, 0, box.style.textSize, box.style.textSize, box.style.colors[Color.text]
        );
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

void loadPage(LoadedPage* page, char[][] pageLines, int chapterNum, float textScale, Vec2 margin) { with (page) {
  if (page.arena.data.ptr) {
    arenaClear(&page.arena);
  }
  else {
    page.arena = arenaMake(1*1024*1024);
  }

  // Extra lines for the chapter heading
  // @HACK: Doing this here, but is there a better way this should work?
  auto numLines = pageLines.length+1;

  textArray = arenaPushArray!(C2D_Text, false)(&page.arena, numLines);
  textBuf   = C2D_TextBufNew(&page.arena, 16384);

  page.linesInPage = numLines;
  page.textSize    = textScale;
  page.pageMargin  = margin;

  wrapInfos = arenaPushArray!(C2D_WrapInfo, false)(&page.arena, numLines);

  // Chapter heading
  C2D_TextParse(&textArray[0], textBuf, arenaPrintf(&page.arena, "Chapter %d", chapterNum), flags : C2D_ParseFlags.bible);
  wrapInfos[0] = C2D_CalcWrapInfo(&textArray[0], &page.arena, textScale, SCREEN_BOTTOM_WIDTH - 2 * margin.x);

  foreach (lineNum; 0..pageLines.length) {
    C2D_TextParse(&textArray[lineNum+1], textBuf, pageLines[lineNum], flags : C2D_ParseFlags.bible);
    wrapInfos[lineNum+1] = C2D_CalcWrapInfo(&textArray[lineNum+1], &page.arena, textScale, SCREEN_BOTTOM_WIDTH - 2 * margin.x);
  }

  auto actualNumLines = numLines;
  foreach (ref wrapInfo; wrapInfos) {
    if (wrapInfo.words.length) {
      actualNumLines += wrapInfo.words[$-1].newLineNumber;
    }
  }

  C2D_TextGetDimensions(&textArray[0], textScale, textScale, &glyphSize.x, &glyphSize.y);

  actualLineNumberTable = arenaPushArray!(LoadedPage.LineTableEntry, false)(&page.arena, actualNumLines);

  size_t runner = 0;
  foreach (i, ref wrapInfo; wrapInfos) {
    auto realLines = (wrapInfo.words.length ? wrapInfo.words[$-1].newLineNumber : 0) + 1;

    actualLineNumberTable[runner..runner+realLines] = LoadedPage.LineTableEntry(i, runner * glyphSize.y);

    runner += realLines;
  }

  foreach (lineNum; 0..textArray.length) {
    C2D_TextOptimize(&textArray[lineNum]);
  }

  page.scrollInfo = ScrollInfo.init;

  //mainData.scrollCache.needsRepaint = true;
}}

struct BoxHashTable {
  Box*[] table;

  Box[] freePool;  // Persists between frames
  size_t freePoolPos;
  Box* firstFree;

  Box[] temp;  // Cleared each frame
  size_t tempPos;

  @nogc: nothrow:
  Box* opIndex(const(char)[] text) {
    auto key   = boxHash(text);
    auto index = cast(size_t) (key % this.table.length);

    Box* runner = this.table[index];
    while (!boxIsNull(runner) && runner.hashKey != key) {
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

ulong boxHash(const(char)[] text) {
  // @TODO: This hash sucks!!!! Replace it!
  ulong hash = 5381;

  foreach (c; cast(const(ubyte)[]) text) {
    hash = hash * 33 ^ c;
  }

  return hash;
}

BoxHashTable hashTableMake(Arena* arena, size_t maxElements, size_t tableElements, size_t tempElements) {
  BoxHashTable result;

  result.table    = arenaPushArray!(Box*, false)(arena, tableElements);
  result.table[]  = gNullBox;
  result.freePool = arenaPushArray!(Box,  true) (arena, maxElements);
  result.temp     = arenaPushArray!(Box,  true) (arena, tempElements);

  result.firstFree = gNullBox;

  return result;
}

Box* hashTableFindOrAlloc(BoxHashTable* hashTable, const(char)[] text) {
  mixin(timeBlock("hashTableFindOrAlloc"));

  Box* result = gNullBox;

  // If we're passed an empty ID, allocate it on the per-frame temporary box arena
  if (!text.length) {
    assert(hashTable.tempPos < hashTable.temp.length);
    result = &hashTable.temp[hashTable.tempPos];
    hashTable.tempPos++;

    return result;
  }

  auto key    = boxHash(text);
  auto index  = cast(size_t) (key % hashTable.table.length);
  Box* runner = hashTable.table[index], last = gNullBox;

  bool fillingSlot = boxIsNull(runner);
  if (!boxIsNull(runner)) {
    debug hashTable.perfStats.collisions++;

    // Look for the end of the chain or a box with our key, if it's there
    debug uint chainLength = 0;
    while (!boxIsNull(runner)) {
      if (runner.hashKey == key) {
        result = runner;
        assert(result.lastFrameTouchedIndex != gUiData.frameIndex, "Duplicate key or hash collision detected!");
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

  if (boxIsNull(result)) {
    // Looks like we must add to the end of the chain, so allocate on the free list
    if (!boxIsNull(hashTable.firstFree)) {
      result              = hashTable.firstFree;
      hashTable.firstFree = hashTable.firstFree.freeListNext;
    }
    else {
      assert(hashTable.freePoolPos < hashTable.freePool.length);
      result = &hashTable.freePool[hashTable.freePoolPos];
      hashTable.freePoolPos++;
    }

    if (fillingSlot) {
      hashTable.table[index] = result;
    }

    result.freeListNext = gNullBox;
    result.hashKey      = key;
    if (!boxIsNull(last)) last.hashNext = result;
    result.hashPrev     = last;
    result.hashNext     = gNullBox;
  }

  return result;
}

void hashTableRemove(BoxHashTable* hashTable, Box* box) {
  assert(box >= hashTable.freePool.ptr && box <= hashTable.freePool.ptr + hashTable.freePool.length);

  if (!boxIsNull(box.hashPrev)) {
    box.hashPrev.hashNext = box.hashNext;
  }

  if (!boxIsNull(box.hashNext)) {
    box.hashNext.hashPrev = box.hashPrev;
  }

  box.freeListNext    = hashTable.firstFree;
  hashTable.firstFree = box;

  box.hashKey = 0;

  // @Note: Doesn't update the table array - only hashTablePrune knows enough to do that without a loop. Is this a bad API?
}

void hashTablePrune(BoxHashTable* hashTable) {
  foreach (ref box; hashTable.table) {
    auto runner = box;

    while (!boxIsNull(runner)) {
      if (runner.lastFrameTouchedIndex != gUiData.frameIndex) {
        hashTableRemove(hashTable, runner);
        if (box == runner) box = runner.hashNext;
      }
      runner = runner.hashNext;
    }
  }

  hashTable.tempPos = 0;
}

void hashTableClear(BoxHashTable* hashTable) {
  hashTable.table[]     = gNullBox;
  hashTable.firstFree   = gNullBox;
  hashTable.freePoolPos = 0;
  hashTable.tempPos     = 0;
}