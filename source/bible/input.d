module bible.input;

public import ctru.services.hid;
import std.algorithm : max, min;
import std.math;
import bible.util;

nothrow: @nogc:

struct ScrollDiff {
  float x = 0, y = 0;
}

enum ScrollMethod {
  none, dpad, circle, touch
}

struct Input {
  nothrow: @nogc:

  uint downRaw,     heldRaw,
       prevDownRaw, prevHeldRaw;

  touchPosition touchRaw, prevTouchRaw, prevPrevTouchRaw, firstTouchRaw;
  circlePosition circleRaw, prevCircleRaw;

  ScrollMethod scrollMethodCur;
  float scrollVel = 0;

  bool down(Key k) {
    return cast(bool)(downRaw & k);
  }

  bool held(Key k) {
    return cast(bool)(heldRaw & k);
  }

  bool prevDown(Key k) {
    return cast(bool)(prevDownRaw & k);
  }

  bool prevHeld(Key k) {
    return cast(bool)(prevHeldRaw & k);
  }

  bool allHeld(Key k) {
    return (heldRaw & k) == k;
  }

  bool allPrevHeld(Key k) {
    return (prevHeldRaw & k) == k;
  }

  bool allNewlyHeld(Key k) {
    return allHeld(k) && !allPrevHeld(k);
  }

  intpair touchDiff() {
    return intpair(touchRaw.px - firstTouchRaw.px, touchRaw.py - firstTouchRaw.py);
  }
}

void updateInput(Input* input, uint _down, uint _held, touchPosition _touch, circlePosition _circle) { with (input) {
  //prevent left+right and up+down
  if (_down & Key.left) _down = _down & ~(Key.right);
  if (_down & Key.down) _down = _down & ~(Key.up);

  if (_held & Key.left) _held = _held & ~(Key.right);
  if (_held & Key.down) _held = _held & ~(Key.up);

  prevPrevTouchRaw = prevTouchRaw;

  prevDownRaw = downRaw;
  prevHeldRaw = heldRaw;
  prevTouchRaw = touchRaw;
  prevCircleRaw = circleRaw;

  downRaw = _down;
  heldRaw = _held;
  touchRaw = _touch;
  circleRaw = _circle;

  if (down(Key.touch)) {
    firstTouchRaw = touchRaw;
  }
}}

ScrollDiff updateScrollDiff(Input* input) { with (input) {
  ScrollDiff result;

  enum CIRCLE_DEADZONE = 15;

  final switch (scrollMethodCur) {
    case ScrollMethod.none: break;
    case ScrollMethod.dpad:
      if (!held(Key.dup | Key.ddown | Key.dleft | Key.dright)) {
        scrollMethodCur = ScrollMethod.none;
      }
      break;
    case ScrollMethod.circle:
      if (circleRaw.dy * circleRaw.dy + circleRaw.dx * circleRaw.dx <= CIRCLE_DEADZONE * CIRCLE_DEADZONE) {
        scrollMethodCur = ScrollMethod.none;
      }
      break;
    case ScrollMethod.touch:
      if (!held(Key.touch)) {
        scrollMethodCur = ScrollMethod.none;
      }
      break;
  }

  if (scrollMethodCur == ScrollMethod.none) {
    StartScrollingSwitch:
    foreach (method; ScrollMethod.min..ScrollMethod.max+1) {
      final switch (method) {
        case ScrollMethod.none: break;
        case ScrollMethod.dpad:
          if (held(Key.dup | Key.ddown | Key.dleft | Key.dright)) {
            scrollMethodCur = cast(ScrollMethod) method;
            break StartScrollingSwitch;
          }
          break;
        case ScrollMethod.circle:
          if (circleRaw.dy * circleRaw.dy + circleRaw.dx * circleRaw.dx > CIRCLE_DEADZONE * CIRCLE_DEADZONE) {
            scrollMethodCur = cast(ScrollMethod) method;
            break StartScrollingSwitch;
          }
          break;
        case ScrollMethod.touch:
          if (held(Key.touch)) {
            scrollMethodCur = cast(ScrollMethod) method;
            break StartScrollingSwitch;
          }
          break;
      }
    }

    if (scrollMethodCur != ScrollMethod.none) scrollVel = 0;
  }

  final switch (scrollMethodCur) {
    case ScrollMethod.none:
      if (prevHeld(Key.touch)) {
        scrollVel = max(min(prevTouchRaw.py - prevPrevTouchRaw.py, 40), -40);
      }
      result.y = scrollVel;
      scrollVel *= 0.95;

      if (fabs(scrollVel) < 3) {
        scrollVel = 0;
      }
      break;
    case ScrollMethod.dpad:
      if      (held(Key.dup))    result.y =  5;
      else if (held(Key.ddown))  result.y = -5;
      else if (held(Key.dleft))  result.x = -5;
      else if (held(Key.dright)) result.x =  5;
      break;
    case ScrollMethod.circle:
      result = ScrollDiff(circleRaw.dx/10, circleRaw.dy/10);
      break;
    case ScrollMethod.touch:
      result = ScrollDiff(touchRaw.px - prevTouchRaw.px, touchRaw.py - prevTouchRaw.py);
      break;
  }

  return result;
}}
