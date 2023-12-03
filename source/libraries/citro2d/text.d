/**
 * @file text.h
 * @brief Text rendering API
 */

module citro2d.text;

import core.stdc.string;
import citro2d.internal;
import citro2d.base;
import citro2d.font;
import citro3d.texture;
import ctru.services.cfgu;
import ctru.services.gspgpu;
import ctru.font;
import ctru.gfx;
import ctru.gpu.enums;
import ctru.result;
import ctru.svc;
import ctru.types;
import ctru.util.utf;
import core.stdc.stdarg;
import core.stdc.stdlib;

import std.math : ceil;

import bible.util;

nothrow: @nogc:

C3D_Tex* s_glyphSheets;
float s_textScale;

enum C2D_ParseFlags : uint {
  none,
  bible      = (1 << 0),  // Whether or not to perform Bible-specific hacks (e.g. verse number, italics)
}

enum C2Di_GlyphFlags : uint {
  none,
  small      = (1 << 0),
  italicized = (1 << 1),
}

enum float SMALL_SCALE        = 0.7;
enum float ITALICS_SKEW_RATIO = 0.1;

struct C2Di_Glyph
{
  uint lineNo;
  C3D_Tex* sheet;
  float xPos = 0;
  float width = 0;

  struct _anon
  {
    float left = 0, top = 0, right = 0, bottom = 0;
  };

  _anon texcoord;
  uint wordNo;
  C2Di_GlyphFlags flags;
}

struct C2D_TextBuf_s
{
  uint[2] reserved;
  size_t glyphCount;
  size_t glyphBufSize;
  C2Di_Glyph[0] glyphs;
}

alias C2D_TextBuf = C2D_TextBuf_s*;

/** @defgroup Text Text drawing functions
 *  @{
 */

/// Text object.
struct C2D_Text
{
    C2D_TextBuf buf;       ///< Buffer associated with the text.
    size_t      begin;     ///< Reserved for internal use.
    size_t      end;       ///< Reserved for internal use.
    float       width = 0; ///< Width of the text in pixels, according to 1x scale metrics.
    uint        lines;     ///< Number of lines in the text, according to 1x scale metrics;
    uint        words;     ///< Number of words in the text.
    C2D_Font    font;      ///< Font used to draw the text, or null for system font
}

enum : ubyte
{
  C2D_AtBaseline       = BIT(0), ///< Matches the Y coordinate with the baseline of the font.
  C2D_WithColor        = BIT(1), ///< Draws text with color. Requires a u32 color value.
  C2D_AlignLeft        = 0 << 2, ///< Draws text aligned to the left. This is the default.
  C2D_AlignRight       = 1 << 2, ///< Draws text aligned to the right.
  C2D_AlignCenter      = 2 << 2, ///< Draws text centered.
  C2D_AlignJustified   = 3 << 2, ///< Draws text justified. When C2D_WordWrap is not specified, right edge is x + scaleX*text->width. Otherwise, right edge is x + the width specified for those values.
  C2D_AlignMask        = 3 << 2, ///< Bitmask for alignment values.
  C2D_WordWrap         = 1 << 4, ///< Draws text with wrapping of full words before specified width. Requires a float value, passed after color if C2D_WithColor is specified.
  C2D_WordWrapPrecalc  = 2 << 4, ///< The above, but with a provided set of already-calculated wrapping information.
};

struct C2Di_LineInfo
{
  uint words;
  uint wordStart;
}

struct C2Di_WordInfo
{
  C2Di_Glyph* start;
  C2Di_Glyph* end;
  float wrapXOffset = 0;
  uint newLineNumber;
}

size_t C2Di_TextBufBufferSize(size_t maxGlyphs)
{
  return C2D_TextBuf_s.sizeof + maxGlyphs*C2Di_Glyph.sizeof;
}

extern(C) int C2Di_GlyphComp(const void* _g1, const void* _g2)
{
  const C2Di_Glyph* g1 = cast(C2Di_Glyph*)_g1;
  const C2Di_Glyph* g2 = cast(C2Di_Glyph*)_g2;
  int ret = cast(int)g1.sheet - cast(int)g2.sheet;
  if (ret == 0)
    ret = cast(int)g1 - cast(int)g2;
  return ret;
}

void C2Di_TextEnsureLoad()
{
  // Skip if already loaded
  if (s_glyphSheets)
    return;

  // Ensure the shared system font is mapped
  if (R_FAILED(fontEnsureMapped()))
    svcBreak(UserBreakType.panic);

  // Load the glyph texture sheets
  CFNT_s* font = fontGetSystemFont();
  TGLP_s* glyphInfo = fontGetGlyphInfo(font);
  s_glyphSheets = cast(C3D_Tex*) malloc(C3D_Tex.sizeof*glyphInfo.nSheets);
  s_textScale = 30.0f / glyphInfo.cellHeight;
  if (!s_glyphSheets)
    svcBreak(UserBreakType.panic);

  int i;
  for (i = 0; i < glyphInfo.nSheets; i ++)
  {
    C3D_Tex* tex = &s_glyphSheets[i];
    tex.data = fontGetGlyphSheetTex(font, i);
    tex.fmt = cast(GPUTexColor) glyphInfo.sheetFmt;
    tex.size = glyphInfo.sheetSize;
    tex.width = glyphInfo.sheetWidth;
    tex.height = glyphInfo.sheetHeight;
    tex.param = GPU_TEXTURE_MAG_FILTER(GPUTextureFilterParam.linear) | GPU_TEXTURE_MIN_FILTER(GPUTextureFilterParam.linear)
      | GPU_TEXTURE_WRAP_S(GPUTextureWrapParam.clamp_to_border) | GPU_TEXTURE_WRAP_T(GPUTextureWrapParam.clamp_to_border);
    tex.border = 0xFFFFFFFF;
    tex.lodParam = 0;
  }
}

