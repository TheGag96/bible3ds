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
  gProfilingStartTime = readTimestamp();

  gTimerInfo[] = TimerData.init;
}

// In order to force a unique template instantiation per use, try to combine line number, filename, and function name
// in a pretty goofy way.
struct TimeBlock {
  @nogc: nothrow:

  size_t parentIndex;
  TimerData* timerData;
  ulong oldElapsedInclusive;
  ulong start;

  @disable this();

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

void endProfileAndLog() {
  auto profilingEndTime = readTimestamp();
  auto totalTime         = profilingEndTime - gProfilingStartTime;

  //enum size_t cpuFreq = 268111856; // from https://3dbrew.org/wiki/Hardware
  enum ulong TIMER_FREQ = SYSCLOCK_ARM11; // @TODO: Check

  printf("Timing info (CPU freq = %llu Hz):\n", TIMER_FREQ);
  printf("Total time: %f ms (%llu cycles)\n", 1000.0*totalTime/TIMER_FREQ, totalTime);

  double percentSum = 0;
  foreach (ref it; gTimerInfo) {
    if (!it.name.length)  continue;
    auto percent      = (cast(double)it.elapsedExclusive)/totalTime * 100;

    if (it.elapsedExclusive != it.elapsedInclusive) {
      auto percentWithChildren = (cast(double)it.elapsedInclusive)/totalTime * 100;
      printf("  %s[%lu]: %llu (%f%%, %f%% w/ children)\n", it.name.ptr, it.hitCount, it.elapsedExclusive, percent, percentWithChildren);
    }
    else {
      printf("  %s[%lu]: %llu (%f%%)\n", it.name.ptr, it.hitCount, it.elapsedExclusive, percent);
    }

    percentSum += percent;
  }

  printf("Percent of runtime covered: %f\n", percentSum);
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
