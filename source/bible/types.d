module bible.types;

import std.typecons      : Tuple;
import ctru.services.hid : Key;

@nogc: nothrow:

alias box     = Tuple!(float, "left", float, "right", float, "top", float, "bottom");
alias pair    = Tuple!(float, "x", float, "y");
alias intpair = Tuple!(int, "x", int, "y");

struct Vec3 {
  @nogc: nothrow: @safe:

  float x, y, z;

  pure
  Vec3 opBinary(string op)(const Vec3 other) const
  if (op == "+" || op == "-") {
    mixin("return Vec3(x" ~ op ~ "other.x, y" ~ op ~ "other.y, z" ~ op ~ "other.z );");
  }

  pure
  Vec3 opBinary(string op)(float v) const
  if (op == "*" || op == "/") {
    mixin("return Vec3(x" ~ op ~ "v, y" ~ op ~ "v, z" ~ op ~ "v );");
  }

  pure
  ref Vec3 opOpAssign(string op)(const Vec3 other) return
  if (op == "+" || op == "-") {
    mixin("x " ~ op ~ "= other.x;");
    mixin("y " ~ op ~ "= other.y;");
    mixin("z " ~ op ~ "= other.z;");
    return this;
  }

  pure
  ref Vec3 opOpAssign(string op)(float v) return
  if (op == "*" || op == "/")  {
    mixin("x " ~ op ~ "= v;");
    mixin("y " ~ op ~ "= v;");
    mixin("z " ~ op ~ "= v;");
    return this;
  }

  pragma(inline, true)
  pure
  float dot(const Vec3 other) const {
    return x*other.x + y*other.y + z*other.z;
  }

  pragma(inline, true)
  pure
  float length() const {
    import std.math : sqrt;
    return sqrt(x^^2 + y^^2 + z^^2);
  }

  pragma(inline, true)
  pure
  Vec3 unit() const {
    return this / length();
  }

  pragma(inline, true)
  pure
  Vec3 cross(const Vec3 other) const {
    return Vec3( (y*other.z - z*other.y), -(x*other.z - z*other.x), (x*other.y - y*other.x) );
  }
}

enum Direction : ubyte {
  left, right, up, down
}

pure @safe
float affinity(Direction dir) {
  final switch (dir) {
    case Direction.left:
    case Direction.up:
      return -1;
    case Direction.right:
    case Direction.down:
      return 1;
  }
}

pure @safe
Direction opposite(Direction dir) {
  final switch (dir) {
    case Direction.left:  return Direction.right;
    case Direction.right: return Direction.left;
    case Direction.up:    return Direction.down;
    case Direction.down:  return Direction.up;
  }
}

pure @safe
Key toKey(Direction dir) {
  final switch (dir) {
    case Direction.left:  return Key.left;
    case Direction.right: return Key.right;
    case Direction.up:    return Key.up;
    case Direction.down:  return Key.down;
  }
}

enum LayerIndex {
  front =  0,
  back  =  1,
  top   = -1,
}

pure @safe
float depthFactor(LayerIndex layerIndex) {
  final switch (layerIndex) {
    case LayerIndex.front:
    case LayerIndex.top:
      return 1;
    case LayerIndex.back:
      return 0.5;
  }
}

struct Rectangle {
  float left = 0, right = 0, top = 0, bottom = 0;
}

pure nothrow @nogc @safe
bool insideOrOn(Rectangle rect, Vec2 point) {
  return point.x >= rect.left && point.x <= rect.right && point.y >= rect.top && point.y <= rect.bottom;
}

pure nothrow @nogc @safe
bool intersects(const scope ref Rectangle rect, const scope ref Rectangle other) {
  if (rect.left < other.right && rect.right > other.left) {
    if (rect.top < other.bottom && rect.bottom > other.top) {
      return true;
    }
  }
  return false;
}

struct DimSlice(T, size_t n = 1) {
  nothrow:

  T[] arr;
  alias arr this;

  size_t[n] sizes;

  @nogc @safe
  this(T[] data, size_t[n] indicies...) {
    arr = data;

    static foreach (dim; 0..n) {
      sizes[dim] = indicies[dim];
    }
  }

  pragma(inline, true)
  pure nothrow @nogc @trusted
  ref T opIndex(size_t[n] indicies...) {
    auto arrIndex = 0;

    static foreach (dim; 0..n) {
      version (D_NoBoundsChecks) { }
      else assert(indicies[dim] < sizes[dim]);

      static if (dim != 0) arrIndex *= sizes[dim];
      arrIndex += indicies[dim];
    }

    //direct pointer read, since if bounds checks are on, we already checked them above
    return arr.ptr[arrIndex];
  }
}