/** @brief Creates a new text buffer.
 *  @param[in] maxGlyphs Maximum number of glyphs that can be stored in the buffer.
 *  @returns Text buffer handle (or null on failure).
 */
C2D_TextBuf C2D_TextBufNew(size_t maxGlyphs)
{
  C2Di_TextEnsureLoad();

  C2D_TextBuf buf = cast(C2D_TextBuf)malloc(C2Di_TextBufBufferSize(maxGlyphs));
  if (!buf) return null;
  memset(buf, 0, C2D_TextBuf_s.sizeof);
  buf.glyphBufSize = maxGlyphs;
  return buf;
}

C2D_TextBuf C2D_TextBufNew(Arena* arena, size_t maxGlyphs)
{
  C2Di_TextEnsureLoad();

  C2D_TextBuf buf = cast(C2D_TextBuf) arenaPushBytesZero(arena, C2Di_TextBufBufferSize(maxGlyphs)).ptr;
  buf.glyphBufSize = maxGlyphs;
  return buf;
}

/** @brief Resizes a text buffer.
 *  @param[in] buf Text buffer to resize.
 *  @param[in] maxGlyphs Maximum number of glyphs that can be stored in the buffer.
 *  @returns New text buffer handle (or null on failure).
 *  @remarks If successful, old text buffer handle becomes invalid.
 */
C2D_TextBuf C2D_TextBufResize(C2D_TextBuf buf, size_t maxGlyphs)
{
  size_t oldMax = buf.glyphBufSize;
  C2D_TextBuf newBuf = cast(C2D_TextBuf)realloc(buf, C2Di_TextBufBufferSize(maxGlyphs));
  if (!newBuf) return null;

  // zero out new glyphs
  if (maxGlyphs > oldMax)
    memset(&newBuf.glyphs[oldMax], 0, (maxGlyphs-oldMax)*C2Di_Glyph.sizeof);

  newBuf.glyphBufSize = maxGlyphs;
  return newBuf;
}

/** @brief Deletes a text buffer.
 *  @param[in] buf Text buffer handle.
 *  @remarks This also invalidates all text objects previously created with this buffer.
 */
void C2D_TextBufDelete(C2D_TextBuf buf)
{
  free(buf);
}

/** @brief Clears all stored text in a buffer.
 *  @param[in] buf Text buffer handle.
 */
void C2D_TextBufClear(C2D_TextBuf buf)
{
  buf.glyphCount = 0;
}

/** @brief Retrieves the number of glyphs stored in a text buffer.
 *  @param[in] buf Text buffer handle.
 *  @returns The number of glyphs.
 */
size_t C2D_TextBufGetNumGlyphs(C2D_TextBuf buf)
{
  return buf.glyphCount;
}

/** @brief Parses and adds a single line of text to a text buffer.
 *  @param[out] text Pointer to text object to store information in.
 *  @param[in] buf Text buffer handle.
 *  @param[in] str String to parse.
 *  @param[in] lineNo Line number assigned to the text (used to calculate vertical position).
 *  @param[in] flags String parsing option flags.
 *  @remarks Whitespace doesn't add any glyphs to the text buffer and is thus "free".
 *  @returns On success, a pointer to the character on which string processing stopped, which
 *           can be a newline ('\n'; indicating that's where the line ended), the null character
 *           ('\0'; indicating the end of the string was reached), or any other character
 *           (indicating the text buffer is full and no more glyphs can be added).
 *           On failure, null.
 */
const(char)[] C2D_TextParseLine (C2D_Text* text, C2D_TextBuf buf, const(char)[] str, uint lineNo, C2D_ParseFlags flags = C2D_ParseFlags.none)
{
  return C2D_TextFontParseLine(text, null, buf, str, lineNo, flags);
}

/** @brief Parses and adds a single line of text to a text buffer.
 *  @param[out] text Pointer to text object to store information in.
 *  @param[in] font Font to get glyphs from, or null for system font
 *  @param[in] buf Text buffer handle.
 *  @param[in] str String to parse.
 *  @param[in] flags String parsing option flags.
 *  @param[in] lineNo Line number assigned to the text (used to calculate vertical position).
 *  @remarks Whitespace doesn't add any glyphs to the text buffer and is thus "free".
 *  @returns On success, a pointer to the character on which string processing stopped, which
 *           can be a newline ('\n'; indicating that's where the line ended), the null character
 *           ('\0'; indicating the end of the string was reached), or any other character
 *           (indicating the text buffer is full and no more glyphs can be added).
 *           On failure, null.
 */
