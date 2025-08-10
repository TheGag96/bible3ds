module bible.util;

public import bible.types;
public import core.stdc.stdio : printf;
public import std.algorithm   : min, max;
public import std.math        : floor, ceil, round, log2;

import ctru, citro2d, citro3d;
import core.stdc.stdarg : va_list, va_start, va_end;

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

inout(ubyte)[] representation(inout(char)[] s) {
  return cast(typeof(return)) s;
}

inout(char)[] sliceCString(inout(char)* cStr) {
  import core.stdc.string : strlen;
  return cStr[0..strlen(cStr)];
}

inout(char)[] sliceCBuffer(inout(char)[] cBuf) {
  foreach (i, c; cBuf.representation) {
    if (c == '\0') {
      cBuf = cBuf[0..i];
      break;
    }
  }
  return cBuf;
}

struct ParseIntResult(T) {
  T number;
  const(char)[] intPart;
  bool success;
}

ParseIntResult!T advanceInt(T)(const(char)[]* str, int base = 10) if (is(T == uint) || is(T == int) || is(T == ulong) || is(T == long)) {
  import std.traits;
  import core.checkedint;

  ParseIntResult!T result;

  const(char)[] local = *str;

  bool isNegative = !isUnsigned!T && local.length && local[0] == '-';
  T sign = 1;
  if (isNegative) {
    local = local[1..$];
    sign = -1;
  }

  bool overflow = false;
  size_t i = 0;
  foreach (c; local.representation) {
    T newNum = result.number;

    static if (isUnsigned!T) {
      newNum = mulu(newNum, base, overflow);
    }
    else {
      newNum = muls(newNum, base, overflow);
    }
    if (overflow) break;

    T toAdd = void;
    if (c >= '0' && c < '0' + min(base, 10)) {
      toAdd = (c - '0');
    }
    else if (c >= 'A' && c < 'A' + base - 10) {
      toAdd = (c - 'A' + 10);
    }
    else if (c >= 'a' && c < 'a' + base - 10) {
      toAdd = (c - 'a' + 10);
    }
    else {
      break;
    }
    if (isNegative) toAdd = -toAdd;

    static if (isUnsigned!T) {
      newNum = addu(newNum, toAdd, overflow);
    }
    else {
      newNum = adds(newNum, toAdd, overflow);
    }
    if (overflow) break;

    result.number = newNum;
    i++;
  }
  local = local[i..$];

  if (i > 0 && !overflow) {
    result.success = true;
    result.intPart = (*str)[0..$-local.length];
    *str = local;
  }

  return result;
}

ParseIntResult!T parseInt(T)(const(char)[] str, int base = 10) if (is(T == uint) || is(T == int) || is(T == ulong) || is(T == long)) {
  auto result = advanceInt!T(&str, base);

  // If successful, the whole string should have been consumed
  if (str.length) {
    result.success = false;
  }

  return result;
}

struct Arena {
  ubyte[] data;
  ubyte* index;

  debug size_t watermark, highWatermark;
}

Arena arenaMake(ubyte[] buffer) {
  Arena result;

  result.data  = buffer;
  result.index = buffer.ptr;

  return result;
}

Arena arenaMake(size_t bytes) {
  ubyte* ptr = cast(ubyte*) malloc(bytes);
  assert(ptr);

  return arenaMake(ptr[0..bytes]);
}

void arenaFree(Arena* arena) {
  free(arena.data.ptr);
  *arena = Arena.init;
}

void arenaClear(Arena* arena) {
  arena.index = arena.data.ptr;
  debug arena.watermark = 0;
}

struct ScopedArenaRestore {
  @nogc: nothrow:

  Arena* arena;
  ubyte* oldIndex;
  @disable this();

  pragma(inline, true)
  this(Arena* arena) {
    this.arena    = arena;
    this.oldIndex = arena.index;
  }

  pragma(inline, true)
  ~this() {
    arena.index = oldIndex;
  }
}

// Internal.
ubyte* arenaAlignBumpIndex(Arena* arena, size_t amount, size_t alignment) { with (arena) {
  ubyte* toReturn = cast(ubyte*) ((cast(size_t)index + alignment - 1) & ~(alignment - 1));
  ubyte* newIndex = toReturn + amount;

  debug {
    if (newIndex > data.ptr + watermark) {
      watermark = cast(size_t) (newIndex - data.ptr);

      if (watermark > highWatermark) highWatermark = watermark;
    }
  }

  if (newIndex > data.ptr + data.length) {
    assert(0, "Arena allocation failed!");  // @TODO: Consider chained arenas
    return null;
  }
  else {
    index = newIndex;
    return toReturn;
  }
}}

ubyte[] arenaPushBytesNoZero(Arena* arena, size_t bytes, size_t aligning = 1) {
  ubyte* result = arenaAlignBumpIndex(arena, bytes, aligning);
  return (cast(ubyte*) result)[0..bytes];
}

ubyte[] arenaPushBytes(Arena* arena, size_t bytes, size_t aligning = 1) {
  import core.stdc.string : memset;

  auto result = arenaPushBytesNoZero(arena, bytes, aligning);
  memset(result.ptr, 0, result.length);
  return result;
}

