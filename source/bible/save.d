module bible.save;

import bible.bible, bible.util;
import ctru.result;
import ctru.services.fs;
import ctru.types;

nothrow: @nogc:

struct Settings {
  Translation translation;
  ColorTheme colorTheme;
  ubyte[62] spare;
}

struct Progress {
  ubyte chapter;
  ubyte scrollAmount; // 0-255 meaning top of page to bottom of page
}

// @TODO: Consider an actual config file of some kind
struct SaveFile {
  ushort fileVersion = 0;

  Settings settings;

  Progress[enumCount!Book] progress;

  Book bookmarkBook;
  ubyte bookmarkChapter;

  ubyte[56] spare;
}
static assert (SaveFile.sizeof == 256);

__gshared SaveFile gSaveFile;

static immutable FS_Path EMPTY_PATH = { type : FSPathType.empty, size : 0, data : null };

version (Output_CIA) {
  static immutable FS_Path SAVE_PATH  = { type : FSPathType.ascii, size : "/save.dat".length + 1, data : "/settings.dat".ptr };
  enum SAVE_ARCHIVE_ID = FSArchiveID.savedata;
}
else version (Output_3DSX) {
  enum SAVE_PATH_DIR_STRING = "/3ds/bible3ds";
  enum SAVE_PATH_STRING     = "/3ds/bible3ds/settings.dat";
  static immutable FS_Path SAVE_PATH     = { type : FSPathType.ascii, size : SAVE_PATH_STRING.length + 1,
                                             data : SAVE_PATH_STRING.ptr };
  static immutable FS_Path SAVE_DIR_PATH = { type : FSPathType.ascii, size : SAVE_PATH_DIR_STRING.length + 1,
                                             data : SAVE_PATH_DIR_STRING.ptr };
  enum SAVE_ARCHIVE_ID = FSArchiveID.sdmc;
}
else static assert(0);

Result saveFileInit() {
  FS_Archive archiveHandle;
  Handle fileHandle;

  Result rc = FSUSER_OpenArchive(&archiveHandle, SAVE_ARCHIVE_ID, EMPTY_PATH);

  version (Output_CIA) {
    if (R_FAILED(rc)) {
      return saveFileCreate();
    }
  }
  else version (Output_3DSX) {
    if (R_FAILED(rc)) {
      assert(0, "Couldn't open SD card filesystem!");
      return rc;
    }
  }
  else static assert(0);

  scope (exit) FSUSER_CloseArchive(archiveHandle);

  rc = FSUSER_OpenFile(&fileHandle, archiveHandle, SAVE_PATH, FS_OPEN_READ, 0);

  version (Output_CIA) {
    if (R_FAILED(rc)) {
      assert(0, "Couldn't open the app's save file??");
      return rc;
    }
  }
  else version (Output_3DSX) {
    if (R_FAILED(rc)) {
      return saveFileCreate();
    }
  }
  else static assert(0);

  scope (exit) FSFILE_Close(fileHandle);

  ulong fileSize;
  rc = FSFILE_GetSize(fileHandle, &fileSize);
  //assert(fileSize == gSaveFile.sizeof);

  if (R_FAILED(rc) || fileSize != gSaveFile.sizeof) {
    assert(0, "Either couldn't get save file size or it mismatches what we expect it to be!");
    return rc;
  }

  uint bytesRead;
  rc = FSFILE_Read(fileHandle, &bytesRead, 0, &gSaveFile, gSaveFile.sizeof);

  if (R_FAILED(rc) || bytesRead != gSaveFile.sizeof) {
    assert(0, "Couldn't read the save file for some reason!");
    return rc;
  }

  return 0;
}

Result saveFileCreate() {
  Result rc;

  version (Output_CIA) {
    rc = FSUSER_FormatSaveData(SAVE_ARCHIVE_ID, EMPTY_PATH, 512, 7, 7, 7, 7, false);

    if (R_FAILED(rc)) {
      printf("\x1b[15;1Herror: %08X\x1b[K", rc);
      assert(0, "Couldn't format the save file!");
      return rc;
    }
  }

  FS_Archive archiveHandle;
  rc = FSUSER_OpenArchive(&archiveHandle, SAVE_ARCHIVE_ID, EMPTY_PATH);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "Couldn't open the save archive!");
    return rc;
  }

  version (Output_3DSX) {
    rc = FSUSER_CreateDirectory(archiveHandle, SAVE_DIR_PATH, FS_ATTRIBUTE_DIRECTORY);

    auto description = R_DESCRIPTION(rc);

    // If the directory exists already, we'll get an error that we can ignore
    if (R_FAILED(rc) && !(description >= 180 && description <= 199)) {
      printf("\x1b[15;1Herror: %08X\x1b[K", rc);
      assert(0, "Couldn't create the save directory!");
      return rc;
    }
  }

  rc = FSUSER_CreateFile(archiveHandle, SAVE_PATH, 0, gSaveFile.sizeof);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "Couldn't create the file in which the save lives!");
    return rc;
  }

  FSUSER_CloseArchive(archiveHandle);

  return saveSettings();
}

Result saveSettings() {
  FS_Archive archiveHandle;

  Result rc = FSUSER_OpenArchive(&archiveHandle, SAVE_ARCHIVE_ID, EMPTY_PATH);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "Couldn't open the save archive!");
    return rc;
  }

  scope (exit) FSUSER_CloseArchive(archiveHandle);

  Handle fileHandle;

  rc = FSUSER_OpenFile(&fileHandle, archiveHandle, SAVE_PATH, FS_OPEN_WRITE, 0);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "Couldn't open the file in which the save lives!");
    return rc;
  }

  scope (exit) FSFILE_Close(fileHandle);

  size_t bytesWritten;
  rc = FSFILE_Write(fileHandle, &bytesWritten, 0, &gSaveFile, gSaveFile.sizeof, 0);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "Couldn't write to the save file!");
    return rc;
  }

  return 0;
}