const(char)[] C2D_TextFontParseLine (C2D_Text* text, C2D_Font font, C2D_TextBuf buf, const(char)[] str, uint lineNo, C2D_ParseFlags flags = C2D_ParseFlags.none)
{
  const(ubyte)[] p = cast(const(ubyte)[])str;
  text.font  = font;
  text.buf   = buf;
  text.begin = buf.glyphCount;
  text.width = 0.0f;
  uint wordNum = 0;
  bool lastWasWhitespace = true;
  bool verseNumActive = false;
  int  italicsActive = 0;
  int  skipCount = 0;
  bool lineStart = true;

  while (buf.glyphCount < buf.glyphBufSize)
  {
    if (skipCount > 0) skipCount--;

    uint code;
    ssize_t units = decode_utf8(&code, p);
    if (units == -1)
    {
      code = 0xFFFD;
      units = 1;
    }
    else if (code == 0 || code == '\n')
    {
      // If we last parsed non-whitespace, increment the word counter
      if (!lastWasWhitespace)
        wordNum++;
      break;
    }
    else if ((flags & C2D_ParseFlags.bible) && lineStart && code == '[') {
      verseNumActive = true;
      skipCount = -1; // Skip chapter number that comes before the ':'
    }
    else if (verseNumActive && code == ':') {
      skipCount = 1;
    }
    else if (verseNumActive && code == ']') {
      verseNumActive = false;
      skipCount = 1;
    }
    else if ((flags & C2D_ParseFlags.bible) && code == '`') {
      italicsActive++;
      skipCount = 1;
    }
    else if (italicsActive && code == '\'') {
      italicsActive--;
      skipCount = 1;
    }

    p = p[units..$];

    if (skipCount == 0) {
      fontGlyphPos_s glyphData;
      C2D_FontCalcGlyphPos(font, &glyphData, C2D_FontGlyphIndexFromCodePoint(font, code), 0, 1.0f, 1.0f);
      float scaleFactor = verseNumActive ? SMALL_SCALE : 1.0;

      if (glyphData.width > 0.0f)
      {

        C2Di_Glyph* glyph = &buf.glyphs[buf.glyphCount++];
        if (font)
          glyph.sheet = &font.glyphSheets[glyphData.sheetIndex];
        else
          glyph.sheet = &s_glyphSheets[glyphData.sheetIndex];
        glyph.xPos            = text.width + glyphData.xOffset;
        glyph.lineNo          = lineNo;
        glyph.wordNo          = wordNum;
        glyph.width           = glyphData.width * scaleFactor;
        glyph.texcoord.left   = glyphData.texcoord.left;
        glyph.texcoord.top    = glyphData.texcoord.top;
        glyph.texcoord.right  = glyphData.texcoord.right;
        glyph.texcoord.bottom = glyphData.texcoord.bottom;
        glyph.flags           = C2Di_GlyphFlags.none;

        if (verseNumActive) glyph.flags |= C2Di_GlyphFlags.small;
        if (italicsActive)  glyph.flags |= C2Di_GlyphFlags.italicized;

        lastWasWhitespace = false;
      }
      else if (!lastWasWhitespace)
      {
        wordNum++;
        lastWasWhitespace = true;
      }
      text.width += glyphData.xAdvance * scaleFactor;
    }

    lineStart = false;
  }
  text.end = buf.glyphCount;
  text.width *= s_textScale;
  text.lines = 1;
  text.words = wordNum;
  return cast(const(char)[])p;
}

/** @brief Parses and adds arbitrary text (including newlines) to a text buffer.
 *  @param[out] text Pointer to text object to store information in.
 *  @param[in] buf Text buffer handle.
 *  @param[in] str String to parse.
 *  @param[in] flags String parsing option flags.
 *  @remarks Whitespace doesn't add any glyphs to the text buffer and is thus "free".
 *  @returns On success, a pointer to the character on which string processing stopped, which
 *           can be the null character ('\0'; indicating the end of the string was reached),
 *           or any other character (indicating the text buffer is full and no more glyphs can be added).
 *           On failure, null.
 */
const(char)[] C2D_TextParse (C2D_Text* text, C2D_TextBuf buf, const(char)[] str, C2D_ParseFlags flags = C2D_ParseFlags.none)
{
  return C2D_TextFontParse(text, null, buf, str, flags);
}

/** @brief Parses and adds arbitrary text (including newlines) to a text buffer.
 *  @param[out] text Pointer to text object to store information in.
 *  @param[in] font Font to get glyphs from, or null for system font
 *  @param[in] buf Text buffer handle.
 *  @param[in] str String to parse.
 *  @param[in] flags String parsing option flags.
 *  @remarks Whitespace doesn't add any glyphs to the text buffer and is thus "free".
 *  @returns On success, a pointer to the character on which string processing stopped, which
 *           can be the null character ('\0'; indicating the end of the string was reached),
 *           or any other character (indicating the text buffer is full and no more glyphs can be added).
 *           On failure, null.
 */
