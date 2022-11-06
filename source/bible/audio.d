module bible.audio;

import ctru.allocator, ctru.ndsp, ctru.services.dsp, ctru.synchronization, ctru.svc, ctru.thread;
import bible.util;

import core.stdc.stdlib;
import core.atomic, core.volatile;

nothrow: @nogc:

enum THREADED_MUSIC = false;  //keeping the threaded code in just in case it turns out to be the better option...

enum SAMPLERATE          = 32768;  //this is actually the native sample rate of the 3DS (unfortunately)
enum SAMPLESPERBUF       = SAMPLERATE * (THREADED_MUSIC ? 10 : 17) / 1000;
enum CHANNELS_PER_SAMPLE = 2;
enum BYTESPERSAMPLE      = CHANNELS_PER_SAMPLE * 2;
enum WAVEBUF_SIZE        = SAMPLESPERBUF * BYTESPERSAMPLE;

enum THREAD_AFFINITY = -1;           //execute thread on any core
enum THREAD_STACK_SZ = 200 * 1024;   //stack for audio thread

enum MUSIC_CHANNEL     = 0;
enum FIRST_SFX_CHANNEL = MUSIC_CHANNEL + 1;
enum MAX_CHANNELS      = 24;


struct SeData {
  ndspWaveBuf[SoundEffect.max + 1] waveBufs;
  byte[SoundEffect.max + 1]        channelSoundsPlaying;
}
__gshared SeData gSeData;

struct MusicData {
  ndspWaveBuf[3] waveBufs;
  short[]        playBuf;
  WAVE_32BS[]    renderBuf;
  bool           loaded;
  bool           playing;
  float          currentVol = 1, targetVol = 1, volRate;  //TODO: find better place

  static if (THREADED_MUSIC) {
    align(4) shared bool         threadQuit;
    align(4) shared MusicCommand command;

    align(4) shared Music        currentMusic;

    Thread     threadId;
    LightEvent musicEvent;
  }
  else {
    MusicCommand command;

    Music currentMusic;
  }
}
__gshared MusicData gMusicData;

alias DEV_SMPL = int;
struct WAVE_32BS {
  DEV_SMPL L;
  DEV_SMPL R;
}

enum Music : ubyte {
  none = 0,
}

struct MusicInfo {
  string path;
}

enum MusicAction : ubyte {
  none = 0,
  load_and_play,
  //fade_in,
  //fade_out,
  pause,
  resume,
  //stop,
  //quit,
}

struct MusicCommand {
  MusicAction action;
  Music       music;
}

enum SoundEffect : ubyte {
  none = 0,
  scroll_tick,
  scroll_stop,
}

enum SoundType : ubyte {
  normal,
  looping
}

struct SoundInfo {
  string path;
  SoundType soundType;
}

enum musicPath(Music music)  = "romfs:/sound/music/" ~ __traits(allMembers, Music)[music]    ~ ".vgz";
enum sfxPath(SoundEffect se) = "romfs:/sound/sfx/"   ~ __traits(allMembers, SoundEffect)[se] ~ ".raw";

static immutable MusicInfo[Music.max + 1] MUSIC_INFO_TABLE = [
  Music.none                : { path : ""                                    },
];

static immutable SoundInfo[SoundEffect.max + 1] SOUND_INFO_TABLE = [
  SoundEffect.none                   : { path : "",                                           soundType : SoundType.normal },
  SoundEffect.scroll_tick            : { path : "romfs:/sound/sfx/scroll_tick.raw",           soundType : SoundType.normal },
  SoundEffect.scroll_stop            : { path : "romfs:/sound/sfx/scroll_stop.raw",           soundType : SoundType.normal },
];

///sounds loaded all the time
static immutable SoundEffect[] GLOBAL_SOUNDS = [
  SoundEffect.scroll_tick,
  SoundEffect.scroll_stop,
];


