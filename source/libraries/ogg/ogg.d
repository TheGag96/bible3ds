/********************************************************************
 *                                                                  *
 * THIS FILE IS PART OF THE OggVorbis SOFTWARE CODEC SOURCE CODE.   *
 * USE, DISTRIBUTION AND REPRODUCTION OF THIS LIBRARY SOURCE IS     *
 * GOVERNED BY A BSD-STYLE SOURCE LICENSE INCLUDED WITH THIS SOURCE *
 * IN 'COPYING'. PLEASE READ THESE TERMS BEFORE DISTRIBUTING.       *
 *                                                                  *
 * THE OggVorbis SOURCE CODE IS (C) COPYRIGHT 1994-2007             *
 * by the Xiph.Org Foundation http://www.xiph.org/                  *
 *                                                                  *
 ********************************************************************

 function: toplevel libogg include
 last mod: $Id$

 ********************************************************************/

module ogg.ogg;

import core.stdc.config;
import ogg.config_types;

extern (C): nothrow: @nogc:

struct ogg_iovec_t
{
    void* iov_base;
    size_t iov_len;
}

struct oggpack_buffer
{
    c_long endbyte;
    int endbit;

    ubyte* buffer;
    ubyte* ptr;
    c_long storage;
}

/* ogg_page is used to encapsulate the data in one Ogg bitstream page *****/

struct ogg_page
{
    ubyte* header;
    c_long header_len;
    ubyte* body_;
    c_long body_len;
}

/* ogg_stream_state contains the current encode/decode state of a logical
   Ogg bitstream **********************************************************/

struct ogg_stream_state
{
    ubyte* body_data; /* bytes from packet bodies */
    c_long body_storage; /* storage elements allocated */
    c_long body_fill; /* elements stored; fill mark */
    c_long body_returned; /* elements of fill returned */

    int* lacing_vals; /* The values that will go to the segment table */
    ogg_int64_t* granule_vals; /* granulepos values for headers. Not compact
       this way, but it is simple coupled to the
       lacing fifo */
    c_long lacing_storage;
    c_long lacing_fill;
    c_long lacing_packet;
    c_long lacing_returned;

    ubyte[282] header; /* working space for header encode */
    int header_fill;

    int e_o_s; /* set when we have buffered the last packet in the
       logical bitstream */
    int b_o_s; /* set after we've written the initial page
       of a logical bitstream */
    c_long serialno;
    c_long pageno;
    ogg_int64_t packetno; /* sequence number for decode; the framing
       knows where there's a hole in the data,
       but we need coupling so that the codec
       (which is in a separate abstraction
       layer) also knows about the gap */
    ogg_int64_t granulepos;
}

/* ogg_packet is used to encapsulate the data and metadata belonging
   to a single raw Ogg/Vorbis packet *************************************/

struct ogg_packet
{
    ubyte* packet;
    c_long bytes;
    c_long b_o_s;
    c_long e_o_s;

    ogg_int64_t granulepos;

    ogg_int64_t packetno; /* sequence number for decode; the framing
       knows where there's a hole in the data,
       but we need coupling so that the codec
       (which is in a separate abstraction
       layer) also knows about the gap */
}

struct ogg_sync_state
{
    ubyte* data;
    int storage;
    int fill;
    int returned;

    int unsynced;
    int headerbytes;
    int bodybytes;
}

/* Ogg BITSTREAM PRIMITIVES: bitstream ************************/

void oggpack_writeinit (oggpack_buffer* b);
int oggpack_writecheck (oggpack_buffer* b);
void oggpack_writetrunc (oggpack_buffer* b, c_long bits);
void oggpack_writealign (oggpack_buffer* b);
void oggpack_writecopy (oggpack_buffer* b, void* source, c_long bits);
void oggpack_reset (oggpack_buffer* b);
void oggpack_writeclear (oggpack_buffer* b);
void oggpack_readinit (oggpack_buffer* b, ubyte* buf, int bytes);
void oggpack_write (oggpack_buffer* b, c_ulong value, int bits);
c_long oggpack_look (oggpack_buffer* b, int bits);
c_long oggpack_look1 (oggpack_buffer* b);
void oggpack_adv (oggpack_buffer* b, int bits);
void oggpack_adv1 (oggpack_buffer* b);
c_long oggpack_read (oggpack_buffer* b, int bits);
c_long oggpack_read1 (oggpack_buffer* b);
c_long oggpack_bytes (oggpack_buffer* b);
c_long oggpack_bits (oggpack_buffer* b);
ubyte* oggpack_get_buffer (oggpack_buffer* b);

