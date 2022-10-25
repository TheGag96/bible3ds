module bible.util;

public import bible.types;
public import core.stdc.stdio : printf;
public import std.algorithm   : min, max;
public import std.math        : floor, ceil, round;

nothrow: @nogc:

///////////////
// Constants //
///////////////

enum SCREEN_WIDTH  = 400;
enum SCREEN_HEIGHT = 240;
enum SCREEN_CENTER = Vec3(SCREEN_WIDTH/2, SCREEN_HEIGHT/2, 0);

enum VB_3DS_DIFF_X = 16;
enum VB_3DS_DIFF_Y = 16;

enum FRAMERATE_VB = 50.0;
enum FRAMERATE    = 60.0;
enum VB_3DS_FRAMERATE_RATIO = FRAMERATE_VB/FRAMERATE;

enum BLOCK_SIZE = 16;

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
  return cast(T)((1-amount)*a + amount*b);
}

//wish this could use "lazy", but it's incompatible with nothrow and @nogc by a design flaw in D
auto profile(string id, T)(scope T delegate() nothrow @nogc exp, int line) {
  import ctru;

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

  printf("\x1b[%d;1H%s Min:   %6.4f\x1b[K",      line,     id.ptr, timeMin);
  printf("\x1b[%d;1H%s Max:   %6.4f\x1b[K",      line + 1, id.ptr, timeMax);
  printf("\x1b[%d;1H%s Avg:   %6.4f @ %d\x1b[K", line + 2, id.ptr, timeAvg, num);

  static if (!is(T == void)) {
    return result;
  }
}
