module bible.bible;

@nogc: nothrow:

import std.algorithm;
import std.range;
import bible.util;
import ctru.thread, ctru.synchronization;
import core.atomic;

struct OpenBook {
  char[] rawFile;
  char[][] lines;
  char[][][] chapters;
}

char[] until(char[] haystack, char needle) {
  foreach (i, c; haystack.representation) {
    if (c == needle) {
      return haystack[0..i];
    }
  }

  return [];
}

OpenBook[Book.max+1] openBibleTranslation(Arena* arena, Translation translation) {
  OpenBook[Book.max+1] result;

  foreach (book; enumRange!Book) {
    result[book] = openBibleBook(arena, translation, book);
  }

  return result;
}

OpenBook openBibleBook(Arena* arena, Translation translation, Book book) {
  OpenBook result;

  auto restore = ScopedArenaRestore(&gTempStorage);
  auto bookText = readCompressedTextFile(arena, arenaPrintf(&gTempStorage, "romfs:/bibles/%s/%s", TRANSLATION_NAMES[translation].ptr, BOOK_FILENAMES[book].ptr));
  result.rawFile = bookText;

  int numLines = bookText.representation.count('\n');
  char[][] lines = arenaPushArray!(char[])(arena, numLines);

  foreach (i, line; bookText.representation.splitter('\n').enumerate) {
    if (i != numLines) lines[i] = cast(char[])line;
  }

  //hackily convert all lines to null-terminated strings so that C2D text functions work per-line.
  foreach (ref c; bookText.representation) {
    if (c == '\n') c = '\0';
  }

  result.lines = lines;

  int numChapters = 0;
  char[] lastChapter;
  foreach (line; lines[1..$]) { //skip heading
    auto chapter = line[1..$].until(':');
    if (chapter != lastChapter) {
      lastChapter = chapter;
      numChapters++;
    }
  }

  char[][][] chapters = arenaPushArray!(char[][])(arena, numChapters+1);

  lastChapter = [];
  size_t chapterStart = 0;
  int curChapter = 0;
  foreach (i, line; lines) {
    if (i == 0) continue; //skip heading

    auto chapter = line[1..$].until(':');
    if (chapter != lastChapter) {
      lastChapter = chapter;
      chapters[curChapter] = lines[chapterStart..i];
      chapterStart = i;
      curChapter++;
    }
  }
  chapters[$-1] = lines[chapterStart..$];

  result.chapters = chapters;

  return result;
}

struct BibleLoadData {
  Thread threadHandle;

  // In
  LightSemaphore inSync;
  Translation translation;

  // Out
  LightSemaphore outSync;
  bool loadDone;  // Access atomically
  OpenBook[Book.max+1] books;
  Arena bibleArena;
}

extern(C) void bibleLoadThread(void* data) {
  auto loadData = cast(BibleLoadData*) data;

  gTempStorage        = arenaMake(1*1024);
  loadData.bibleArena = arenaMake(16*1024*1024);

  while (true) {
    // Wait for command to start a load
    LightSemaphore_Acquire(&loadData.inSync,  1);
    auto translation = atomicLoad!(MemoryOrder.acq)(loadData.translation);

    // Load the entire translation from storage. This can take a long time!
    arenaClear(&loadData.bibleArena);
    loadData.books = openBibleTranslation(&loadData.bibleArena, translation);

    // Signal the loaded data is now valid
    LightSemaphore_Release(&loadData.outSync, 1);

    arenaClear(&gTempStorage);
  }
}

void startAsyncBibleLoad(BibleLoadData* bible, Translation translation) {
  bible.translation = translation;

  if (bible.threadHandle == null) {
    LightSemaphore_Init(&bible.inSync,  initial_count :  1, max_count : 1);
    LightSemaphore_Init(&bible.outSync, initial_count : -1, max_count : 1);
    bible.threadHandle = threadCreate(&bibleLoadThread, bible, 16*1024, 0x31, -2, true);
  }
  else {
    // @Blocking: Last Bible load most complete before we can queue another
    LightSemaphore_Acquire(&bible.outSync, 0);
    LightSemaphore_Release(&bible.outSync, -1);
    LightSemaphore_Release(&bible.inSync,   1);
  }
}

void waitAsyncBibleLoad(BibleLoadData* bible) {
  LightSemaphore_Acquire(&bible.outSync, 0);
}

enum Translation : ubyte {
  asv,
  bbe,
  kjv,
  web,
  ylt,
}

