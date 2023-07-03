module bible.util;

public import bible.types;
public import core.stdc.stdio : printf;
public import std.algorithm   : min, max;
public import std.math        : floor, ceil, round;

import ctru, citro3d;

nothrow: @nogc:

///////////////
// Constants //
///////////////

enum SCREEN_TOP_WIDTH    = 400.0f;
enum SCREEN_BOTTOM_WIDTH = 320.0f;

float screenWidth(GFXScreen screen) { return screen == GFXScreen.top ? SCREEN_TOP_WIDTH : SCREEN_BOTTOM_WIDTH; }

enum SCREEN_HEIGHT       = 240.0f;

enum FRAMERATE    = 60.0;

///////////////////////
// Utility Functions //
///////////////////////

import core.stdc.stdlib : malloc, free;

T* allocInstance(T, bool initialize = true, alias allocFunc = malloc)() {
  import core.lifetime : emplace;

  auto result = cast(T*)allocFunc(T.sizeof);
  assert(result);

  static if (initialize && __traits(compiles, () { auto test = T.init; })) {
    emplace!T(result, T.init);
  }

  return result;
}

void freeInstance(T, alias freeFunc = free)(T* ptr) {
  freeFunc(ptr);
}

T[] allocArray(T, bool initialize = true, alias allocFunc = malloc)(size_t size) {
  import core.lifetime : emplace;

  auto arrSize = T.sizeof*size;
  auto ptr = cast(T*)allocFunc(arrSize);
  assert(ptr);

  static if (initialize && __traits(compiles, () { auto test = T.init; })) {
    foreach (ref thing; ptr[0..size]) {
      emplace!T(&thing, T.init);
    }
  }

  return ptr[0..size];
}

void freeArray(T, alias freeFunc = free)(T[] arr) {
  freeFunc(arr.ptr);
}

DimSlice!(T, R.length) allocDimSlice(T, bool initialize = true, R...)(R lengths) {
  auto size = 1;
  foreach (a; lengths) {
    size *= a;
  }
  return DimSlice!(T, R.length)(allocArray!(T, initialize)(size), lengths);
}

auto dup(T, size_t n)(DimSlice!(T, n) other) {
  DimSlice!(T, n) result;
  result.arr = allocArray!(T, false)(other.arr.length);
  result.arr[] = other.arr[];
  result.sizes = other.sizes;
  return result;
}

T[n] s(T, size_t n)(auto ref T[n] array) pure nothrow @nogc @safe {
  return array;
}

struct TemporaryStorage(size_t maxSize) {
  nothrow: @nogc:

  ubyte[maxSize] data;

  ubyte* index;

  debug size_t watermark, highWatermark;

  void init() {
    reset();
    debug highWatermark = 0;
  }

  void reset() {
    index = data.ptr;
    debug watermark = 0;
  }

  pragma(inline, true)
  ubyte* alignBumpIndex(T)(size_t amount) {
    import std.math : log2;

    enum ALIGN_SHIFT_AMOUNT = cast(size_t) log2(T.alignof);

    static if (T.alignof > 1) {
      //align to minimum align of the desired allocation
      ubyte* toReturn = cast(ubyte*) (cast(size_t)index & ~((1 << ALIGN_SHIFT_AMOUNT) - 1));
      toReturn += (index != toReturn) * (1 << ALIGN_SHIFT_AMOUNT);
    }
    else {
      ubyte* toReturn = index;
    }

    ubyte* newIndex = toReturn + amount;

    debug {
      if (newIndex > data.ptr + watermark) {
        watermark = cast(size_t) (newIndex - data.ptr);

        if (watermark > highWatermark) highWatermark = watermark;
      }
    }

    if (newIndex > data.ptr + maxSize) {
      return null;
    }
    else {
      index = newIndex;
      return toReturn;
    }
  }

  void* alloc(size_t bytes) return {
    ubyte* result = alignBumpIndex!size_t(bytes);
    if (result != null) {
      return cast(void*) result;
    }
    else {
      //leak memory if allocation failed
      assert(0, "temp allocation failed");
      return malloc(bytes);
    }
  }

  T* allocInstance(T, bool initialize = true)() return {
    import core.lifetime : emplace;

    T* result = cast(T*) alignBumpIndex!T(T.sizeof);
    if (result != null) {
      static if (initialize && __traits(compiles, () { auto test = T.init; })) {
        emplace!T(result, T.init);
      }

      return result;
    }
    else {
      //leak memory if allocation failed
      assert(0, "temp allocation failed");
      return cast(T*) malloc(T.sizeof);
    }
  }

  T[] allocArray(T, bool initialize = true)(size_t size) return {
    import core.lifetime : emplace;

    T* result = cast(T*) alignBumpIndex!T(size*T.sizeof);
    if (result != null) {
      static if (initialize && __traits(compiles, () { auto test = T.init; })) {
        emplace!T(result, T.init);
      }

      return result[0..size];
    }
    else {
      //leak memory if allocation failed
      assert(0, "temp allocation failed");
      return (cast(T*) malloc(T.sizeof*size))[0..size];
    }
  }

