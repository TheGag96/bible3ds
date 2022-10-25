/********************************************************************
 *                                                                  *
 * THIS FILE IS PART OF THE OggVorbis SOFTWARE CODEC SOURCE CODE.   *
 * USE, DISTRIBUTION AND REPRODUCTION OF THIS LIBRARY SOURCE IS     *
 * GOVERNED BY A BSD-STYLE SOURCE LICENSE INCLUDED WITH THIS SOURCE *
 * IN 'COPYING'. PLEASE READ THESE TERMS BEFORE DISTRIBUTING.       *
 *                                                                  *
 * THE OggVorbis SOURCE CODE IS (C) COPYRIGHT 1994-2002             *
 * by the Xiph.Org Foundation http://www.xiph.org/                  *
 *                                                                  *
 ********************************************************************

 function: #ifdef jail to whip a few platforms into the UNIX ideal.
 last mod: $Id$

 ********************************************************************/

module ogg.os_types;

import core.stdc.stdlib;

extern (C): nothrow: @nogc:

/* make it easy on the folks that want to compile the libs with a
   different malloc than stdlib */
alias _ogg_malloc = malloc;
alias _ogg_calloc = calloc;
alias _ogg_realloc = realloc;
alias _ogg_free = free;

/* MSVC 2013 and newer */

/* MSVC/Borland */

/* MacOS X Framework build */

/* Haiku */

/* Be */

/* OS/2 GCC */

/* DJGPP */

/* PS2 EE */

/* Symbian GCC */

/* TI C64x compiler */

/* _OS_TYPES_H */