T* arenaPush(T, bool init = true)(Arena* arena) {
  import core.lifetime : emplace;

  T* result = cast(T*) arenaAlignBumpIndex(arena, T.sizeof, T.alignof);
  static if (init && __traits(compiles, () { auto test = T.init; })) {
    emplace!T(result, T.init);
  }

  return result;
}

T[] arenaPushArray(T, bool init = true)(Arena* arena, size_t size) {
  import core.lifetime : emplace;

  T* result = cast(T*) arenaAlignBumpIndex(arena, size*T.sizeof, T.alignof);
  static if (init && __traits(compiles, () { auto test = T.init; })) {
    foreach (i; 0..size) {
      emplace!T(result + i, T.init);
    }
  }

  return result[0..size];
}

Arena arenaPushArena(Arena* parent, size_t bytes, size_t aligning = 16) {
  Arena result;

  result.data  = arenaPushBytesNoZero(parent, bytes, aligning);
  result.index = result.data.ptr;

  return result;
}

T* arenaCopy(T)(Arena* arena, in T thing) {
  auto result = arenaPush!(T, false)(arena);
  *result = thing;
  return result;
}

T[] arenaCopyArray(T)(Arena* arena, const(T)[] arr) {
  import core.stdc.string : memcpy;
  auto result = arenaPushArray!(T, false)(arena, arr.length);
  memcpy(result.ptr, arr.ptr, T.sizeof * arr.length);
  return result;
}

void arenaAppend(T)(Arena* arena, T[]* arr, in T thing) {
  if (arr.ptr == null) {
    *arr = arenaCopyArray(arena, (&thing)[0..1]);
  }
  else {
    if (arena.index != cast(const(ubyte)*) (arr.ptr + arr.length)) {
      *arr = arenaCopyArray(arena, *arr);
    }

    arenaCopy(arena, thing);
    *arr = (*arr).ptr[0..arr.length+1];
  }
}

void arenaExtend(T)(Arena* arena, T[]* arr, const(T)[] other) {
  if (arr.ptr == null) {
    *arr = arenaCopyArray(arena, other);
  }
  else {
    if (arena.index != cast(const(ubyte)*) (arr.ptr + arr.length)) {
      *arr = arenaCopyArray(arena, *arr);
    }

    arenaCopyArray(arena, other);
    *arr = (*arr).ptr[0..arr.length+other.length];
  }
}

pragma(printf)
extern(C) char[] arenaPrintf(Arena* arena, const(char)* spec, ...) {
  va_list args;
  va_start(args, spec);
  auto result = arenaVprintf(arena, spec, args);
  va_end(args);
  return result;
}

extern(C) char[] arenaVprintf(Arena* arena, const(char)* spec, va_list args) {
  import core.stdc.stdio  : vsnprintf;

  int spaceRemaining = arena.data.length - (arena.index-arena.data.ptr);

  int length = vsnprintf(cast(char*) arena.index, spaceRemaining, spec, args);

  assert(length >= 0); //no idea what to do if length comes back negative

  // Plus one because of the null character
  char* result = cast(char*)arenaAlignBumpIndex(arena, length+1, 1);

  return result[0..length];
}

pragma(inline, true)
bool arenaOwns(Arena* arena, void* thing) {
  return thing >= arena.data.ptr && thing < arena.data.ptr + arena.data.length;
}

Arena gTempStorage;

pragma(printf)
extern(C) char[] tprintf(const(char)* spec, ...) {
  va_list args;
  va_start(args, spec);
  auto result = arenaVprintf(&gTempStorage, spec, args);
  va_end(args);
  return result;
}

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
char[] readCompressedTextFile(Arena* arena, scope const(char)[] filename) {
  import ctru.util.decompress;

  // @Note: Use malloc for temp allocation here. Use an arena instead?
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

  char[] buf = arenaPushArray!(char, false)(arena, decompSize);

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

enum enumCount(T) = T.max-T.min+1;

// Generate an array with a value for each member of an enum.
// @Compiler Bug: Doesn't work with large enums because of how many function parameters ther eare...
template arrayOfEnum(T, V) if (is(T == enum)) {
  static assert(T.min >= 0 && T.max >= 0, "This function doesn't handle enums with negative bounds!");

  mixin(() {
    import std.conv : to;
    string result = "V[enumCount!T] arrayOfEnum(\n";

    foreach (field; __traits(allMembers, T)) {
      result ~= "  V ";
      result ~= field;
      result ~= ",\n";
    }

    result ~= ") {\n  V[enumCount!T] result;\n";

    foreach (field; __traits(allMembers, T)) {
      result ~= "  result[T.";
      result ~= field;
      result ~= "] = ";
      result ~= field;
      result ~= ";\n";
    }

    result ~= "  return result; }";
    return result;
  }());
}

Vec4 rgba8ToRgbaF(uint color) {
  return Vec4(color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF, color >> 24) / 255;
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

T kilobytes(T)(T count) { return count * 1024; }
T megabytes(T)(T count) { return count * 1024 * 1024; }
T gigabytes(T)(T count) { return count * 1024 * 1024 * 1024; }

pragma(inline, true)
void breakpoint() {
  import ldc.llvmasm;
  __asm("bkpt", "");
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
