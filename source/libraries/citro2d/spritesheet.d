/**
 * @file spritesheet.h
 * @brief Spritesheet (texture atlas) loading and management
 */

module citro2d.spritesheet;

import core.stdc.stdio;
import core.stdc.stdlib;
import ctru.gpu.enums;
import ctru.font;
import ctru.services.cfgu;
import ctru.types;
import citro2d.base;
import citro3d.texture;
import citro3d.tex3ds;

extern (C): nothrow: @nogc:

struct C2D_SpriteSheet_s
{
    Tex3DS_Texture t3x;
    C3D_Tex        tex;
}
alias C2D_SpriteSheet = C2D_SpriteSheet_s*;

/** @defgroup SpriteSheet Sprite sheet functions
 *  @{
 */

/** @brief Load a sprite sheet from file
 *  @param[in] filename Name of the sprite sheet file (.t3x)
 *  @returns Sprite sheet handle
 *  @retval null Error
 */
C2D_SpriteSheet C2D_SpriteSheetLoad(const(char)* filename)
{
    FILE* f = fopen(filename, "rb");
    if (!f) return null;
    setvbuf(f, null, _IOFBF, 64*1024);
    C2D_SpriteSheet ret = C2D_SpriteSheetLoadFromHandle(f);
    fclose(f);
    return ret;
}

pragma(inline, true)
C2D_SpriteSheet C2Di_SpriteSheetAlloc()
{
    return cast(C2D_SpriteSheet)malloc(C2D_SpriteSheet_s.sizeof);
}

pragma(inline, true)
C2D_SpriteSheet C2Di_PostLoadSheet(C2D_SpriteSheet sheet)
{
    if (!sheet.t3x)
    {
        free(sheet);
        sheet = null;
    } else
    {
        // Configure white border around texture sheet to allow for drawing
        // non-textured polygons without having to disable GPU_TEXTURE0
        sheet.tex.border = 0xFFFFFFFF;
        C3D_TexSetWrap(&sheet.tex, GPUTextureWrapParam.clamp_to_border, GPUTextureWrapParam.clamp_to_border);
    }
    return sheet;
}

/** @brief Load a sprite sheet from memory
 *  @param[in] data Data to load
 *  @param[in] size Size of the data to load
 *  @returns Sprite sheet handle
 *  @retval null Error
 */
C2D_SpriteSheet C2D_SpriteSheetLoadFromMem(const(void)* data, size_t size)
{
    C2D_SpriteSheet sheet = C2Di_SpriteSheetAlloc();
    if (sheet)
    {
        sheet.t3x = Tex3DS_TextureImport(data, size, &sheet.tex, null, false);
        sheet = C2Di_PostLoadSheet(sheet);
    }
    return sheet;
}

pragma(inline, true)
extern(D) C2D_SpriteSheet C2D_SpriteSheetLoadFromMem(const(void)[] data)
{
    return C2D_SpriteSheetLoadFromMem(data.ptr, data.length);
}

/** @brief Load sprite sheet from file descriptor
 *  @param[in] fd File descriptor used to load data
 *  @returns Sprite sheet handle
 *  @retval null Error
 */
C2D_SpriteSheet C2D_SpriteSheetFromFD(int fd)
{
    C2D_SpriteSheet sheet = C2Di_SpriteSheetAlloc();
    if (sheet)
    {
        sheet.t3x = Tex3DS_TextureImportFD(fd, &sheet.tex, null, false);
        sheet = C2Di_PostLoadSheet(sheet);
    }
    return sheet;
}

/** @brief Load sprite sheet from stdio file handle
 *  @param[in] f File handle used to load data
 *  @returns Sprite sheet handle
 *  @retval null Error
 */
C2D_SpriteSheet C2D_SpriteSheetLoadFromHandle(FILE* f)
{
    C2D_SpriteSheet sheet = C2Di_SpriteSheetAlloc();
    if (sheet)
    {
        sheet.t3x = Tex3DS_TextureImportStdio(f, &sheet.tex, null, false);
        sheet = C2Di_PostLoadSheet(sheet);
    }
    return sheet;
}

/** @brief Free a sprite sheet
 *  @param[in] sheet Sprite sheet handle
 */
void C2D_SpriteSheetFree(C2D_SpriteSheet sheet)
{
    Tex3DS_TextureFree(sheet.t3x);
    C3D_TexDelete(&sheet.tex);
    free(sheet);
}

/** @brief Retrieves the number of sprites in the specified sprite sheet
 *  @param[in] sheet Sprite sheet handle
 *  @returns Number of sprites
 */
size_t C2D_SpriteSheetCount(C2D_SpriteSheet sheet)
{
    return Tex3DS_GetNumSubTextures(sheet.t3x);
}


/** @brief Retrieves the specified image from the specified sprite sheet
 *  @param[in] sheet Sprite sheet handle
 *  @param[in] index Index of the image to retrieve
 *  @returns Image object
 */
C2D_Image C2D_SpriteSheetGetImage(C2D_SpriteSheet sheet, size_t index)
{
    C2D_Image ret = { &sheet.tex, Tex3DS_GetSubTexture(sheet.t3x, index) };
    return ret;
}

/** @} */
