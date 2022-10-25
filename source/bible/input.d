module bible.input;

public import ctru.services.hid : Key;

nothrow: @nogc:

struct Input {
  nothrow: @nogc:

  uint downRaw,     heldRaw,
       prevDownRaw, prevHeldRaw;

  void update(uint _down, uint _held) {
    //prevent left+right and up+down
    if (_down & Key.left) _down = _down & ~(Key.right);
    if (_down & Key.down) _down = _down & ~(Key.up);

    if (_held & Key.left) _held = _held & ~(Key.right);
    if (_held & Key.down) _held = _held & ~(Key.up);

    prevDownRaw = downRaw;
    prevHeldRaw = heldRaw;

    downRaw = _down;
    heldRaw = _held;
  }

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
}