const(char)[] C2D_TextFontParse (C2D_Text* text, C2D_Font font, C2D_TextBuf buf, const(char)[] str, C2D_ParseFlags flags = C2D_ParseFlags.none)
{
  text.font   = font;
  text.buf    = buf;
  text.begin  = buf.glyphCount;
  text.width  = 0.0f;
  text.words  = 0;
  text.lines  = 0;

  for (;;)
  {
    C2D_Text temp;
    str = C2D_TextFontParseLine(&temp, font, buf, str, text.lines++, flags);
    text.words += temp.words;
    if (temp.width > text.width)
      text.width = temp.width;
    if (!str.length || str[0] != '\n')
      break;
    str = str[1..$];
  }

  text.end = buf.glyphCount;
  return str;
}

/** @brief Optimizes a text object in order to be drawn more efficiently.
 *  @param[in] text Pointer to text object.
 */
void C2D_TextOptimize(const(C2D_Text)* text_)
{
  auto text  = cast(C2D_Text*) text_; // get around lack of head const
  // Dirty and probably not very efficient/overkill, but it should work
  qsort(&text.buf.glyphs[text.begin], text.end-text.begin, C2Di_Glyph.sizeof, &C2Di_GlyphComp);
}

/** @brief Retrieves the total dimensions of a text object.
 *  @param[in] text Pointer to text object.
 *  @param[in] scaleX Horizontal size of the font. 1.0f corresponds to the native size of the font.
 *  @param[in] scaleY Vertical size of the font. 1.0f corresponds to the native size of the font.
 *  @param[out] outWidth (optional) Variable in which to store the width of the text.
 *  @param[out] outHeight (optional) Variable in which to store the height of the text.
 */
void C2D_TextGetDimensions(const(C2D_Text)* text, float scaleX, float scaleY, float* outWidth, float* outHeight)
{
  if (outWidth)
    *outWidth  = scaleX*text.width;
  if (outHeight)
  {
    if (text.font)
      *outHeight = ceil(scaleY*text.font.textScale*text.font.cfnt.finf.lineFeed)*text.lines;
    else
      *outHeight = ceil(scaleY*s_textScale*fontGetInfo(fontGetSystemFont()).lineFeed)*text.lines;
  }
}

void C2Di_CalcLineInfo(const(C2D_Text)* text_, C2Di_LineInfo[] lines, C2Di_WordInfo[] words)
{
  auto text = cast(C2D_Text*) text_; // get around lack of head const

  C2Di_Glyph* begin = cast(C2Di_Glyph*) &text.buf.glyphs[text.begin];
  C2Di_Glyph* end   = cast(C2Di_Glyph*) &text.buf.glyphs[text.end];
  C2Di_Glyph* cur;
  // Get information about lines
  lines[] = C2Di_LineInfo.init;
  for (cur = begin; cur != end; cur++)
    if (cur.wordNo >= lines[cur.lineNo].words)
      lines[cur.lineNo].words = cur.wordNo + 1;
  for (uint i = 1; i < text.lines; i++)
    lines[i].wordStart = lines[i-1].wordStart + lines[i-1].words;

  // Get information about words
  for (uint i = 0; i < text.words; i++)
  {
    words[i].start = null;
    words[i].end = null;
    words[i].wrapXOffset = 0;
    words[i].newLineNumber = 0;
  }
  for (cur = begin; cur != end; cur++)
  {
    uint consecutiveWordNum = cur.wordNo + lines[cur.lineNo].wordStart;
    if (!words[consecutiveWordNum].end || cur.xPos + cur.width > words[consecutiveWordNum].end.xPos + words[consecutiveWordNum].end.width)
      words[consecutiveWordNum].end = cur;
    if (!words[consecutiveWordNum].start || cur.xPos < words[consecutiveWordNum].start.xPos)
      words[consecutiveWordNum].start = cur;
    words[consecutiveWordNum].newLineNumber = cur.lineNo;
  }
}

void C2Di_CalcLineWidths(float* widths, const(C2D_Text)* text_, const(C2Di_WordInfo)[] words_, bool wrap)
{
  auto text  = cast(C2D_Text*) text_; // get around lack of head const
  auto words = cast(C2Di_WordInfo[]) words_; // get around lack of head const

  uint currentWord = 0;
  if (words)
  {
    while (currentWord != text.words)
    {
      uint nextLineWord = currentWord + 1;
      // Advance nextLineWord to the next word that's on a different line, or the end
      if (wrap)
      {
        while (nextLineWord != text.words && words[nextLineWord].newLineNumber == words[currentWord].newLineNumber) nextLineWord++;
        // Finally, set the new line width
        widths[words[currentWord].newLineNumber] = words[nextLineWord-1].end.xPos + words[nextLineWord-1].end.width - words[currentWord].start.xPos;
      }
      else
      {
        while (nextLineWord != text.words && words[nextLineWord].start.lineNo == words[currentWord].start.lineNo) nextLineWord++;
        // Finally, set the new line width
        widths[words[currentWord].start.lineNo] = words[nextLineWord-1].end.xPos + words[nextLineWord-1].end.width - words[currentWord].start.xPos;
      }

      currentWord = nextLineWord;
    }
  }
  else
  {
    memset(widths, 0, float.sizeof * text.lines);
    for (C2Di_Glyph* cur = &text.buf.glyphs[text.begin]; cur != &text.buf.glyphs[text.end]; cur++)
      if (cur.xPos + cur.width > widths[cur.lineNo])
        widths[cur.lineNo] = cur.xPos + cur.width;
  }
}

