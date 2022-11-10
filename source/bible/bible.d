module bible.bible;

@nogc: nothrow:

import std.algorithm;
import std.string : representation;
import std.range;
import bible.util;

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

OpenBook openBibleBook(Translation translation, Book book) {
  OpenBook result;

  auto bookText = readTextFile(gTempStorage.printf("romfs:/bibles/%s/%s", TRANSLATION_NAMES[translation].ptr, BOOK_FILENAMES[book].ptr));
  result.rawFile = bookText;

  int numLines = bookText.representation.count('\n');
  char[][] lines = allocArray!(char[])(numLines);

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

  char[][][] chapters = allocArray!(char[][])(numChapters+1);

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

void closeBibleBook(OpenBook* book) {
  freeArray(book.rawFile);
  freeArray(book.lines);
  freeArray(book.chapters);
}

enum Translation {
  asv,
}

static immutable string[] TRANSLATION_NAMES = [
  Translation.asv : "asv",
];

enum Book {
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
  Book.Genesis          : "1 Genesis.txt",
  Book.Exodus           : "2 Exodus.txt",
  Book.Leviticus        : "3 Leviticus.txt",
  Book.Numbers          : "4 Numbers.txt",
  Book.Deuteronomy      : "5 Deuteronomy.txt",
  Book.Joshua           : "6 Joshua.txt",
  Book.Judges           : "7 Judges.txt",
  Book.Ruth             : "8 Ruth.txt",
  Book._1_Samuel        : "9 1 Samuel.txt",
  Book._2_Samuel        : "10 2 Samuel.txt",
  Book._1_Kings         : "11 1 Kings.txt",
  Book._2_Kings         : "12 2 Kings.txt",
  Book._1_Chronicles    : "13 1 Chronicles.txt",
  Book._2_Chronicles    : "14 2 Chronicles.txt",
  Book.Ezra             : "15 Ezra.txt",
  Book.Nehemiah         : "16 Nehemiah.txt",
  Book.Esther           : "17 Esther.txt",
  Book.Job              : "18 Job.txt",
  Book.Psalms           : "19 Psalms.txt",
  Book.Proverbs         : "20 Proverbs.txt",
  Book.Ecclesiastes     : "21 Ecclesiastes.txt",
  Book.Song_of_Solomon  : "22 Song of Solomon.txt",
  Book.Isaiah           : "23 Isaiah.txt",
  Book.Jeremiah         : "24 Jeremiah.txt",
  Book.Lamentations     : "25 Lamentations.txt",
  Book.Ezekiel          : "26 Ezekiel.txt",
  Book.Daniel           : "27 Daniel.txt",
  Book.Hosea            : "28 Hosea.txt",
  Book.Joel             : "29 Joel.txt",
  Book.Amos             : "30 Amos.txt",
  Book.Obadiah          : "31 Obadiah.txt",
  Book.Jonah            : "32 Jonah.txt",
  Book.Micah            : "33 Micah.txt",
  Book.Nahum            : "34 Nahum.txt",
  Book.Habakkuk         : "35 Habakkuk.txt",
  Book.Zephaniah        : "36 Zephaniah.txt",
  Book.Haggai           : "37 Haggai.txt",
  Book.Zechariah        : "38 Zechariah.txt",
  Book.Malachi          : "39 Malachi.txt",
  Book.Matthew          : "40 Matthew.txt",
  Book.Mark             : "41 Mark.txt",
  Book.Luke             : "42 Luke.txt",
  Book.John             : "43 John.txt",
  Book.Acts             : "44 Acts.txt",
  Book.Romans           : "45 Romans.txt",
  Book._1_Corinthians   : "46 1 Corinthians.txt",
  Book._2_Corinthians   : "47 2 Corinthians.txt",
  Book.Galatians        : "48 Galatians.txt",
  Book.Ephesians        : "49 Ephesians.txt",
  Book.Philippians      : "50 Philippians.txt",
  Book.Colossians       : "51 Colossians.txt",
  Book._1_Thessalonians : "52 1 Thessalonians.txt",
  Book._2_Thessalonians : "53 2 Thessalonians.txt",
  Book._1_Timothy       : "54 1 Timothy.txt",
  Book._2_Timothy       : "55 2 Timothy.txt",
  Book.Titus            : "56 Titus.txt",
  Book.Philemon         : "57 Philemon.txt",
  Book.Hebrews          : "58 Hebrews.txt",
  Book.James            : "59 James.txt",
  Book._1_Peter         : "60 1 Peter.txt",
  Book._2_Peter         : "61 2 Peter.txt",
  Book._1_John          : "62 1 John.txt",
  Book._2_John          : "63 2 John.txt",
  Book._3_John          : "64 3 John.txt",
  Book.Jude             : "65 Jude.txt",
  Book.Revelation       : "66 Revelation.txt",
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