void oggpackB_writeinit (oggpack_buffer* b);
int oggpackB_writecheck (oggpack_buffer* b);
void oggpackB_writetrunc (oggpack_buffer* b, c_long bits);
void oggpackB_writealign (oggpack_buffer* b);
void oggpackB_writecopy (oggpack_buffer* b, void* source, c_long bits);
void oggpackB_reset (oggpack_buffer* b);
void oggpackB_writeclear (oggpack_buffer* b);
void oggpackB_readinit (oggpack_buffer* b, ubyte* buf, int bytes);
void oggpackB_write (oggpack_buffer* b, c_ulong value, int bits);
c_long oggpackB_look (oggpack_buffer* b, int bits);
c_long oggpackB_look1 (oggpack_buffer* b);
void oggpackB_adv (oggpack_buffer* b, int bits);
void oggpackB_adv1 (oggpack_buffer* b);
c_long oggpackB_read (oggpack_buffer* b, int bits);
c_long oggpackB_read1 (oggpack_buffer* b);
c_long oggpackB_bytes (oggpack_buffer* b);
c_long oggpackB_bits (oggpack_buffer* b);
ubyte* oggpackB_get_buffer (oggpack_buffer* b);

/* Ogg BITSTREAM PRIMITIVES: encoding **************************/

int ogg_stream_packetin (ogg_stream_state* os, ogg_packet* op);
int ogg_stream_iovecin (
    ogg_stream_state* os,
    ogg_iovec_t* iov,
    int count,
    c_long e_o_s,
    ogg_int64_t granulepos);
int ogg_stream_pageout (ogg_stream_state* os, ogg_page* og);
int ogg_stream_pageout_fill (ogg_stream_state* os, ogg_page* og, int nfill);
int ogg_stream_flush (ogg_stream_state* os, ogg_page* og);
int ogg_stream_flush_fill (ogg_stream_state* os, ogg_page* og, int nfill);

/* Ogg BITSTREAM PRIMITIVES: decoding **************************/

int ogg_sync_init (ogg_sync_state* oy);
int ogg_sync_clear (ogg_sync_state* oy);
int ogg_sync_reset (ogg_sync_state* oy);
int ogg_sync_destroy (ogg_sync_state* oy);
int ogg_sync_check (ogg_sync_state* oy);

char* ogg_sync_buffer (ogg_sync_state* oy, c_long size);
int ogg_sync_wrote (ogg_sync_state* oy, c_long bytes);
c_long ogg_sync_pageseek (ogg_sync_state* oy, ogg_page* og);
int ogg_sync_pageout (ogg_sync_state* oy, ogg_page* og);
int ogg_stream_pagein (ogg_stream_state* os, ogg_page* og);
int ogg_stream_packetout (ogg_stream_state* os, ogg_packet* op);
int ogg_stream_packetpeek (ogg_stream_state* os, ogg_packet* op);

/* Ogg BITSTREAM PRIMITIVES: general ***************************/

int ogg_stream_init (ogg_stream_state* os, int serialno);
int ogg_stream_clear (ogg_stream_state* os);
int ogg_stream_reset (ogg_stream_state* os);
int ogg_stream_reset_serialno (ogg_stream_state* os, int serialno);
int ogg_stream_destroy (ogg_stream_state* os);
int ogg_stream_check (ogg_stream_state* os);
int ogg_stream_eos (ogg_stream_state* os);

void ogg_page_checksum_set (ogg_page* og);

int ogg_page_version (const(ogg_page)* og);
int ogg_page_continued (const(ogg_page)* og);
int ogg_page_bos (const(ogg_page)* og);
int ogg_page_eos (const(ogg_page)* og);
ogg_int64_t ogg_page_granulepos (const(ogg_page)* og);
int ogg_page_serialno (const(ogg_page)* og);
c_long ogg_page_pageno (const(ogg_page)* og);
int ogg_page_packets (const(ogg_page)* og);

void ogg_packet_clear (ogg_packet* op);

/* _OGG_H */
