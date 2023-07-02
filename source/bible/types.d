module bible.types;

import std.typecons      : Tuple;
import ctru.services.hid : Key;

@nogc: nothrow:

alias box     = Tuple!(float, "left", float, "right", float, "top", float, "bottom");
alias pair    = Tuple!(float, "x", float, "y");
alias intpair = Tuple!(int, "x", int, "y");

alias Vec2 = Vec!2;
alias Vec3 = Vec!3;

struct Vec(size_t n) {
  @nogc: nothrow: @safe:

  union {
    float[n] vals = 0;
    struct {
      float x, y;
      static if (n >= 3) float z;
      static if (n >= 4) float w;
    }
  }

  alias vals this;

  pragma(inline, true)
  pure
  this(float[n] vals...) {
    this.vals = vals;
  }

  pragma(inline, true)
  pure
  Vec!n opBinary(string op)(const Vec!n other) const
  if (op == "+" || op == "-") {
    Vec!n result = void;

    static foreach (i; 0..n) {
      mixin("result.vals[i] = vals[i] " ~ op ~ " other.vals[i];");
    }

    return result;
  }

  pragma(inline, true)
  pure
  Vec!n opBinary(string op)(float v) const
  if (op == "*" || op == "/") {
    Vec!n result = void;

    static foreach (i; 0..n) {
      mixin("result.vals[i] = vals[i] " ~ op ~ " v;");
    }

    return result;
  }

  pragma(inline, true)
  pure
  ref Vec!n opOpAssign(string op)(const Vec!n other) return
  if (op == "+" || op == "-") {
    static foreach (i; 0..n) {
      mixin("vals[i] " ~ op ~ "= other.vals[i];");
    }

    return this;
  }

  pragma(inline, true)
  pure
  ref Vec!n opOpAssign(string op)(float v) return
  if (op == "*" || op == "/")  {
    static foreach (i; 0..n) {
      mixin("vals[i] " ~ op ~ "= v;");
    }

    return this;
  }

  pragma(inline, true)
  pure
  float dot(const Vec!n other) const {
    float result = 0;

    static foreach (i; 0..n) {
      result += vals[i]*other.vals[i];
    }

    return result;
  }

  pragma(inline, true)
  pure
  float length() const {
    import std.math : sqrt;
    float sum = 0;

    static foreach (i; 0..n) {
      sum += vals[i]^^2;
    }

    return sqrt(sum);
  }

  pragma(inline, true)
  pure
  Vec!n unit() const {
    return this / length();
  }

  static if (n == 3) {
    pragma(inline, true)
    pure
    Vec!n cross(const Vec!n other) const {
      return Vec!n( (y*other.z - z*other.y), -(x*other.z - z*other.x), (x*other.y - y*other.x) );
    }
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