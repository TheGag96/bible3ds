module sdl.audio;

extern(C):
@nogc: nothrow:

/*
    SDL - Simple DirectMedia Layer
    Copyright (C) 1997-2012 Sam Lantinga

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

    Sam Lantinga
    slouken@libsdl.org
*/

/**
 *  @file SDL_audio.h
 *  Access to the raw audio mixing buffer for the SDL library
 */

//public import sdl.stdinc;
//public import sdl.error;
//public import sdl.endian;
//public import sdl.mutex;
//public import sdl.thread;
public import sdl.rwops;

//#include "begin_code.h"
/* Set up for C function definitions, even when using C++ */

/**
 * When filling in the desired audio spec structure,
 * - 'desired->freq' should be the desired audio frequency in samples-per-second.
 * - 'desired->format' should be the desired audio format.
 * - 'desired->samples' is the desired size of the audio buffer, in samples.
 *     This number should be a power of two, and may be adjusted by the audio
 *     driver to a value more suitable for the hardware.  Good values seem to
 *     range between 512 and 8096 inclusive, depending on the application and
 *     CPU speed.  Smaller values yield faster response time, but can lead
 *     to underflow if the application is doing heavy processing and cannot
 *     fill the audio buffer in time.  A stereo sample consists of both right
 *     and left channels in LR ordering.
 *     Note that the number of samples is directly related to time by the
 *     following formula:  ms = (samples*1000)/freq
 * - 'desired->size' is the size in bytes of the audio buffer, and is
 *     calculated by SDL_OpenAudio().
 * - 'desired->silence' is the value used to set the buffer to silence,
 *     and is calculated by SDL_OpenAudio().
 * - 'desired->callback' should be set to a function that will be called
 *     when the audio device is ready for more data.  It is passed a pointer
 *     to the audio buffer, and the length in bytes of the audio buffer.
 *     This function usually runs in a separate thread, and so you should
 *     protect data structures that it accesses by calling SDL_LockAudio()
 *     and SDL_UnlockAudio() in your code.
 * - 'desired->userdata' is passed as the first parameter to your callback
 *     function.
 *
 * @note The calculated values in this structure are calculated by SDL_OpenAudio()
 *
 */
struct SDL_AudioSpec {
  int freq;   /**< DSP frequency -- samples per second */
  ushort format;    /**< Audio data format */
  ubyte  channels;  /**< Number of channels: 1 mono, 2 stereo */
  ubyte  silence;   /**< Audio buffer silence value (calculated) */
  ushort samples;   /**< Audio buffer size in samples (power of 2) */
  ushort padding;   /**< Necessary for some compile environments */
  uint size;    /**< Audio buffer size in bytes (calculated) */
  /**
   *  This function is called when the audio device needs more data.
   *
   *  @param[out] stream  A pointer to the audio data buffer
   *  @param[in]  len The length of the audio buffer in bytes.
   *
   *  Once the callback returns, the buffer will no longer be valid.
   *  Stereo samples are stored in a LRLRLR ordering.
   */
  void function(void* userdata, ubyte* stream, int len) callback;
  void  *userdata;
} 

/**
 *  @name Audio format flags
 *  defaults to LSB byte order
 */
/*@{*/
enum AUDIO_U8 =  0x0008;  /**< Unsigned 8-bit samples */
enum AUDIO_S8 =  0x8008;  /**< Signed 8-bit samples */
enum AUDIO_U16LSB =  0x0010;  /**< Unsigned 16-bit samples */
enum AUDIO_S16LSB =  0x8010;  /**< Signed 16-bit samples */
enum AUDIO_U16MSB =  0x1010;  /**< As above, but big-endian byte order */
enum AUDIO_S16MSB =  0x9010;  /**< As above, but big-endian byte order */
enum AUDIO_U16 = AUDIO_U16LSB;
enum AUDIO_S16 = AUDIO_S16LSB;

/**
 *  @name Native audio byte ordering
 */
/*@{*/
version (LittleEndian) {
  enum AUDIO_U16SYS =  AUDIO_U16LSB;
  enum AUDIO_S16SYS =  AUDIO_S16LSB;
}
else {
  enum AUDIO_U16SYS =  AUDIO_U16MSB;
  enum AUDIO_S16SYS =  AUDIO_S16MSB;
}
/*@}*/

/*@}*/


/** A structure to hold a set of audio conversion filters and buffers */
struct SDL_AudioCVT {
  int needed;     /**< Set to 1 if conversion possible */
  ushort src_format;    /**< Source audio format */
  ushort dst_format;    /**< Target audio format */
  double rate_incr;   /**< Rate conversion increment */
  ubyte* buf;     /**< Buffer to hold entire audio data */
  int    len;     /**< Length of original audio buffer */
  int    len_cvt;     /**< Length of converted audio buffer */
  int    len_mult;    /**< buffer must be len*len_mult big */
  double len_ratio;   /**< Given len, final size is len*len_ratio */
  void function(SDL_AudioCVT* cvt, ushort format)[10] filters;
  int filter_index;   /**< Current audio conversion function */
} 


/* Function prototypes */

/**
 * @name Audio Init and Quit
 * These functions are used internally, and should not be used unless you
 * have a specific need to specify the audio driver you want to use.
 * You should normally use SDL_Init() or SDL_InitSubSystem().
 */
/*@{*/
int SDL_AudioInit(const(char)* driver_name);
void SDL_AudioQuit();
/*@}*/