void audioInit() {
  ndspInit();

  foreach (se; GLOBAL_SOUNDS) {
    audioLoadSoundEffect(se);
  }

  gMusicData.playBuf   = allocArray!(short, false, linearAlloc)(SAMPLESPERBUF * CHANNELS_PER_SAMPLE * gMusicData.waveBufs.length);
  gMusicData.renderBuf = allocArray!(WAVE_32BS, false, malloc)(SAMPLESPERBUF);

  // Setup waveBufs for NDSP
  foreach (i, ref buf; gMusicData.waveBufs[]) {
    buf.data_vaddr = gMusicData.playBuf.ptr + i * SAMPLESPERBUF * CHANNELS_PER_SAMPLE;
    buf.status     = NDSP_WBUF_DONE;
  }

  // TODO: music system

  static if (THREADED_MUSIC) {
    LightEvent_Init(&gMusicData.musicEvent, ResetType.oneshot);

    ndspSetCallback(&audioCallback, null);

    int priority = 0x30;
    svcGetThreadPriority(&priority, CUR_THREAD_HANDLE);
    // ... then subtract 1, as lower number => higher actual priority ...
    priority -= 1;
    // ... finally, clamp it between 0x18 and 0x3F to guarantee that it's valid.
    priority = priority < 0x18 ? 0x18 : priority;
    priority = priority > 0x3F ? 0x3F : priority;

    // Start the thread, passing our opusFile as an argument.
    gMusicData.threadId = threadCreate(&audioThread, null,
                                       THREAD_STACK_SZ, priority,
                                       THREAD_AFFINITY, false);
  }
}

void audioFini() {
  static if (THREADED_MUSIC) {
    atomicStore(gMusicData.threadQuit, true);
    LightEvent_Signal(&gMusicData.musicEvent);

    threadJoin(gMusicData.threadId, ulong.max);
    threadFree(gMusicData.threadId);
  }

  ndspExit();
}

void audioLoadSoundEffect(SoundEffect se) {
  auto buf    = &gSeData.waveBufs[se];
  auto seInfo = &SOUND_INFO_TABLE[se];

  if (buf.data_vaddr) return;

  auto soundData = readFile!linearAlloc(seInfo.path);

  buf.data_vaddr = cast(uint*) soundData.ptr;
  buf.nsamples   = soundData.length / BYTESPERSAMPLE;
  buf.looping    = seInfo.soundType == SoundType.looping;

  DSP_FlushDataCache(buf.data_pcm16, soundData.length);
}

void audioPlaySound(SoundEffect se, float volume = 1) {
  byte channelToUse = audioPlaySoundCommon(se);
  if (!channelToUse) return;

  float[12] mix;
  mix[0]    = volume;
  mix[1]    = volume;
  mix[2..$] = 0;

  ndspChnSetMix(channelToUse, mix);
  ndspChnWaveBufAdd(channelToUse, &gSeData.waveBufs[se]);
}

byte audioPlaySoundCommon(SoundEffect se) {
  if (!gSeData.waveBufs[se].data_vaddr) return 0;

  byte channelToUse = gSeData.channelSoundsPlaying[se];

  if (channelToUse == 0) {
    foreach (byte i; FIRST_SFX_CHANNEL..MAX_CHANNELS) {
      if (!ndspChnIsPlaying(i)) {
        channelToUse = i;
        break;
      }
    }
    if (!channelToUse) return 0;
  }
  else {
    ndspChnReset(channelToUse);
  }

  gSeData.channelSoundsPlaying[se] = channelToUse;

  ndspChnSetInterp(channelToUse, NDSPInterpType.polyphase);
  ndspChnSetRate(channelToUse, SAMPLERATE);
  ndspChnSetFormat(channelToUse, NDSP_FORMAT_MONO_PCM16);

  return channelToUse;
}

void audioStopSound(SoundEffect se) {
  byte channel = gSeData.channelSoundsPlaying[se];
  if (!channel) return;

  ndspChnReset(channel);
}

void audioPlayMusic(Music music) {
  if (music == gMusicData.currentMusic) {
    audioSetFade(1, 0.25);
  }
  else {
    atomicStore(gMusicData.command, MusicCommand(MusicAction.load_and_play, music));
  }
}

void audioSetFade(float targetVol, float secsToFade) {
  gMusicData.targetVol = targetVol;
  gMusicData.volRate   = 1.0f / FRAMERATE / secsToFade;  //TODO: need some kind of DSP rate for threaded mode
}

