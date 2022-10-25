module sdl.rwops;

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

/** @file SDL_rwops.h
 *  This file provides a general interface for SDL to read and write
 *  data sources.  It can easily be extended to files, memory, etc.
 */

//public import sdl.stdinc;
//public import sdl.error;
import core.stdc.stdio;

/** This is the read/write operation structure -- very basic */

struct SDL_RWops {
  /** Seek to 'offset' relative to whence, one of stdio's whence values:
   *  SEEK_SET, SEEK_CUR, SEEK_END
   *  Returns the final offset in the data source.
   */
  int function(SDL_RWops* context, int offset, int whence) seek;

  /** Read up to 'maxnum' objects each of size 'size' from the data
   *  source to the area pointed at by 'ptr'.
   *  Returns the number of objects read, or -1 if the read failed.
   */
  int function(SDL_RWops* context, void* ptr, int size, int maxnum) read;

  /** Write exactly 'num' objects each of size 'objsize' from the area
   *  pointed at by 'ptr' to data source.
   *  Returns 'num', or -1 if the write failed.
   */
  int function(SDL_RWops* context, const(void)* ptr, int size, int num) write;

  /** Close and free an allocated SDL_FSops structure */
  int function(SDL_RWops* context) close;

  uint type;
  union _Anonymous_U {
    struct _Anonymous_0 {
      int autoclose;
      FILE* fp;
    }
    _Anonymous_0 stdio;
    struct _Anonymous_1 {
      ubyte* base;
      ubyte* here;
      ubyte* stop;
    }
    _Anonymous_1 mem;
    struct _Anonymous_2 {
      void* data1;
    } 
    _Anonymous_2 unknown;
  };
  _Anonymous_U hidden;
}


/** @name Functions to create SDL_RWops structures from various data sources */
/*@{*/

SDL_RWops* SDL_RWFromFile(const(char)* file, const(char)* mode);

SDL_RWops* SDL_RWFromFP(FILE* fp, int autoclose);

SDL_RWops* SDL_RWFromMem(void* mem, int size);
SDL_RWops* SDL_RWFromConstMem(const(void)* mem, int size);

SDL_RWops* SDL_AllocRW();
void SDL_FreeRW(SDL_RWops* area);

/*@}*/

/** @name Seek Reference Points */
/*@{*/
enum RW_SEEK_SET = 0; /**< Seek from the beginning of data */
enum RW_SEEK_CUR = 1; /**< Seek relative to current read point */
enum RW_SEEK_END = 2; /**< Seek relative to the end of data */
/*@}*/

/** @name Macros to easily read and write from an SDL_RWops structure */
/*@{*/
auto SDL_RWseek(T0, T1, T2)(T0 ctx, T1 offset, T2 whence)       { (ctx).seek(ctx, offset, whence); }
auto SDL_RWtell(T0)(T0 ctx)                                     { (ctx).seek(ctx, 0, RW_SEEK_CUR); }
auto SDL_RWread(T0, T1, T2, T3)(T0 ctx, T1 ptr, T2 size, T3 n)  { (ctx).read(ctx, ptr, size, n); }
auto SDL_RWwrite(T0, T1, T2, T3)(T0 ctx, T1 ptr, T2 size, G3 n) { (ctx).write(ctx, ptr, size, n); }
auto SDL_RWclose(T0)(T0 ctx)                                    { (ctx).close(ctx); }
/*@}*/

/** @name Read an item of the specified endianness and return in native format */
/*@{*/
ushort SDL_ReadLE16(SDL_RWops* src);
ushort SDL_ReadBE16(SDL_RWops* src);
uint SDL_ReadLE32(SDL_RWops* src);
uint SDL_ReadBE32(SDL_RWops* src);
ulong SDL_ReadLE64(SDL_RWops* src);
ulong SDL_ReadBE64(SDL_RWops* src);
/*@}*/

/** @name Write an item of native format to the specified endianness */
/*@{*/
int SDL_WriteLE16(SDL_RWops* dst, ushort value);
int SDL_WriteBE16(SDL_RWops* dst, ushort value);
int SDL_WriteLE32(SDL_RWops* dst, uint value);
int SDL_WriteBE32(SDL_RWops* dst, uint value);
int SDL_WriteLE64(SDL_RWops* dst, ulong value);
int SDL_WriteBE64(SDL_RWops* dst, ulong value);
/*@}*/