/**
 * This function fills the given character buffer with the name of the
 * current audio driver, and returns a pointer to it if the audio driver has
 * been initialized.  It returns NULL if no driver has been initialized.
 */
char* SDL_AudioDriverName(char* namebuf, int maxlen);

/**
 * This function opens the audio device with the desired parameters, and
 * returns 0 if successful, placing the actual hardware parameters in the
 * structure pointed to by 'obtained'.  If 'obtained' is NULL, the audio
 * data passed to the callback function will be guaranteed to be in the
 * requested format, and will be automatically converted to the hardware
 * audio format if necessary.  This function returns -1 if it failed 
 * to open the audio device, or couldn't set up the audio thread.
 *
 * The audio device starts out playing silence when it's opened, and should
 * be enabled for playing by calling SDL_PauseAudio(0) when you are ready
 * for your audio callback function to be called.  Since the audio driver
 * may modify the requested size of the audio buffer, you should allocate
 * any local mixing buffers after you open the audio device.
 *
 * @sa SDL_AudioSpec
 */
int SDL_OpenAudio(SDL_AudioSpec* desired, SDL_AudioSpec* obtained);

enum SDL_audiostatus {
  SDL_AUDIO_STOPPED = 0,
  SDL_AUDIO_PLAYING,
  SDL_AUDIO_PAUSED
}
enum SDL_AUDIO_STOPPED = SDL_audiostatus.SDL_AUDIO_STOPPED;
enum SDL_AUDIO_PLAYING = SDL_audiostatus.SDL_AUDIO_PLAYING;
enum SDL_AUDIO_PAUSED  = SDL_audiostatus.SDL_AUDIO_PAUSED;

/** Get the current audio state */
SDL_audiostatus SDL_GetAudioStatus();

/**
 * This function pauses and unpauses the audio callback processing.
 * It should be called with a parameter of 0 after opening the audio
 * device to start playing sound.  This is so you can safely initialize
 * data for your callback function after opening the audio device.
 * Silence will be written to the audio device during the pause.
 */
void SDL_PauseAudio(int pause_on);

/**
 * This function loads a WAVE from the data source, automatically freeing
 * that source if 'freesrc' is non-zero.  For example, to load a WAVE file,
 * you could do:
 *  @code SDL_LoadWAV_RW(SDL_RWFromFile("sample.wav", "rb"), 1, ...); @endcode
 *
 * If this function succeeds, it returns the given SDL_AudioSpec,
 * filled with the audio data format of the wave data, and sets
 * 'audio_buf' to a malloc()'d buffer containing the audio data,
 * and sets 'audio_len' to the length of that audio buffer, in bytes.
 * You need to free the audio buffer with SDL_FreeWAV() when you are 
 * done with it.
 *
 * This function returns NULL and sets the SDL error message if the 
 * wave file cannot be opened, uses an unknown data format, or is 
 * corrupt.  Currently raw and MS-ADPCM WAVE files are supported.
 */
SDL_AudioSpec* SDL_LoadWAV_RW(SDL_RWops* src, int freesrc, SDL_AudioSpec* spec, ubyte** audio_buf, uint* audio_len);

/** Compatibility convenience function -- loads a WAV from a file */
SDL_AudioSpec* SDL_LoadWAV(char* file, SDL_AudioSpec* spec, ubyte** audio_buf, uint* audio_len) {
  return SDL_LoadWAV_RW(SDL_RWFromFile(file, "rb"),1, spec,audio_buf,audio_len);
}

/**
 * This function frees data previously allocated with SDL_LoadWAV_RW()
 */
void SDL_FreeWAV(ubyte* audio_buf);

/**
 * This function takes a source format and rate and a destination format
 * and rate, and initializes the 'cvt' structure with information needed
 * by SDL_ConvertAudio() to convert a buffer of audio data from one format
 * to the other.
 *
 * @return This function returns 0, or -1 if there was an error.
 */
int SDL_BuildAudioCVT(SDL_AudioCVT* cvt,
    ushort src_format, ubyte src_channels, int src_rate,
    ushort dst_format, ubyte dst_channels, int dst_rate);

/**
 * Once you have initialized the 'cvt' structure using SDL_BuildAudioCVT(),
 * created an audio buffer cvt->buf, and filled it with cvt->len bytes of
 * audio data in the source format, this function will convert it in-place
 * to the desired format.
 * The data conversion may expand the size of the audio data, so the buffer
 * cvt->buf should be allocated after the cvt structure is initialized by
 * SDL_BuildAudioCVT(), and should be cvt->len*cvt->len_mult bytes long.
 */
int SDL_ConvertAudio(SDL_AudioCVT* cvt);


enum SDL_MIX_MAXVOLUME = 128;
/**
 * This takes two audio buffers of the playing audio format and mixes
 * them, performing addition, volume adjustment, and overflow clipping.
 * The volume ranges from 0 - 128, and should be set to SDL_MIX_MAXVOLUME
 * for full audio volume.  Note this does not change hardware volume.
 * This is provided for convenience -- you can mix your own audio data.
 */
void SDL_MixAudio(ubyte* dst, const ubyte* src, uint len, int volume);

/**
 * @name Audio Locks
 * The lock manipulated by these functions protects the callback function.
 * During a LockAudio/UnlockAudio pair, you can be guaranteed that the
 * callback function is not running.  Do not call these from the callback
 * function or you will cause deadlock.
 */
/*@{*/
void SDL_LockAudio();
void SDL_UnlockAudio();
/*@}*/

/**
 * This function shuts down audio processing and closes the audio device.
 */
void SDL_CloseAudio();


