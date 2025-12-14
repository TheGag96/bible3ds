/**
 * @file font.h
 * @brief Font loading and management
 */

module citro2d.font;

import citro2d.base;
import ctru.allocator;
import ctru.font;
import ctru.gpu.enums;
import ctru.result;
import ctru.romfs;
import ctru.services.fs;
import ctru.types;
import ctru.services.cfgu;
import ctru.util.decompress;
import citro3d.texture;

import core.stdc.stdio;
import core.stdc.stdlib;
import core.stdc.string;
//import core.stdc.unistd;
import citro2d.internal;

extern (C): nothrow: @nogc:

struct C2D_Font_s
{
  CFNT_s* cfnt;
  C3D_Tex* glyphSheets;
  float textScale = 0;
  fontGlyphPos_s[128] asciiCache;
};
alias C2D_Font = C2D_Font_s*;

/** @defgroup Font Font functions
 * @{
 */

/** @brief Load a font from a file
 * @param[in] filename Name of the font file (.bcfnt)
 * @returns Font handle
 * @retval null Error
 */
C2D_Font C2D_FontLoad(const(char)* filename)
{
  FILE* f = fopen(filename, "rb");
  if (!f) return null;
  C2D_Font ret = C2D_FontLoadFromHandle(f);
  fclose(f);
  return ret;
}

/** @brief Load a font from memory
 * @param[in] data Data to load
 * @param[in] size Size of the data to load
 * @returns Font handle
 * @retval null Error
 */
C2D_Font C2D_FontLoadFromMem(const(void)* data, size_t size)
{
  C2D_Font font = C2Di_FontAlloc();
  if (font)
  {
    font.cfnt = cast(CFNT_s*) linearAlloc(size);
    if (font.cfnt)
      memcpy(font.cfnt, data, size);
    font = C2Di_PostLoadFont(font);
  }
  return font;
}

/** @brief Load a font from file descriptor
 * @param[in] fd File descriptor used to load data
 * @returns Font handle
 * @retval null Error
 */
C2D_Font C2D_FontLoadFromFD(int fd)
{
  C2D_Font font = C2Di_FontAlloc();
  if (font)
  {
    CFNT_s cfnt;
    read(fd, &cfnt, CFNT_s.sizeof);
    font.cfnt = cast(CFNT_s*) linearAlloc(cfnt.fileSize);
    if (font.cfnt)
    {
      memcpy(font.cfnt, &cfnt, CFNT_s.sizeof);
      read(fd, cast(ubyte*)(font.cfnt) + CFNT_s.sizeof, cfnt.fileSize - CFNT_s.sizeof);
    }
    font = C2Di_PostLoadFont(font);
  }
  return font;
}

/** @brief Load font from stdio file handle
 *  @param[in] f File handle used to load data
 *  @returns Font handle
 *  @retval null Error
 */
// import core.stdc.stdio;
// C2D_Font C2D_FontLoadFromHandle(FILE* f);

/** @brief Load corresponding font from system archive
 *  @param[in] region Region to get font from
 *  @returns Font handle
 *  @retval null Error
 *  @remark JPN, USA, EUR, and AUS all use the same font.
 */
C2D_Font C2D_FontLoadSystem(CFGRegion region)
{
  uint fontIdx = C2Di_RegionToFontIndex(region);

  ubyte systemRegion = 0;
  Result rc = CFGU_SecureInfoGetRegion(&systemRegion);
  if (R_FAILED(rc) || fontIdx == C2Di_RegionToFontIndex(cast(CFGRegion)systemRegion))
  {
    fontEnsureMapped();
    return null;
  }

  // Load the font
  return C2Di_FontLoadFromArchive(0x0004009b00014002UL | (fontIdx<<8), C2Di_FontPaths[fontIdx]);
}

/** @brief Free a font
 * @param[in] font Font handle
 */
void C2D_FontFree(C2D_Font font)
{
  if (font)
  {
    if (font.cfnt)
      linearFree(font.cfnt);
    free(font.glyphSheets);
  }
}

