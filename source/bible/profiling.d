// A module used to conveniently insert profiling calls anywhere in the program, patterened off of the utility Casey
// Muratori writes in his Performance-Aware Programming Course.
//
// To be used properly, the D program MUST be compiled with the option -mixin=somefile.d, or else the extremely hacky
// mechanism that allows counting unique timers at compile time will not work properly!!
//
// Used like:
// beginProfile();
// {
//   auto timeIt = TimerBlock.make!("Cool Block Name");  // Omit name to use name of current function
//   // Do some work..
// }
// endProfileAndLog();

module bible.profiling;

import ctru;
import core.stdc.stdio;

@nogc: nothrow:

struct TimerData {
  ulong elapsedExclusive;  // Excludes time spent in children
  ulong elapsedInclusive;  // Includes time spent in children
  size_t hitCount;
  string name;
}

enum MAX_TIMERS = 100;
TimerData[MAX_TIMERS] gTimerInfo;
ulong gProfilingStartTime;
size_t gProfilerParent;

pragma(inline, true)
ulong readTimestamp() {
  return svcGetSystemTick();
}

void beginProfile() {
  version (Profiling) {
    gTimerInfo[] = TimerData.init;
    gProfilingStartTime = readTimestamp();
  }
}

struct TimeBlock {
  @nogc: nothrow:

  size_t parentIndex;
  TimerData* timerData;
  ulong oldElapsedInclusive;
  ulong start;

  @disable this();

  // In order to force a unique template instantiation per use, try to combine line number, filename, and function name
  // in a pretty goofy way.
  pragma(inline, true)
  static TimeBlock make(string name = __FUNCTION__, string file = __FILE__, string pretty  = __PRETTY_FUNCTION__, int line = __LINE__)() {
    enum THIS_TIMER_INDEX = counter!().get!(hashStuff(line, file, pretty));
    import core.lifetime : move;
    TimeBlock result = void;
    result.parentIndex           = gProfilerParent;
    gProfilerParent              = THIS_TIMER_INDEX;
    result.timerData             = &gTimerInfo[THIS_TIMER_INDEX];
    result.oldElapsedInclusive   = result.timerData.elapsedInclusive;
    result.timerData.name        = name;
    result.start                 = readTimestamp();
    return result;  // @Note: Can the destructor get called here??
  }

  pragma(inline, true)
  ~this() {
    auto end     = readTimestamp();
    auto elapsed = end - start;

    timerData.elapsedExclusive += elapsed;
    timerData.elapsedInclusive  = oldElapsedInclusive + elapsed;

    // For the parent block, subtract off in place the time we spent inside the inner block.
    // This solves elapsed time being doubly counted across two timers when running one timer inside another.
    gTimerInfo[parentIndex].elapsedExclusive -= elapsed;

    gProfilerParent             = parentIndex;
    timerData.hitCount         += 1;
  }
}

// Generate a string to mixin to conveniently create a scoped timer block
string timeBlock(string name = __FUNCTION__) {
  version (Profiling) {
    char[] filtered = new char[name.length];
    size_t counter = 0;
    foreach (c; cast(ubyte[]) name) {
      if (c >= 'a' && c <='z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9') {
        filtered[counter] = c;
        counter++;
      }
    }
    filtered = filtered[0..counter];

    return "auto timeBlock_" ~ cast(string)filtered ~ " = TimeBlock.make!(\"" ~ name ~ "\");";
  }
  else {
    return "";
  }
}

void endProfileAndLog() {
  version (Profiling) {
    auto profilingEndTime = readTimestamp();
    auto totalTime        = profilingEndTime - gProfilingStartTime;

    //enum size_t cpuFreq = 268111856; // from https://3dbrew.org/wiki/Hardware
    enum ulong TIMER_FREQ = SYSCLOCK_ARM11; // @TODO: Check

    printf("Timing info (CPU freq = %llu Hz):\n", TIMER_FREQ);
    printf("Total time: %f ms (%llu cycles)\n", 1000.0*totalTime/TIMER_FREQ, totalTime);

    double percentSum = 0;
    foreach (ref it; gTimerInfo) {
      if (!it.name.length)  continue;
      auto percent      = (cast(double)it.elapsedExclusive)/totalTime * 100;

      double exclusiveMs = 1000.0*it.elapsedExclusive/TIMER_FREQ;
      if (it.elapsedExclusive != it.elapsedInclusive) {
        auto percentWithChildren = (cast(double)it.elapsedInclusive)/totalTime * 100;

        double inclusiveMs = 1000.0*it.elapsedInclusive/TIMER_FREQ;
        printf("  %-26s[%3lu]: %8llu / %6.3f ms / %6.3f%% | w/ children: %8llu / %6.3f ms / %6.3f%%\n", it.name.ptr, it.hitCount, it.elapsedExclusive, exclusiveMs, percent, it.elapsedInclusive, inclusiveMs, percentWithChildren);
      }
      else {
        printf("  %-26s[%3lu]: %8llu / %6.3f ms / %6.3f%%)\n", it.name.ptr, it.hitCount, it.elapsedExclusive, exclusiveMs, percent);
      }

      percentSum += percent;
    }

    printf("Percent of runtime covered: %f\n", percentSum);
  }
}

// Super hacky compile-time counter. Thanks, monkyyy!
template counter() {
  template access(uint i) {
    enum access = mixin("__LINE__");
  }
  template get_(uint i, uint sentinel) {
    static if (access!(i) > sentinel) {
      enum get_ = i;
    }
    else {
      enum get_ = get_!(i+1, sentinel);
    }
  }
  template get(uint i) {
    enum setty = mixin("__LINE__");
    alias get = get_!(1, setty);
  }
}

// Crappy hash!
uint hashStuff(uint x, string s1, string s2) {
  uint hash = 5381;

  hash = hash * 33 ^ x;

  foreach (c; s1) {
    hash = hash * 33 ^ c;
  }

  foreach (c; s2) {
    hash = hash * 33 ^ c;
  }

  return hash;
}
