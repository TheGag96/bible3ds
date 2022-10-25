/********************************************************************
 *                                                                  *
 * THIS FILE IS PART OF THE OggVorbis 'TREMOR' CODEC SOURCE CODE.   *
 *                                                                  *
 * USE, DISTRIBUTION AND REPRODUCTION OF THIS LIBRARY SOURCE IS     *
 * GOVERNED BY A BSD-STYLE SOURCE LICENSE INCLUDED WITH THIS SOURCE *
 * IN 'COPYING'. PLEASE READ THESE TERMS BEFORE DISTRIBUTING.       *
 *                                                                  *
 * THE OggVorbis 'TREMOR' SOURCE CODE IS (C) COPYRIGHT 1994-2002    *
 * BY THE Xiph.Org FOUNDATION http://www.xiph.org/                  *
 *                                                                  *
 ********************************************************************

 function: stdio-based convenience library for opening/seeking/decoding

 ********************************************************************/

module tremor.ivorbisfile;

import core.stdc.config;
import core.stdc.stdio;

import tremor.ivorbiscodec;
import ogg;

extern (C): nothrow: @nogc:

/* __cplusplus */

enum CHUNKSIZE = 65535;
enum READSIZE  = 1024;
/* The function prototypes for the callbacks are basically the same as for
 * the stdio functions fread, fseek, fclose, ftell.
 * The one difference is that the FILE * arguments have been replaced with
 * a void * - this is to be used as a pointer to whatever internal data these
 * functions might need. In the stdio case, it's just a FILE * cast to a void *
 *
 * If you use other functions, check the docs for these functions and return
 * the right values. For seek_func(), you *MUST* return -1 if the stream is
 * unseekable
 */
struct ov_callbacks
{
    size_t function (void* ptr, size_t size, size_t nmemb, void* datasource) read_func;
    int function (void* datasource, ogg_int64_t offset, int whence) seek_func;
    int function (void* datasource) close_func;
    c_long function (void* datasource) tell_func;
}

enum NOTOPEN   = 0;
enum PARTOPEN  = 1;
enum OPENED    = 2;
enum STREAMSET = 3;
enum INITSET   = 4;

struct OggVorbis_File
{
    void* datasource; /* Pointer to a FILE *, etc. */
    int seekable;
    ogg_int64_t offset;
    ogg_int64_t end;
    ogg_sync_state oy;

    /* If the FILE handle isn't seekable (eg, a pipe), only the current
       stream appears */
    int links;
    ogg_int64_t* offsets;
    ogg_int64_t* dataoffsets;
    ogg_uint32_t* serialnos;
    ogg_int64_t* pcmlengths;
    vorbis_info* vi;
    vorbis_comment* vc;

    /* Decoding working state local storage */
    ogg_int64_t pcm_offset;
    int ready_state;
    ogg_uint32_t current_serialno;
    int current_link;

    ogg_int64_t bittrack;
    ogg_int64_t samptrack;

    ogg_stream_state os; /* take physical pages, weld into a logical
       stream of packets */
    vorbis_dsp_state vd; /* central working state for the packet->PCM decoder */
    vorbis_block vb; /* local working space for packet->PCM decode */

    ov_callbacks callbacks;
}

int ov_clear (OggVorbis_File* vf);
int ov_open (FILE* f, OggVorbis_File* vf, const(char)* initial, c_long ibytes);
int ov_open_callbacks (
    void* datasource,
    OggVorbis_File* vf,
    const(char)* initial,
    c_long ibytes,
    ov_callbacks callbacks);

int ov_test (FILE* f, OggVorbis_File* vf, const(char)* initial, c_long ibytes);
int ov_test_callbacks (
    void* datasource,
    OggVorbis_File* vf,
    const(char)* initial,
    c_long ibytes,
    ov_callbacks callbacks);
int ov_test_open (OggVorbis_File* vf);

c_long ov_bitrate (OggVorbis_File* vf, int i);
c_long ov_bitrate_instant (OggVorbis_File* vf);
c_long ov_streams (OggVorbis_File* vf);
c_long ov_seekable (OggVorbis_File* vf);
c_long ov_serialnumber (OggVorbis_File* vf, int i);

ogg_int64_t ov_raw_total (OggVorbis_File* vf, int i);
ogg_int64_t ov_pcm_total (OggVorbis_File* vf, int i);
ogg_int64_t ov_time_total (OggVorbis_File* vf, int i);

int ov_raw_seek (OggVorbis_File* vf, ogg_int64_t pos);
int ov_pcm_seek (OggVorbis_File* vf, ogg_int64_t pos);
int ov_pcm_seek_page (OggVorbis_File* vf, ogg_int64_t pos);
int ov_time_seek (OggVorbis_File* vf, ogg_int64_t pos);
int ov_time_seek_page (OggVorbis_File* vf, ogg_int64_t pos);

ogg_int64_t ov_raw_tell (OggVorbis_File* vf);
ogg_int64_t ov_pcm_tell (OggVorbis_File* vf);
ogg_int64_t ov_time_tell (OggVorbis_File* vf);

vorbis_info* ov_info (OggVorbis_File* vf, int link);
vorbis_comment* ov_comment (OggVorbis_File* vf, int link);

c_long ov_read (OggVorbis_File* vf, ubyte* buffer, int length, int* bitstream);

/* __cplusplus */