/** @brief Find the glyph index of a codepoint, or returns the default
 * @param[in] font Font to search, or null for system font
 * @param[in] codepoint Codepoint to search for
 * @returns Glyph index
 * @retval font.cfnt.finf.alterCharIndex The codepoint does not exist in the font
 */
int C2D_FontGlyphIndexFromCodePoint(C2D_Font font, uint codepoint)
{
  if (!font)
    return fontGlyphIndexFromCodePoint(fontGetSystemFont(), codepoint);
  else
    return fontGlyphIndexFromCodePoint(font.cfnt, codepoint);
}

/** @brief Get character width info for a given index
 * @param[in] font Font to read from, or null for system font
 * @param[in] glyphIndex Index to get the width of
 * @returns Width info for glyph
 */
charWidthInfo_s* C2D_FontGetCharWidthInfo(C2D_Font font, int glyphIndex)
{
  if (!font)
    return fontGetCharWidthInfo(fontGetSystemFont(), glyphIndex);
  else
    return fontGetCharWidthInfo(font.cfnt, glyphIndex);
}

/** @brief Calculate glyph position of given index
 * @param[in] font Font to read from, or null for system font
 * @param[out] out Glyph position
 * @param[in] glyphIndex Index to get position of
 * @param[in] flags Misc flags
 * @param[in] scaleX Size to scale in X
 * @param[in] scaleY Size to scale in Y
 */
void C2D_FontCalcGlyphPos(C2D_Font font, fontGlyphPos_s* out_, int glyphIndex, uint flags, float scaleX, float scaleY)
{
  if (!font)
    fontCalcGlyphPos(out_, fontGetSystemFont(), glyphIndex, flags, scaleX, scaleY);
  else
    fontCalcGlyphPos(out_, font.cfnt, glyphIndex, flags, scaleX, scaleY);
}

void C2D_FontCalcGlyphPosFromCodePoint(C2D_Font font, fontGlyphPos_s* out_, uint codePoint, uint flags, float scaleX, float scaleY)
{
  // Building glyph positions is pretty expensive, but we could just store the results for plain ASCII of the system font.
  if (codePoint < __C2Di_SystemFontAsciiCache.length && flags == 0 && scaleX == 1 && scaleY == 1) {
    if (font) {
      *out_ = font.asciiCache[codePoint];
    }
    else {
      *out_ = __C2Di_SystemFontAsciiCache[codePoint];
    }
  }
  else {
    C2D_FontCalcGlyphPos(font, out_, C2D_FontGlyphIndexFromCodePoint(font, codePoint), 0, 1.0f, 1.0f);
  }
}

fontGlyphPos_s* C2D_FontCalcGlyphPosFromSystemFontAscii(uint codePoint)
{
  // Building glyph positions is pretty expensive, but we could just store the results for plain ASCII of the system font.
  return &__C2Di_SystemFontAsciiCache[codePoint];
}

/** @brief Get the font info structure associated with the font
 * @param[in] font Font to read from, or null for the system font
 * @returns FINF associated with the font
 */
FINF_s* C2D_FontGetInfo(C2D_Font font)
{
  if (!font)
    return fontGetInfo(null);
  else
    return fontGetInfo(font.cfnt);
}

/** @} */

pragma(inline, true)
C2D_Font C2Di_FontAlloc()
{
  return cast(C2D_Font)malloc(C2D_Font_s.sizeof);
}

