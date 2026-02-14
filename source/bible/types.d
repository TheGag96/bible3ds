module bible.types;

import std.typecons : Tuple;

@nogc: nothrow:

enum Axis2 : ubyte { x, y }

alias Vec2 = Vec!2;
alias Vec3 = Vec!3;
alias Vec4 = Vec!4;

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
  this(float val) {
    this.vals = val;
  }

  static if (n >= 3) {
    pragma(inline, true)
    pure
    this(Vec!(n-1) smaller, float last) {
      this.vals[0..n-1] = smaller.vals[];
      this.vals[n-1]    = last;
    }
  }

  static if (n >= 4) {
    pragma(inline, true)
    pure
    this(Vec!(n-2) smaller, float last1, float last2) {
      this.vals[0..n-2] = smaller.vals[];
      this.vals[n-2]    = last1;
      this.vals[n-1]    = last2;
    }
  }

  pragma(inline, true)
  pure
  Vec!n opBinary(string op)(const Vec!n other) const
  if (op == "+" || op == "-" || op == "*" || op == "/") {
    Vec!n result = this;
    mixin("result " ~ op ~ "= other;");
    return result;
  }

  pragma(inline, true)
  pure
  Vec!n opBinary(string op)(float v) const
  if (op == "*" || op == "/") {
    Vec!n result = this;

    mixin("result " ~ op ~ "= v;");

    return result;
  }

  pragma(inline, true)
  pure
  Vec!n opBinaryRight(string op)(float v) const
  if (op == "*") {
    Vec!n result = this;

    mixin("result " ~ op ~ "= v;");

    return result;
  }

  pragma(inline, true)
  pure
  ref Vec!n opOpAssign(string op)(const Vec!n other) return
  if (op == "+" || op == "-" || op == "*" || op == "/") {
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

  static if (n >= 3) {
    pragma(inline, true)
    pure
    Vec!2 xy() {
      return Vec!2(x, y);
    }
  }

  static if (n >= 4) {
    pragma(inline, true)
    pure
    Vec!3 xyz() {
      return Vec!3(x, y, z);
    }
  }
}

struct Rectangle {
  @nogc: nothrow: @safe:

  union {
    struct {
      float[2] min = 0, max = 0;
    }
    struct {
      float left, top, right, bottom;
    }
  }

  pragma(inline, true)
  pure
  this(float left, float top, float right, float bottom) {
    this.left = left; this.top = top; this.right = right; this.bottom = bottom;
  }

  pragma(inline, true)
  ref Rectangle opOpAssign(string op, size_t n)(const Vec!n vec)
  if (op == "+" || op == "-") {
    mixin("this.left   " ~ op ~ "= vec.x;");
    mixin("this.top    " ~ op ~ "= vec.y;");
    mixin("this.right  " ~ op ~ "= vec.x;");
    mixin("this.bottom " ~ op ~ "= vec.y;");
    return this;
  }

  pragma(inline, true)
  pure
  Rectangle opBinary(string op, size_t n)(const Vec!n vec) const
  if (op == "+" || op == "-") {
    Rectangle result = this;
    mixin("result " ~ op ~ "= vec;");
    return result;
  }

  pragma(inline, true)
  ref Rectangle opOpAssign(string op)(float v)
  if (op == "*" || op == "/") {
    mixin("this.left   " ~ op ~ "= v;");
    mixin("this.top    " ~ op ~ "= v;");
    mixin("this.right  " ~ op ~ "= v;");
    mixin("this.bottom " ~ op ~ "= v;");
    return this;
  }

  pragma(inline, true)
  pure
  Rectangle opBinary(string op)(float v) const
  if (op == "*" || op == "/") {
    Rectangle result = this;
    mixin("result " ~ op ~ "= v;");
    return result;
  }

  pragma(inline, true)
  pure
  Rectangle opBinaryRight(string op)(float v) const
  if (op == "*") {
    Rectangle result = this;
    mixin("result " ~ op ~ "= v;");
    return result;
  }
}

pure nothrow @nogc @safe
Vec2 size(in Rectangle rect) {
  return Vec2(rect.right - rect.left, rect.bottom-rect.top);
}

// By convention, the mins are incusive, and the maxes are exclusive.

pure nothrow @nogc @safe
bool inside(Rectangle rect, Vec2 point) {
  return point.x >= rect.left && point.x < rect.right && point.y >= rect.top && point.y < rect.bottom;
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

pure nothrow @nogc @safe
Rectangle clipWithinOther(in Rectangle rect, in Rectangle other) {
  import std.algorithm : min, max;

  Rectangle result = void;
  result.left   = max(rect.left,   other.left);
  result.top    = max(rect.top,    other.top);
  result.right  = min(rect.right,  other.right);
  result.bottom = min(rect.bottom, other.bottom);
  return result;
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
  ref inout(T) opIndex(size_t[n] indicies...) inout {
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

enum ColorTheme : ubyte {
  neutral,
  warm,
  night,
}

struct StringNode {
  StringNode* next;
  const(char)[] str;
}

struct StringList {
  StringNode* first, last;
}