  pragma(printf)
  extern(C) char[] printf(const(char)* spec, ...) {
    import core.stdc.stdio  : vsnprintf;
    import core.stdc.stdarg : va_list, va_start, va_end;

    va_list args;
    va_start(args, spec);

    size_t spaceRemaining = maxSize - (index-data.ptr);

    int length = vsnprintf(cast(char*) index, spaceRemaining, spec, args);

    assert(length >= 0); //no idea what to do if length comes back negative

    if (length+1 <= spaceRemaining) {
      ubyte* result = alignBumpIndex!char(length);
      return (cast(char*) result)[0..length];
    }
    else {
      //leak memory if allocation failed
      assert(0, "temp allocation failed");
      auto buf = cast(char*) malloc(length+1);
      vsnprintf(buf, length+1, spec, args);
      return buf[0..length];
    }

    va_end(args);
  }
}

__gshared TemporaryStorage!(16*1024) gTempStorage;

@trusted
ubyte[] readFile(alias allocFunc = malloc)(scope const(char)[] filename) {
  import core.stdc.stdio;

  auto file = fopen(filename.ptr, "rb".ptr);
  fseek(file, 0, SEEK_END);
  auto size = ftell(file);
  rewind(file);

  ubyte[] buf = allocArray!(ubyte, false, allocFunc)(size);

  fread(buf.ptr, 1, size, file);
  fclose(file);

  return buf;
}

@trusted
char[] readTextFile(alias allocFunc = malloc)(scope const(char)[] filename) {
  import core.stdc.stdio;

  auto file = fopen(filename.ptr, "r".ptr);
  fseek(file, 0, SEEK_END);
  auto size = ftell(file);
  rewind(file);

  char[] buf = allocArray!(char, false, allocFunc)(size);

  fread(buf.ptr, 1, size, file);
  fclose(file);

  return buf;
}

@trusted
char[] readCompressedTextFile(alias allocFunc = malloc)(scope const(char)[] filename) {
  import ctru.util.decompress;

  auto compressed = readFile(filename);
  scope (exit) freeArray(compressed);

  DecompressType decompType;
  size_t decompSize;

  ssize_t bytesForHeader = decompressHeader(
    &decompType,
    &decompSize,
    null,
    compressed.ptr,
    compressed.length
  );

  assert(bytesForHeader != -1);

  char[] buf = allocArray!(char, false, allocFunc)(decompSize);

  bool success = decompress(
    buf.ptr,
    buf.length,
    null,
    compressed.ptr,
    compressed.length
  );

  assert(success);

  return buf;
}

T approach(T)(T current, T target, T rate) {
  T result = current;

  if (result < target) {
    result += rate;
    if (result > target) result = target;
  }
  else if (result > target) {
    result -= rate;
    if (result < target) result = target;
  }

  return result;
}

T lerp(T)(T a, T b, float amount) {
  return cast(T)(a*(1-amount) + b*amount);
}

//fmod doesn't handle negatives the way you'd expect, so we need this instead
float wrap(float x, float mod) {
  import core.stdc.math : floor;
  return x - mod * floor(x/mod);
}

struct EnumRange(T) if (is(T == enum)) {
  T first, last;

  T    front()    { return first; }
  bool empty()    { return first > last; }
  void popFront() { first = cast(T) (first+1); }

  bool opBinaryRight(string op : "in")(T val) { return val >= first && val <= last; }
}

pragma(inline, true)
auto enumRange(T)() if (is(T == enum)) {
  return EnumRange!T(T.min, T.max);
}

pragma(inline, true)
auto enumRange(T)(T first, T last) if (is(T == enum)) {
  return EnumRange!T(first, last);
}

//wish this could use "lazy", but it's incompatible with nothrow and @nogc by a design flaw in D
auto profile(string id, T)(scope T delegate() nothrow @nogc exp, int line) {
  import ctru;

  static struct ProfileResult {
    T returnVal;
    float time, timeMin, timeMax, timeAvg;
  }

  __gshared TickCounter tickCounter;
  static float timeMin = float.infinity, timeMax = -float.infinity, timeAvg = 0;
  static int num = 0;
  static bool started = false;

  if (!started) {
    osTickCounterStart(&tickCounter);
    started = true;
  }

  osTickCounterUpdate(&tickCounter);

  static if (is(T == void)) {
    exp();
  }
  else {
    auto result = exp();
  }

  osTickCounterUpdate(&tickCounter);
  float time = osTickCounterRead(&tickCounter);

  if (time < timeMin) timeMin = time;
  if (time > timeMax) timeMax = time;

  timeAvg = (timeAvg * num + time) / (num + 1);
  num++;

  static if (!is(T == void)) {
    return ProfileResult(result, time, timeMin, timeMax, timeAvg);
  }
}

bool loadTextureFromFile(C3D_Tex* tex, C3D_TexCube* cube, string filename) {
  auto bytes = readFile(filename);
  scope (exit) freeArray(bytes);

  Tex3DS_Texture t3x = Tex3DS_TextureImport(bytes.ptr, bytes.length, tex, cube, false);
  if (!t3x)
    return false;

  // Delete the t3x object since we don't need it
  Tex3DS_TextureFree(t3x);
  return true;
}