struct C2D_WrapInfo {
  C2Di_LineInfo[] lines;
  C2Di_WordInfo[] words;
}

__gshared uint biggerBytes = 0, lesserBytes = 0;

C2D_WrapInfo C2D_CalcWrapInfo(const(C2D_Text)* text_, Arena* arena, float scaleX, float maxWidth) {
  auto text  = cast(C2D_Text*) text_; // get around lack of head const

  C2Di_LineInfo[] lines = null;
  C2Di_WordInfo[] words = null;

  lines = arenaPushArray!(C2Di_LineInfo, false)(arena, text.lines);
  words = arenaPushArray!(C2Di_WordInfo, false)(arena, text.words);
  biggerBytes += C2D_WrapInfo.sizeof;
  lesserBytes += (C2Di_LineInfo*).sizeof * 2;

  C2Di_CalcLineInfo(text, lines, words);
  // The first word will never have a wrap offset in X or Y
  for (uint i = 1; i < text.words; i++)
  {
    // If the current word was originally on a different line than the last one, only the difference between new line number and original line number should be the same
    if (words[i-1].start.lineNo != words[i].start.lineNo)
    {
      words[i].wrapXOffset = 0;
      words[i].newLineNumber = words[i].start.lineNo + (words[i-1].newLineNumber - words[i-1].start.lineNo);
    }
    // Otherwise, if the current word goes over the width, with the previous word's offset taken into account...
    else if (scaleX*(words[i-1].wrapXOffset + words[i].end.xPos + words[i].end.width) > maxWidth)
    {
      // Then set the X offset to the negative of the original position
      words[i].wrapXOffset = -words[i].start.xPos;
      // And set the new line number based off the last word's
      words[i].newLineNumber = words[i-1].newLineNumber + 1;
    }
    // Otherwise both X offset and new line number should be the same as the last word's
    else
    {
      words[i].wrapXOffset = words[i-1].wrapXOffset;
      words[i].newLineNumber = words[i-1].newLineNumber;
    }
  }

  return C2D_WrapInfo(lines, words);
}

/** @brief Draws text using the GPU.
 *  @param[in] text Pointer to text object.
 *  @param[in] flags Text drawing flags.
 *  @param[in] x Horizontal position to draw the text on.
 *  @param[in] y Vertical position to draw the text on. If C2D_AtBaseline is not specified (default), this
 *               is the top left corner of the block of text; otherwise this is the position of the baseline
 *               of the first line of text.
 *  @param[in] z Depth value of the text. If unsure, pass 0.0f.
 *  @param[in] scaleX Horizontal size of the font. 1.0f corresponds to the native size of the font.
 *  @param[in] scaleY Vertical size of the font. 1.0f corresponds to the native size of the font.
 *  @remarks The default 3DS system font has a glyph height of 30px, and the baseline is at 25px.
 */