static immutable string[enumCount!Translation] TRANSLATION_NAMES = arrayOfEnum!(Translation, string)(
  asv : "asv",
  bbe : "bbe",
  kjv : "kjv",
  web : "web",
  ylt : "ylt",
);

static immutable string[enumCount!Translation] TRANSLATION_NAMES_LONG = arrayOfEnum!(Translation, string)(
  asv : "American Standard Version",
  bbe : "Bible in Basic English",
  kjv : "King James Version",
  web : "World English Bible",
  ylt : "Young's Literal Translation",
);

enum Book : ubyte {
  Genesis,
  Exodus,
  Leviticus,
  Numbers,
  Deuteronomy,
  Joshua,
  Judges,
  Ruth,
  _1_Samuel,
  _2_Samuel,
  _1_Kings,
  _2_Kings,
  _1_Chronicles,
  _2_Chronicles,
  Ezra,
  Nehemiah,
  Esther,
  Job,
  Psalms,
  Proverbs,
  Ecclesiastes,
  Song_of_Solomon,
  Isaiah,
  Jeremiah,
  Lamentations,
  Ezekiel,
  Daniel,
  Hosea,
  Joel,
  Amos,
  Obadiah,
  Jonah,
  Micah,
  Nahum,
  Habakkuk,
  Zephaniah,
  Haggai,
  Zechariah,
  Malachi,
  Matthew,
  Mark,
  Luke,
  John,
  Acts,
  Romans,
  _1_Corinthians,
  _2_Corinthians,
  Galatians,
  Ephesians,
  Philippians,
  Colossians,
  _1_Thessalonians,
  _2_Thessalonians,
  _1_Timothy,
  _2_Timothy,
  Titus,
  Philemon,
  Hebrews,
  James,
  _1_Peter,
  _2_Peter,
  _1_John,
  _2_John,
  _3_John,
  Jude,
  Revelation,
}

static immutable string[] BOOK_FILENAMES = [
  Book.Genesis          : "1 Genesis.lz11",
  Book.Exodus           : "2 Exodus.lz11",
  Book.Leviticus        : "3 Leviticus.lz11",
  Book.Numbers          : "4 Numbers.lz11",
  Book.Deuteronomy      : "5 Deuteronomy.lz11",
  Book.Joshua           : "6 Joshua.lz11",
  Book.Judges           : "7 Judges.lz11",
  Book.Ruth             : "8 Ruth.lz11",
  Book._1_Samuel        : "9 1 Samuel.lz11",
  Book._2_Samuel        : "10 2 Samuel.lz11",
  Book._1_Kings         : "11 1 Kings.lz11",
  Book._2_Kings         : "12 2 Kings.lz11",
  Book._1_Chronicles    : "13 1 Chronicles.lz11",
  Book._2_Chronicles    : "14 2 Chronicles.lz11",
  Book.Ezra             : "15 Ezra.lz11",
  Book.Nehemiah         : "16 Nehemiah.lz11",
  Book.Esther           : "17 Esther.lz11",
  Book.Job              : "18 Job.lz11",
  Book.Psalms           : "19 Psalms.lz11",
  Book.Proverbs         : "20 Proverbs.lz11",
  Book.Ecclesiastes     : "21 Ecclesiastes.lz11",
  Book.Song_of_Solomon  : "22 Song of Solomon.lz11",
  Book.Isaiah           : "23 Isaiah.lz11",
  Book.Jeremiah         : "24 Jeremiah.lz11",
  Book.Lamentations     : "25 Lamentations.lz11",
  Book.Ezekiel          : "26 Ezekiel.lz11",
  Book.Daniel           : "27 Daniel.lz11",
  Book.Hosea            : "28 Hosea.lz11",
  Book.Joel             : "29 Joel.lz11",
  Book.Amos             : "30 Amos.lz11",
  Book.Obadiah          : "31 Obadiah.lz11",
  Book.Jonah            : "32 Jonah.lz11",
  Book.Micah            : "33 Micah.lz11",
  Book.Nahum            : "34 Nahum.lz11",
  Book.Habakkuk         : "35 Habakkuk.lz11",
  Book.Zephaniah        : "36 Zephaniah.lz11",
  Book.Haggai           : "37 Haggai.lz11",
  Book.Zechariah        : "38 Zechariah.lz11",
  Book.Malachi          : "39 Malachi.lz11",
  Book.Matthew          : "40 Matthew.lz11",
  Book.Mark             : "41 Mark.lz11",
  Book.Luke             : "42 Luke.lz11",
  Book.John             : "43 John.lz11",
  Book.Acts             : "44 Acts.lz11",
  Book.Romans           : "45 Romans.lz11",
  Book._1_Corinthians   : "46 1 Corinthians.lz11",
  Book._2_Corinthians   : "47 2 Corinthians.lz11",
  Book.Galatians        : "48 Galatians.lz11",
  Book.Ephesians        : "49 Ephesians.lz11",
  Book.Philippians      : "50 Philippians.lz11",
  Book.Colossians       : "51 Colossians.lz11",
  Book._1_Thessalonians : "52 1 Thessalonians.lz11",
  Book._2_Thessalonians : "53 2 Thessalonians.lz11",
  Book._1_Timothy       : "54 1 Timothy.lz11",
  Book._2_Timothy       : "55 2 Timothy.lz11",
  Book.Titus            : "56 Titus.lz11",
  Book.Philemon         : "57 Philemon.lz11",
  Book.Hebrews          : "58 Hebrews.lz11",
  Book.James            : "59 James.lz11",
  Book._1_Peter         : "60 1 Peter.lz11",
  Book._2_Peter         : "61 2 Peter.lz11",
  Book._1_John          : "62 1 John.lz11",
  Book._2_John          : "63 2 John.lz11",
  Book._3_John          : "64 3 John.lz11",
  Book.Jude             : "65 Jude.lz11",
  Book.Revelation       : "66 Revelation.lz11",
];