C2D_Font C2Di_PostLoadFont(C2D_Font font)
{
  if (!font.cfnt)
  {
    free(font);
    font = null;
  } else
  {
    fontFixPointers(font.cfnt);

    TGLP_s* glyphInfo = font.cfnt.finf.tglp;
    font.glyphSheets = cast(C3D_Tex*) malloc(C3D_Tex.sizeof*glyphInfo.nSheets);
    font.textScale = 30.0f / glyphInfo.cellHeight;
    if (!font.glyphSheets)
    {
      C2D_FontFree(font);
      return null;
    }

    for (int i = 0; i < glyphInfo.nSheets; i++)
    {
      C3D_Tex* tex = &font.glyphSheets[i];
      tex.data = &glyphInfo.sheetData[glyphInfo.sheetSize*i];
      tex.fmt = cast(GPUTexColor) glyphInfo.sheetFmt;
      tex.size = glyphInfo.sheetSize;
      tex.width = glyphInfo.sheetWidth;
      tex.height = glyphInfo.sheetHeight;
      tex.param = GPU_TEXTURE_MAG_FILTER(GPUTextureFilterParam.linear) | GPU_TEXTURE_MIN_FILTER(GPUTextureFilterParam.linear)
        | GPU_TEXTURE_WRAP_S(GPUTextureWrapParam.clamp_to_border) | GPU_TEXTURE_WRAP_T(GPUTextureWrapParam.clamp_to_border);
      tex.border = 0xFFFFFFFF;
      tex.lodParam = 0;
    }

    foreach (i, ref slot; font.asciiCache) {
      fontCalcGlyphPos(&slot, font.cfnt, fontGlyphIndexFromCodePoint(font.cfnt, i), 0, 1.0, 1.0);
    }
  }
  return font;
}

//TODO: actually make bindings for unistd.h
ssize_t read(int fd, void *buf, size_t nbyte);

C2D_Font C2D_FontLoadFromHandle(FILE* handle)
{
  C2D_Font font = C2Di_FontAlloc();
  if (font)
  {
    CFNT_s cfnt;
    fread(&cfnt, 1, CFNT_s.sizeof, handle);
    font.cfnt = cast(CFNT_s*) linearAlloc(cfnt.fileSize);
    if (font.cfnt)
    {
      memcpy(font.cfnt, &cfnt, CFNT_s.sizeof);
      fread(cast(ubyte*)(font.cfnt) + CFNT_s.sizeof, 1, cfnt.fileSize - CFNT_s.sizeof, handle);
    }
    font = C2Di_PostLoadFont(font);
  }
  return font;
}

C2D_Font C2Di_FontLoadFromArchive(ulong tid, const(char)* path)
{
  void* fontLzData = null;
  uint fontLzSize = 0;

  Result rc = romfsMountFromTitle(tid, FSMediaType.nand, "font");
  if (R_FAILED(rc))
    return null;

  FILE* f = fopen(path, "rb");
  if (f)
  {
    fseek(f, 0, SEEK_END);
    fontLzSize = ftell(f);
    rewind(f);

    fontLzData = malloc(fontLzSize);
    if (fontLzData)
      fread(fontLzData, 1, fontLzSize, f);

    fclose(f);
  }

  romfsUnmount("font");

  if (!fontLzData)
    return null;

  C2D_Font font = C2Di_FontAlloc();
  if (!font)
  {
    free(fontLzData);
    return null;
  }

  uint fontSize = *cast(uint*)fontLzData >> 8;
  font.cfnt = cast(CFNT_s*) linearAlloc(fontSize);
  if (font.cfnt && !decompress_LZ11(font.cfnt, fontSize, null, cast(ubyte*)fontLzData + 4, fontLzSize - 4))
  {
    linearFree(font.cfnt);
    font.cfnt = null;
  }
  free(fontLzData);

  return C2Di_PostLoadFont(font);
}

uint C2Di_RegionToFontIndex(CFGRegion region)
{
  switch (region)
  {
    default:
    case CFGRegion.jpn:
    case CFGRegion.usa:
    case CFGRegion.eur:
    case CFGRegion.aus:
      return 0;
    case CFGRegion.chn:
      return 1;
    case CFGRegion.kor:
      return 2;
    case CFGRegion.twn:
      return 3;
  }
}

static immutable(char*[]) C2Di_FontPaths =
[
  "font:/cbf_std.bcfnt.lz",
  "font:/cbf_zh-Hans-CN.bcfnt.lz",
  "font:/cbf_ko-Hang-KR.bcfnt.lz",
  "font:/cbf_zh-Hant-TW.bcfnt.lz",
];