extern(C) void C2D_DrawText(const(C2D_Text)* text_, uint flags, GFXScreen screen, float x, float y, float z, float scaleX, float scaleY, ...)
{
  auto text  = cast(C2D_Text*) text_; // get around lack of head const

  C2Di_Context* ctx = C2Di_GetContext();

  const screenWidth = screen == GFXScreen.top ? GSP_SCREEN_HEIGHT_TOP : GSP_SCREEN_HEIGHT_BOTTOM;

  // If there are no words, we can't do the math calculations necessary with them. Just return; nothing would be drawn anyway.
  if (text.words == 0)
    return;
  C2Di_Glyph* begin = &text.buf.glyphs[text.begin];
  C2Di_Glyph* end   = &text.buf.glyphs[text.end];
  C2Di_Glyph* cur;
  CFNT_s* systemFont = fontGetSystemFont();

  scaleX *= s_textScale;
  scaleY *= s_textScale;

  float glyphZ = z;
  float glyphH;
  float dispY;
  if (text.font)
  {
    glyphH = scaleY*text.font.cfnt.finf.tglp.cellHeight;
    dispY = ceil(scaleY*text.font.cfnt.finf.lineFeed);
  } else
  {
    glyphH = scaleY*fontGetGlyphInfo(systemFont).cellHeight;
    dispY = ceil(scaleY*fontGetInfo(systemFont).lineFeed);
  }
  uint color = 0xFF000000;
  float maxWidth = scaleX*text.width;

  C2Di_LineInfo[] lines = null;
  C2Di_WordInfo[] words = null;

  va_list va;
  va_start(va, scaleY);

  if (flags & C2D_AtBaseline)
  {
    if (text.font)
      y -= scaleY*text.font.cfnt.finf.tglp.baselinePos;
    else
      y -= scaleY*fontGetGlyphInfo(systemFont).baselinePos;
  }
  if (flags & C2D_WithColor)
    color = va_arg!uint(va);
  if (flags & C2D_WordWrap)
    maxWidth = va_arg!double(va); // Passed as float, but varargs promotes to double.
  if (flags & C2D_WordWrapPrecalc){
    C2D_WrapInfo* C2D_wrapInfo = va_arg!(C2D_WrapInfo*)(va);
    lines = C2D_wrapInfo.lines;
    words = C2D_wrapInfo.words;
  }

  va_end(va);

  C2Di_SetCircle(false);

  if (flags & C2D_WordWrap)
  {
    lines = (cast(C2Di_LineInfo*) alloca(C2Di_LineInfo.sizeof*text.lines))[0..text.lines];
    words = (cast(C2Di_WordInfo*) alloca(C2Di_WordInfo.sizeof*text.words))[0..text.words];
    C2Di_CalcLineInfo(text, lines, words);
    // The first word will never have a wrap offset in X or Y
    for (uint i = 1; i < text.words; i++)
    {
      // If the current word was originally on a different line than the last one, only the difference between new line number and original line number should be the same
      if (words[i-1].start.lineNo != words[i].start.lineNo)
      {
        words[i].wrapXOffset = 0;
        words[i].newLineNumber = words[i].start.lineNo + (words[i-1].newLineNumber - words[i-1].start.lineNo);
      }
      // Otherwise, if the current word goes over the width, with the previous word's offset taken into account...
      else if (scaleX*(words[i-1].wrapXOffset + words[i].end.xPos + words[i].end.width) > maxWidth)
      {
        // Then set the X offset to the negative of the original position
        words[i].wrapXOffset = -words[i].start.xPos;
        // And set the new line number based off the last word's
        words[i].newLineNumber = words[i-1].newLineNumber + 1;
      }
      // Otherwise both X offset and new line number should be the same as the last word's
      else
      {
        words[i].wrapXOffset = words[i-1].wrapXOffset;
        words[i].newLineNumber = words[i-1].newLineNumber;
      }
    }
  }

  pragma(inline, true)
  static void appendGlyphQuad(C2Di_Context* ctx, C2Di_Glyph* cur, float glyphX, float glyphY, float glyphW, float thisGlyphH, float glyphZ, float skew, uint color) {
    float xMinSkewMin = glyphX-skew, xMinSkewMax = glyphX+skew, xMaxSkewMin = glyphX+glyphW-skew, xMaxSkewMax = glyphX+glyphW+skew;
    float yMax = glyphY+thisGlyphH;
    C2Di_Vertex vertex = {
      x : xMinSkewMax, y : glyphY, z : glyphZ,
      u : cur.texcoord.left, v : cur.texcoord.top,
      ptX : 0.0f, ptY : 1.0f,
      color : color,
    };

    ctx.vtxBuf[ctx.vtxBufPos++] = vertex;
    vertex.x = xMinSkewMin;
    vertex.y = yMax;
    vertex.v = cur.texcoord.bottom;
    ctx.vtxBuf[ctx.vtxBufPos++] = vertex;
    vertex.x = xMaxSkewMax;
    vertex.y = glyphY;
    vertex.u = cur.texcoord.right;
    vertex.v = cur.texcoord.top;
    ctx.vtxBuf[ctx.vtxBufPos++] = vertex;
    ctx.vtxBuf[ctx.vtxBufPos++] = vertex;
    vertex.x = xMinSkewMin;
    vertex.y = yMax;
    vertex.u = cur.texcoord.left;
    vertex.v = cur.texcoord.bottom;
    ctx.vtxBuf[ctx.vtxBufPos++] = vertex;
    vertex.x = xMaxSkewMin;
    vertex.u = cur.texcoord.right;
    ctx.vtxBuf[ctx.vtxBufPos++] = vertex;
  }

  switch (flags & C2D_AlignMask)
  {
    case C2D_AlignLeft:
      for (cur = begin; cur != end; ++cur)
      {
        float glyphW = scaleX*cur.width;
        float glyphX;
        float glyphY;
        float thisGlyphH = glyphH * ((cur.flags & C2Di_GlyphFlags.small) ? SMALL_SCALE : 1.0);

        if (flags & (C2D_WordWrap | C2D_WordWrapPrecalc))
        {
          uint consecutiveWordNum = cur.wordNo + lines[cur.lineNo].wordStart;
          glyphX = x+scaleX*(cur.xPos + words[consecutiveWordNum].wrapXOffset);
          glyphY = y+dispY*words[consecutiveWordNum].newLineNumber;
        }
        else
        {
          glyphX = x+scaleX*cur.xPos;
          glyphY = y+dispY*cur.lineNo;
        }

        //if (glyphX > screenWidth || glyphX+glyphW < 0) {
        //  continue;
        //}

        float skew = (cur.flags & C2Di_GlyphFlags.italicized) ? thisGlyphH * ITALICS_SKEW_RATIO : 0.0;

        C2Di_SetTex(cur.sheet);
        C2Di_Update();

        appendGlyphQuad(ctx, cur, glyphX, glyphY, glyphW, thisGlyphH, glyphZ, skew, color);
      }
      break;
    case C2D_AlignRight:
    {
      //float[flags & C2D_WordWrap ? words[text.words-1].newLineNumber + 1 : text.lines] finalLineWidths;
      size_t lineWidthsLength = flags & C2D_WordWrap ? words[text.words-1].newLineNumber + 1 : text.lines;
      float* finalLineWidths = cast(float*) alloca(float.sizeof * (lineWidthsLength));

      C2Di_CalcLineWidths(finalLineWidths, text, words, !!(flags & C2D_WordWrap));

      for (cur = begin; cur != end; cur++)
      {
        float glyphW = scaleX*cur.width;
        float glyphX;
        float glyphY;
        float thisGlyphH = glyphH * ((cur.flags & C2Di_GlyphFlags.small) ? SMALL_SCALE : 1.0);

        if (flags & C2D_WordWrap)
        {
          uint consecutiveWordNum = cur.wordNo + lines[cur.lineNo].wordStart;
          glyphX = x + scaleX*(cur.xPos + words[consecutiveWordNum].wrapXOffset - finalLineWidths[words[consecutiveWordNum].newLineNumber]);
          glyphY = y + dispY*words[consecutiveWordNum].newLineNumber;
        }
        else
        {
          glyphX = x + scaleX*(cur.xPos - finalLineWidths[cur.lineNo]);
          glyphY = y + dispY*cur.lineNo;
        }

        float skew = (cur.flags & C2Di_GlyphFlags.italicized) ? thisGlyphH * ITALICS_SKEW_RATIO : 0.0;

        C2Di_SetTex(cur.sheet);
        C2Di_Update();

        appendGlyphQuad(ctx, cur, glyphX, glyphY, glyphW, thisGlyphH, glyphZ, skew, color);
      }
    }
    break;
    case C2D_AlignCenter:
    {
      //float[flags & C2D_WordWrap ? words[text.words-1].newLineNumber + 1 : text.lines] finalLineWidths;
      size_t lineWidthsLength = flags & C2D_WordWrap ? words[text.words-1].newLineNumber + 1 : text.lines;
      float* finalLineWidths = cast(float*) alloca(float.sizeof * (lineWidthsLength));

      C2Di_CalcLineWidths(finalLineWidths, text, words, !!(flags & C2D_WordWrap));

      for (cur = begin; cur != end; cur++)
      {
        float glyphW = scaleX*cur.width;
        float glyphX;
        float glyphY;
        float thisGlyphH = glyphH * ((cur.flags & C2Di_GlyphFlags.small) ? SMALL_SCALE : 1.0);

        if (flags & C2D_WordWrap)
        {
          uint consecutiveWordNum = cur.wordNo + lines[cur.lineNo].wordStart;
          glyphX = x + scaleX*(cur.xPos + words[consecutiveWordNum].wrapXOffset - finalLineWidths[words[consecutiveWordNum].newLineNumber]/2);
          glyphY = y + dispY*words[consecutiveWordNum].newLineNumber;
        }
        else
        {
          glyphX = x + scaleX*(cur.xPos - finalLineWidths[cur.lineNo]/2);
          glyphY = y + dispY*cur.lineNo;
        }

        float skew = (cur.flags & C2Di_GlyphFlags.italicized) ? thisGlyphH * ITALICS_SKEW_RATIO : 0.0;

        C2Di_SetTex(cur.sheet);
        C2Di_Update();

        appendGlyphQuad(ctx, cur, glyphX, glyphY, glyphW, thisGlyphH, glyphZ, skew, color);
      }
    }
    break;
    case C2D_AlignJustified:
    {
      if (!(flags & C2D_WordWrap))
      {
        lines = (cast(C2Di_LineInfo*) alloca(C2Di_LineInfo.sizeof*text.lines))[0..text.lines];
        words = (cast(C2Di_WordInfo*) alloca(C2Di_WordInfo.sizeof*text.words))[0..text.words];
        C2Di_CalcLineInfo(text, lines, words);
      }
      // Get total width available for whitespace for all lines after wrapping
      struct jlinfo_t
      {
        float whitespaceWidth;
        uint wordStart;
        uint words;
      }

      size_t jlinfoSize = words[text.words - 1].newLineNumber + 1;
      jlinfo_t* justifiedLineInfo = cast(jlinfo_t*) alloca(jlinfo_t.sizeof * jlinfoSize);

      for (uint i = 0; i < words[text.words - 1].newLineNumber + 1; i++)
      {
        justifiedLineInfo[i].whitespaceWidth = 0;
        justifiedLineInfo[i].words = 0;
        justifiedLineInfo[i].wordStart = 0;
      }
      for (uint i = 0; i < text.words; i++)
      {
        // Calculate the total text width
        justifiedLineInfo[words[i].newLineNumber].whitespaceWidth += words[i].end.xPos + words[i].end.width - words[i].start.xPos;
        // Increment amount of words
        justifiedLineInfo[words[i].newLineNumber].words++;
        // And set the word starts
        if (i > 0 && words[i-1].newLineNumber != words[i].newLineNumber)
          justifiedLineInfo[words[i].newLineNumber].wordStart = i;
      }
      for (uint i = 0; i < words[text.words - 1].newLineNumber + 1; i++)
      {
        // Transform it from total text width to total whitespace width
        justifiedLineInfo[i].whitespaceWidth = maxWidth - scaleX*justifiedLineInfo[i].whitespaceWidth;
        // And then get the width of a single whitespace
        if (justifiedLineInfo[i].words > 1)
          justifiedLineInfo[i].whitespaceWidth /= justifiedLineInfo[i].words - 1;
      }

      // Set up final word beginnings and ends
      struct wordPositions_t
      {
        float xBegin;
        float xEnd;
      }

      wordPositions_t* wordPositions = cast(wordPositions_t*) alloca(wordPositions_t.sizeof * text.words);

      wordPositions[0].xBegin = 0;
      wordPositions[0].xEnd = wordPositions[0].xBegin + words[0].end.xPos + words[0].end.width - words[0].start.xPos;
      for (uint i = 1; i < text.words; i++)
      {
        wordPositions[i].xBegin = words[i-1].newLineNumber != words[i].newLineNumber ? 0 : wordPositions[i-1].xEnd;
        wordPositions[i].xEnd = wordPositions[i].xBegin + words[i].end.xPos + words[i].end.width - words[i].start.xPos;
      }

      for (cur = begin; cur != end; cur++)
      {
        uint consecutiveWordNum = cur.wordNo + lines[cur.lineNo].wordStart;
        float glyphW = scaleX*cur.width;
        // The given X position, plus the scaled beginning position for this word, plus the offset of this glyph within the word, plus the whitespace width for this line times the word number within the line
        float glyphX = x + scaleX*wordPositions[consecutiveWordNum].xBegin + scaleX*(cur.xPos - words[consecutiveWordNum].start.xPos) + justifiedLineInfo[words[consecutiveWordNum].newLineNumber].whitespaceWidth*(consecutiveWordNum - justifiedLineInfo[words[consecutiveWordNum].newLineNumber].wordStart);
        float glyphY = y + dispY*words[consecutiveWordNum].newLineNumber;
        float thisGlyphH = glyphH * ((cur.flags & C2Di_GlyphFlags.small) ? SMALL_SCALE : 1.0);

        float skew = (cur.flags & C2Di_GlyphFlags.italicized) ? thisGlyphH * ITALICS_SKEW_RATIO : 0.0;

        C2Di_SetTex(cur.sheet);
        C2Di_Update();

        appendGlyphQuad(ctx, cur, glyphX, glyphY, glyphW, thisGlyphH, glyphZ, skew, color);
      }
    }
    break;

    default: break;
  }
}