static immutable string[] BOOK_NAMES = [
  Book.Genesis          : "Genesis",
  Book.Exodus           : "Exodus",
  Book.Leviticus        : "Leviticus",
  Book.Numbers          : "Numbers",
  Book.Deuteronomy      : "Deuteronomy",
  Book.Joshua           : "Joshua",
  Book.Judges           : "Judges",
  Book.Ruth             : "Ruth",
  Book._1_Samuel        : "1 Samuel",
  Book._2_Samuel        : "2 Samuel",
  Book._1_Kings         : "1 Kings",
  Book._2_Kings         : "2 Kings",
  Book._1_Chronicles    : "1 Chronicles",
  Book._2_Chronicles    : "2 Chronicles",
  Book.Ezra             : "Ezra",
  Book.Nehemiah         : "Nehemiah",
  Book.Esther           : "Esther",
  Book.Job              : "Job",
  Book.Psalms           : "Psalms",
  Book.Proverbs         : "Proverbs",
  Book.Ecclesiastes     : "Ecclesiastes",
  Book.Song_of_Solomon  : "Song of Solomon",
  Book.Isaiah           : "Isaiah",
  Book.Jeremiah         : "Jeremiah",
  Book.Lamentations     : "Lamentations",
  Book.Ezekiel          : "Ezekiel",
  Book.Daniel           : "Daniel",
  Book.Hosea            : "Hosea",
  Book.Joel             : "Joel",
  Book.Amos             : "Amos",
  Book.Obadiah          : "Obadiah",
  Book.Jonah            : "Jonah",
  Book.Micah            : "Micah",
  Book.Nahum            : "Nahum",
  Book.Habakkuk         : "Habakkuk",
  Book.Zephaniah        : "Zephaniah",
  Book.Haggai           : "Haggai",
  Book.Zechariah        : "Zechariah",
  Book.Malachi          : "Malachi",
  Book.Matthew          : "Matthew",
  Book.Mark             : "Mark",
  Book.Luke             : "Luke",
  Book.John             : "John",
  Book.Acts             : "Acts",
  Book.Romans           : "Romans",
  Book._1_Corinthians   : "1 Corinthians",
  Book._2_Corinthians   : "2 Corinthians",
  Book.Galatians        : "Galatians",
  Book.Ephesians        : "Ephesians",
  Book.Philippians      : "Philippians",
  Book.Colossians       : "Colossians",
  Book._1_Thessalonians : "1 Thessalonians",
  Book._2_Thessalonians : "2 Thessalonians",
  Book._1_Timothy       : "1 Timothy",
  Book._2_Timothy       : "2 Timothy",
  Book.Titus            : "Titus",
  Book.Philemon         : "Philemon",
  Book.Hebrews          : "Hebrews",
  Book.James            : "James",
  Book._1_Peter         : "1 Peter",
  Book._2_Peter         : "2 Peter",
  Book._1_John          : "1 John",
  Book._2_John          : "2 John",
  Book._3_John          : "3 John",
  Book.Jude             : "Jude",
  Book.Revelation       : "Revelation",
];