void audioUpdate() {
  ////
  // Update table of sounds playing
  ////

  foreach (se; 0..SoundEffect.max + 1) {
    auto channel = gSeData.channelSoundsPlaying[se];
    if (!channel) continue;

    if (gSeData.waveBufs[se].status == NDSP_WBUF_DONE) {
      gSeData.channelSoundsPlaying[se] = 0;
    }
  }

  ////
  // Update music
  ////

  static if (!THREADED_MUSIC) {
    //audioUpdateMusic(); //TODO
  }
}

bool fillMusicBuffer(ref ndspWaveBuf waveBuf) {
  const int samplesRendered = 0; // TODO

  int*   inPointer  = cast(int*) gMusicData.renderBuf.ptr;
  short* outPointer = waveBuf.data_pcm16;

  foreach (i; 0..SAMPLESPERBUF*2) {
    //shift 24-bit audio into 16-bit audio
    outPointer[i] = cast(short) (inPointer[i] >> 8);
  }

  waveBuf.nsamples = samplesRendered;

  ndspChnWaveBufAdd(MUSIC_CHANNEL, &waveBuf);
  DSP_FlushDataCache(waveBuf.data_pcm16, samplesRendered * BYTESPERSAMPLE);

  return true;
}

void audioUpdateMusic() {
  //read and consume command
  MusicCommand currentCommand = atomicExchange(&gMusicData.command, MusicCommand.init);

  final switch (currentCommand.action) {
    case MusicAction.none: break;

    case MusicAction.load_and_play:
      ubyte loadFailure = 0; // TODO
      assert(!loadFailure, "Music file load failed");

      gMusicData.loaded       = true;
      gMusicData.playing      = true;
      gMusicData.currentMusic = currentCommand.music;

      ndspChnReset(MUSIC_CHANNEL);
      ndspSetOutputMode(NDSPOutputMode.stereo);
      ndspChnSetInterp(MUSIC_CHANNEL, NDSPInterpType.polyphase);
      ndspChnSetRate(MUSIC_CHANNEL, SAMPLERATE);
      ndspChnSetFormat(MUSIC_CHANNEL, NDSP_FORMAT_STEREO_PCM16);

      gMusicData.currentVol = 1;
      gMusicData.targetVol  = gMusicData.currentVol;
      float[12] mix;
      mix[0..2] = gMusicData.currentVol;
      mix[2..$] = 0;
      ndspChnSetMix(MUSIC_CHANNEL, mix);

      ndspChnSetPaused(MUSIC_CHANNEL, false);

      foreach (i, ref buf; gMusicData.waveBufs[]) {
        buf.status = NDSP_WBUF_DONE;
        fillMusicBuffer(buf);
      }

      break;

    case MusicAction.pause:
      gMusicData.playing = false;
      ndspChnSetPaused(MUSIC_CHANNEL, true);
      break;

    case MusicAction.resume:
      gMusicData.playing = gMusicData.loaded;
      ndspChnSetPaused(MUSIC_CHANNEL, false);
      break;
  }

  if (gMusicData.playing) {
    foreach (i, ref buf; gMusicData.waveBufs[]) {
      if (buf.status != NDSP_WBUF_DONE) continue;
      fillMusicBuffer(buf);
      break;  //only do one buffer per frame
    }

    ////
    // Handle fading
    ////

    if (gMusicData.currentVol != gMusicData.targetVol) {
      gMusicData.currentVol = gMusicData.currentVol.approach(gMusicData.targetVol, gMusicData.volRate);

      float[12] mix;
      mix[0..2] = gMusicData.currentVol;
      mix[2..$] = 0;
      ndspChnSetMix(MUSIC_CHANNEL, mix);
    }
  }
}

static if (THREADED_MUSIC) {
  extern(C)
  void audioCallback(const(void*) data) {
    if (atomicLoad(gMusicData.threadQuit)) {
      return;
    }

    LightEvent_Signal(&gMusicData.musicEvent);
  }

  extern(C)
  void audioThread(const(void*) data) {
    bool playing = false;
    bool loaded  = false;

    while (!atomicLoad(gMusicData.threadQuit)) {
      audioUpdateMusic();

      //Wait for a signal that we're needed again before continuing,
      //so that we can yield to other things that want to run
      //(Note that the 3DS uses cooperative threading)
      LightEvent_Wait(&gMusicData.musicEvent);
    }
  }
}