/** @} */

// Ported and modified from libctru's decode_utf8.c
ssize_t
decode_utf8(uint*          output,
            const(ubyte)[] input)
{
  ubyte code1, code2, code3, code4;

  if (input.length == 0) return 0;

  code1 = input[0];
  if(code1 < 0x80)
  {
    /* 1-byte sequence */
    *output = code1;
    return 1;
  }
  else if(code1 < 0xC2)
  {
    return -1;
  }
  else if(code1 < 0xE0)
  {
    /* 2-byte sequence */
    if (input.length < 2) return -1;

    code2 = input[1];
    if((code2 & 0xC0) != 0x80)
    {
      return -1;
    }

    *output = (code1 << 6) + code2 - 0x3080;
    return 2;
  }
  else if(code1 < 0xF0)
  {
    if (input.length < 3) return -1;
    /* 3-byte sequence */
    code2 = input[1];
    if((code2 & 0xC0) != 0x80)
    {
      return -1;
    }
    if(code1 == 0xE0 && code2 < 0xA0)
    {
      return -1;
    }

    code3 = input[2];
    if((code3 & 0xC0) != 0x80)
    {
      return -1;
    }

    *output = (code1 << 12) + (code2 << 6) + code3 - 0xE2080;
    return 3;
  }
  else if(code1 < 0xF5)
  {
    /* 4-byte sequence */
    if (input.length < 4) return -1;

    code2 = input[1];
    if((code2 & 0xC0) != 0x80)
    {
      return -1;
    }
    if(code1 == 0xF0 && code2 < 0x90)
    {
      return -1;
    }
    if(code1 == 0xF4 && code2 >= 0x90)
    {
      return -1;
    }

    code3 = input[2];
    if((code3 & 0xC0) != 0x80)
    {
      return -1;
    }

    code4 = input[3];
    if((code4 & 0xC0) != 0x80)
    {
      return -1;
    }

    *output = (code1 << 18) + (code2 << 12) + (code3 << 6) + code4 - 0x3C82080;
    return 4;
  }

  return -1;
}