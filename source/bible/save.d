module bible.save;

import bible.util;
import ctru.result;
import ctru.services.fs;
import ctru.types;

nothrow: @nogc:

struct SaveFile {
  ubyte todo;
}

struct SaveData {
  SaveFile[3] saveFiles;
  SaveFile* currentSave;
}
__gshared SaveData gSaveData;

static immutable FS_Path EMPTY_PATH = { type : FSPathType.empty, size : 0, data : null };

version (Output_CIA) {
  static immutable FS_Path SAVE_PATH  = { type : FSPathType.ascii, size : "/save.dat".length + 1, data : "/save.dat".ptr };
  enum SAVE_ARCHIVE_ID = FSArchiveID.savedata;
}
else version (Output_3DSX) {
  enum SAVE_PATH_DIR_STRING = "/3ds/bible3ds";
  enum SAVE_PATH_STRING     = "/3ds/bible3ds/save.dat";
  static immutable FS_Path SAVE_PATH     = { type : FSPathType.ascii, size : SAVE_PATH_STRING.length + 1,
                                             data : SAVE_PATH_STRING.ptr };
  static immutable FS_Path SAVE_DIR_PATH = { type : FSPathType.ascii, size : SAVE_PATH_DIR_STRING.length + 1,
                                             data : SAVE_PATH_DIR_STRING.ptr };
  enum SAVE_ARCHIVE_ID = FSArchiveID.sdmc;
}
else static assert(0);

Result saveGameInit() {
  FS_Archive archiveHandle;
  Handle fileHandle;

  Result rc = FSUSER_OpenArchive(&archiveHandle, SAVE_ARCHIVE_ID, EMPTY_PATH);

  version (Output_CIA) {
    if (R_FAILED(rc)) {
      return saveGameCreate();
    }
  }
  else version (Output_3DSX) {
    if (R_FAILED(rc)) {
      assert(0, "couldn't open SD card filesystem");
      return rc;
    }
  }
  else static assert(0);

  scope (exit) FSUSER_CloseArchive(archiveHandle);

  rc = FSUSER_OpenFile(&fileHandle, archiveHandle, SAVE_PATH, FS_OPEN_READ, 0);

  version (Output_CIA) {
    if (R_FAILED(rc)) {
      assert(0, "couldn't open the app's save file??");
      return rc;
    }
  }
  else version (Output_3DSX) {
    if (R_FAILED(rc)) {
      return saveGameCreate();
    }
  }
  else static assert(0);

  scope (exit) FSFILE_Close(fileHandle);

  ulong fileSize;
  rc = FSFILE_GetSize(fileHandle, &fileSize);
  //assert(fileSize == gSaveData.saveFiles.sizeof);

  if (R_FAILED(rc) || fileSize != gSaveData.saveFiles.sizeof) {
    //assert(0, "either couldn't get save file size or it mismatches");
    return rc;
  }

  uint bytesRead;
  rc = FSFILE_Read(fileHandle, &bytesRead, 0, &gSaveData.saveFiles, gSaveData.saveFiles.sizeof);

  if (R_FAILED(rc) || bytesRead != gSaveData.saveFiles.sizeof) {
    assert(0, "couldn't read");
    return rc;
  }

  return 0;
}

Result saveGameCreate() {
  Result rc;

  version (Output_CIA) {
    rc = FSUSER_FormatSaveData(SAVE_ARCHIVE_ID, EMPTY_PATH, 512, 7, 7, 7, 7, false);

    if (R_FAILED(rc)) {
      printf("\x1b[15;1Herror: %08X\x1b[K", rc);
      assert(0, "couldn't format");
      return rc;
    }
  }

  FS_Archive archiveHandle;
  rc = FSUSER_OpenArchive(&archiveHandle, SAVE_ARCHIVE_ID, EMPTY_PATH);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "couldn't open archive");
    return rc;
  }

  version (Output_3DSX) {
    rc = FSUSER_CreateDirectory(archiveHandle, SAVE_DIR_PATH, FS_ATTRIBUTE_DIRECTORY);

    if (R_FAILED(rc)) {
      printf("\x1b[15;1Herror: %08X\x1b[K", rc);
      assert(0, "couldn't create directory");
      return rc;
    }
  }

  rc = FSUSER_CreateFile(archiveHandle, SAVE_PATH, 0, gSaveData.saveFiles.sizeof);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "couldn't create file");
    return rc;
  }

  FSUSER_CloseArchive(archiveHandle);

  return saveGames();
}

Result saveGames() {
  FS_Archive archiveHandle;

  Result rc = FSUSER_OpenArchive(&archiveHandle, SAVE_ARCHIVE_ID, EMPTY_PATH);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "couldn't open archive");
    return rc;
  }

  scope (exit) FSUSER_CloseArchive(archiveHandle);

  Handle fileHandle;

  rc = FSUSER_OpenFile(&fileHandle, archiveHandle, SAVE_PATH, FS_OPEN_WRITE, 0);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "couldn't open file");
    return rc;
  }

  scope (exit) FSFILE_Close(fileHandle);

  size_t bytesWritten;
  rc = FSFILE_Write(fileHandle, &bytesWritten, 0, &gSaveData.saveFiles, gSaveData.saveFiles.sizeof, 0);

  if (R_FAILED(rc)) {
    printf("\x1b[15;1Herror: %08X\x1b[K", rc);
    assert(0, "couldn't write file");
    return rc;
  }

  return 0;
}

void saveGameSelect(size_t saveNum) {
  assert(saveNum < gSaveData.saveFiles.length);
  gSaveData.currentSave = &gSaveData.saveFiles[saveNum];
}