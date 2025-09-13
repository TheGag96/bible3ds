module bible.util;

public import bible.types;
public import core.stdc.stdio : printf;
public import std.algorithm   : min, max;
public import std.math        : floor, ceil, round, log2;

version (_3DS) {
  import ctru : ssize_t, GFXScreen;
}
import core.stdc.stdarg : va_list, va_start, va_end;

nothrow: @nogc:

///////////////
// Constants //
///////////////

enum SCREEN_TOP_WIDTH    = 400.0f;
enum SCREEN_BOTTOM_WIDTH = 320.0f;

version (_3DS) {
  float screenWidth(GFXScreen screen) { return screen == GFXScreen.top ? SCREEN_TOP_WIDTH : SCREEN_BOTTOM_WIDTH; }
}

enum SCREEN_HEIGHT       = 240.0f;

enum FRAMERATE    = 60.0;

///////////////////////
// Utility Functions //
///////////////////////

import core.stdc.stdlib : malloc, free;

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

enum ArenaFlags : uint {
  defaults  = 0,
  no_init   = (1 << 0),
  soft_fail = (1 << 1),
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

ubyte[] remaining(Arena* arena) {
  return arena.data[arena.index - arena.data.ptr..$];
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
ubyte* arenaAlignBumpIndex(Arena* arena, size_t amount, ArenaFlags flags, size_t alignment) { with (arena) {
  ubyte* toReturn = cast(ubyte*) ((cast(size_t)index + alignment - 1) & ~(alignment - 1));
  ubyte* newIndex = toReturn + amount;

  debug {
    if (newIndex > data.ptr + watermark) {
      watermark = cast(size_t) (newIndex - data.ptr);

      if (watermark > highWatermark) highWatermark = watermark;
    }
  }

  if (newIndex > data.ptr + data.length) {
    if (!(flags & ArenaFlags.soft_fail)) {
      assert(0, "Arena allocation failed!");  // @TODO: Consider chained arenas
    }
    return null;
  }
  else {
    index = newIndex;
    return toReturn;
  }
}}

ubyte[] pushBytes(Arena* arena, size_t bytes, ArenaFlags flags = ArenaFlags.defaults, size_t aligning = 1) {
  import core.stdc.string : memset;

  ubyte[] result;
  ubyte* ptr = arenaAlignBumpIndex(arena, bytes, flags, aligning);
  if (ptr) {
    if (!(flags & ArenaFlags.no_init)) {
      memset(ptr, 0, bytes);
    }
    result = (cast(ubyte*) ptr)[0..bytes];
  }

  return result;
}

T* push(T)(Arena* arena, ArenaFlags flags = ArenaFlags.defaults) {
  import core.lifetime : emplace;

  T* result = cast(T*) arenaAlignBumpIndex(arena, T.sizeof, flags, T.alignof);
  static if (__traits(compiles, () { auto test = T.init; })) {
    if (result && !(flags & ArenaFlags.no_init)) {
      emplace!T(result, T.init);
    }
  }

  return result;
}

T[] pushArray(T)(Arena* arena, size_t size, ArenaFlags flags = ArenaFlags.defaults) {
  import core.lifetime : emplace;

  T[] result;
  T* ptr = cast(T*) arenaAlignBumpIndex(arena, size*T.sizeof, flags, T.alignof);
  if (ptr) {
    static if (__traits(compiles, () { auto test = T.init; })) {
      if (!(flags & ArenaFlags.no_init)) {
        foreach (i; 0..size) {
          emplace!T(ptr + i, T.init);
        }
      }
    }

    result = ptr[0..size];
  }

  return result;
}

Arena pushArena(Arena* parent, size_t bytes, ArenaFlags flags = ArenaFlags.defaults, size_t aligning = 16) {
  Arena result;

  result.data  = pushBytes(parent, bytes, flags | ArenaFlags.no_init, aligning);
  result.index = result.data.ptr;

  return result;
}

T* copy(T)(Arena* arena, in T thing, ArenaFlags flags = ArenaFlags.defaults) {
  auto result = push!T(arena, flags | ArenaFlags.no_init);
  if (result) {
    *result = thing;
  }
  return result;
}

T[] copyArray(T)(Arena* arena, const(T)[] arr, ArenaFlags flags = ArenaFlags.defaults) {
  import core.stdc.string : memcpy;
  auto result = pushArray!T(arena, arr.length, flags | ArenaFlags.no_init);
  if (result.ptr) {
    memcpy(result.ptr, arr.ptr, T.sizeof * arr.length);
  }
  return result;
}

void append(T)(Arena* arena, T[]* arr, in T thing, ArenaFlags flags = ArenaFlags.defaults) {
  T[] result = *arr;
  if (result.length == 0) {
    result = copyArray(arena, (&thing)[0..1], flags);
  }
  else {
    if (arena.index != cast(const(ubyte)*) (result.ptr + result.length)) {
      result = copyArray(arena, result, flags);
    }

    auto newPart = copy(arena, thing, flags);
    if (result.ptr && newPart.ptr) {
      result = result.ptr[0..result.length+1];
    }
  }

  if (result.ptr) {
    *arr = result;
  }
}

void extend(T)(Arena* arena, T[]* arr, const(T)[] other, ArenaFlags flags = ArenaFlags.defaults) {
  T[] result = *arr;
  if (result.length == 0) {
    result = copyArray(arena, other, flags);
  }
  else {
    if (arena.index != cast(const(ubyte)*) (result.ptr + result.length)) {
      result = copyArray(arena, result, flags);
    }

    auto newPart = copyArray(arena, other, flags);
    if (result.ptr && newPart.ptr) {
      result = result.ptr[0..arr.length+other.length];
    }
  }

  if (result.ptr) {
    *arr = result;
  }
}

pragma(printf)
extern(C) char[] aprintf(Arena* arena, const(char)* spec, ...) {
  va_list args;
  va_start(args, spec);
  auto result = vafprintf(arena, ArenaFlags.defaults, spec, args);
  va_end(args);
  return result;
}

pragma(printf)
extern(C) char[] afprintf(Arena* arena, ArenaFlags flags, const(char)* spec, ...) {
  va_list args;
  va_start(args, spec);
  auto result = vafprintf(arena, flags, spec, args);
  va_end(args);
  return result;
}

extern(C) char[] vafprintf(Arena* arena, ArenaFlags flags, const(char)* spec, va_list args) {
  import core.stdc.stdio  : vsnprintf;

  ptrdiff_t spaceRemaining = arena.data.length - (arena.index-arena.data.ptr);

  int length = vsnprintf(cast(char*) arena.index, spaceRemaining, spec, args);

  assert(length >= 0); //no idea what to do if length comes back negative

  // Plus one because of the null character
  char* result = cast(char*)arenaAlignBumpIndex(arena, length+1, flags, 1);

  return result ? result[0..length] : [];
}

pragma(inline, true)
bool owns(Arena* arena, void* thing) {
  return thing >= arena.data.ptr && thing < arena.data.ptr + arena.data.length;
}

Arena gTempStorage;

pragma(printf)
extern(C) char[] tprintf(const(char)* spec, ...) {
  va_list args;
  va_start(args, spec);
  auto result = vafprintf(&gTempStorage, ArenaFlags.defaults, spec, args);
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
ubyte[] readFile(Arena* arena, scope const(char)[] filename) {
  import core.stdc.stdio;

  auto file = fopen(filename.ptr, "rb".ptr);
  fseek(file, 0, SEEK_END);
  auto size = ftell(file);
  rewind(file);

  ubyte[] buf = pushBytes(arena, size, ArenaFlags.no_init, 16);  // Let's just be safe and align generously, for whatever purpose we might need...

  fread(buf.ptr, 1, size, file);
  fclose(file);

  return buf;
}

version (_3DS) {
  @trusted
  char[] readCompressedTextFile(Arena* arena, scope const(char)[] filename) {
    import ctru.util.decompress;

    auto restore = ScopedArenaRestore(&gTempStorage);

    auto compressed = readFile(&gTempStorage, filename);

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

    char[] buf = pushArray!char(arena, decompSize, ArenaFlags.no_init);

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

T clamp(T)(T x, T min, T max) {
  if (x < min) return min;
  if (x > max) return max;
  return x;
}

T floorSlop(T)(T value) {
  // Floor, but try to prevent rounding down when we're very close to the next whole number.
  return floor(value + 0.001);
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

bool canFind(T)(T haystack, T needle) {
  if (needle.length > haystack.length) return false;
  foreach (a; 0..haystack.length - needle.length + 1) {
    bool found = true;
    foreach (b; 0..needle.length) {
      if (needle[b] != haystack[a+b]) {
        found = false;
        break;
      }
    }
    if (found) return true;
  }

  return false;
}

enum StrSearchFlags : uint {
  defaults       = 0,
  include_needle = (1 << 0),  // Whether the return value includes the needle
  skip_needle    = (1 << 1),  // Whether to move haystack past the needle upon matching
  empty_on_fail  = (1 << 2),  // Whether the return value should be an empty string if no match
}

inout(char)[] consumeUntil(inout(char)[]* haystack, const(char)[] needle, StrSearchFlags flags = StrSearchFlags.defaults) {
  bool   found           = false;
  size_t amountToConsume = (flags & StrSearchFlags.empty_on_fail) ? 0 : haystack.length;

  if (needle.length <= haystack.length) {
    foreach (a; 0..haystack.length - needle.length + 1) {
      bool match = true;
      foreach (b; 0..needle.length) {
        if (needle[b] != (*haystack)[a+b]) {
          match = false;
          break;
        }
      }

      if (match) {
        amountToConsume = a;
        found           = true;
        break;
      }
    }
  }

  size_t newLength = amountToConsume;
  if (found && (flags & StrSearchFlags.include_needle)) {
    newLength += needle.length;
  }
  auto result = (*haystack)[0..newLength];

  if (found && (flags & StrSearchFlags.skip_needle)) {
    amountToConsume += needle.length;
  }
  *haystack = (*haystack)[amountToConsume..$];

  return result;
}

T kilobytes(T)(T count) { return count * 1024; }
T megabytes(T)(T count) { return count * 1024 * 1024; }
T gigabytes(T)(T count) { return count * 1024 * 1024 * 1024; }

pragma(inline, true)
void breakpoint() {
  version (_3DS) {
    import ldc.llvmasm;
    __asm("bkpt", "");
  }
  else {
    // @TODO
  }
}

T* linkedListPushBack(T)(T** first, T** last, T* toAdd) {
  if (!*first) {
    *first = toAdd;
  }

  if (*last) {
    (*last).next = toAdd;
    static if (is(typeof(toAdd.prev))) {
      toAdd.prev = *last;
    }
  }

  *last = toAdd;

  return toAdd;
}

T* linkedListPushBack(List, T)(List* list, T* toAdd) {
  return linkedListPushBack!T(&list.first, &list.last, toAdd);
}

// Returns a range over any linked-list-like thing.
// Just requires a pointer property for next.
// Optionally, an isNull property will be used to check for nullness.
auto linkedRange(T)(T* list) {
  static struct LinkedRange {
    T* front;

    static if (is(typeof(list.isNull))) {
      pragma(inline, true)
      static bool nullCheck(T* list) { return list.isNull(list); }
    }
    else {
      pragma(inline, true)
      static bool nullCheck(T* list) { return list == null; }
    }

    bool empty() {
      return nullCheck(front);
    }

    void popFront() {
      if (!nullCheck(front)) {
        front = front.next;
      }
    }
  }

  return LinkedRange(list);
}

// Returns a range over any graph-like thing that traverses it in pre-order.
// Just requires pointer properties for first, next, and parent.
// Optionally, an isNull property will be used to check for nullness.
auto preOrderRange(T)(T* graph) {
  import std.typecons : Tuple;

  static struct PreOrderRange {
    T* runner;
    int depth;

    static if (is(typeof(graph.isNull))) {
      pragma(inline, true)
      static bool nullCheck(T* graph) { return graph.isNull(graph); }
    }
    else {
      pragma(inline, true)
      static bool nullCheck(T* graph) { return graph == null; }
    }

    Tuple!(T*, int) front() {
      return Tuple!(T*, int)(runner, depth);
    }

    bool empty() {
      return nullCheck(runner);
    }

    void popFront() {
      if (!nullCheck(runner)) {
        if (!nullCheck(runner.first)) {
          runner = runner.first;
          depth++;
        }
        else if (!nullCheck(runner.next)) {
          runner = runner.next;
        }
        else {
          while (true) {
            runner = runner.parent;
            depth--;
            if (nullCheck(runner)) return;
            if (!nullCheck(runner.next)) {
              runner = runner.next;
              break;
            }
          }
        }
      }
    }
  }

  return PreOrderRange(graph, 0);
}

void pushString(Arena* arena, StringList* list, const(char)[] str) {
  auto node = linkedListPushBack(list, push!StringNode(arena));
  node.str  = str;
}