import std.stdio, std.file, std.algorithm, std.range, std.conv, std.string, std.uni, std.bitmanip;

struct Location {
  Book book;
  align(1) ushort verseIndex;
}

pragma(msg, Location.sizeof);
pragma(msg, Location.alignof);

void main(string[] args) {
  writeln("Start...");
  if (args.length != 2) {
    writeln("Please give a string to search.");
    return;
  }

  bool[Location][string] wordDict;

  bool[string] commonWords;
  foreach (word; commonFilter) {
    commonWords[word] = true;
  }

  string[][Book.max+1] allVerses;

  foreach (_bookId; Book.min..Book.max+1) {
    Book bookId = cast(Book) _bookId;

    auto bookText = readText("bible_databases/txt/KJV/" ~ BOOK_FILENAMES[bookId]);
    allVerses[bookId] = bookText.lineSplitter.drop(1).array;
  }
  writeln("Loaded books...");

  foreach (_bookId; Book.min..Book.max+1) {
    Book bookId = cast(Book) _bookId;

    foreach (i, line; allVerses[bookId]) {
      auto split = line.findSplit("] ");
      auto chapterVerse = split[0][1..$].findSplit(":");

      Location location;

      location.book = bookId;
      location.verseIndex = cast(ushort) i;

      auto verse = split[2];

      auto words = verse
        .representation
        .map!(c => (c >= 'A' && c <= 'Z') ? cast(ubyte)(c + ('a'-'A')) : c)
        .filter!(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == ' ' || c == '\'')
        .map!(c => cast(immutable char) c)
        .array
        .splitter(' ')
        .filter!(x => x.length)
        .map!(x => x[$-1] == '\'' ? x[0..$-1] : x)  // try to prevent counting end of italic syntax as being part of words
        .filter!(x => x !in commonWords);

      foreach (word; words) {
        wordDict[word][location] = true;
      }
    }
  }
  writeln("Built index...");


  testSearch(wordDict, commonWords, allVerses, args[1]);
  writeln("---------");
  testSearchDumb(wordDict, commonWords, allVerses, args[1]);

  ubyte[] indexBytes;
  indexBytes.reserve(4*1024*1024);

  foreach (keyVal; wordDict.byKeyValue) {
    auto word = keyVal.key;
    auto locTable = keyVal.value;

    indexBytes ~= word;
    indexBytes ~= 0;
    indexBytes ~= nativeToLittleEndian(cast(uint) locTable.length);
    foreach (loc; locTable.byKey) {
      indexBytes ~= nativeToLittleEndian(loc.book);
      indexBytes ~= nativeToLittleEndian(loc.verseIndex);
    }
  }

  std.file.write("index.dat", indexBytes);
}

Location[] testSearch(bool[Location][string] wordDict, bool[string] commonWords, ref string[][Book.max+1] allVerses, string s) {
  auto words = s
      .representation
      .map!(c => (c >= 'A' && c <= 'Z') ? cast(ubyte)(c + ('a'-'A')) : c)
      .filter!(c => (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == ' ' || c == '\'')
      .map!(c => cast(immutable char) c)
      .array
      .splitter(' ')
      .filter!(x => x.length);

  Location[] locations;
  locations.reserve(1000);

  string[] commonWordsInSearch;

  int[Location] locOccurrences;

  int indexedWordCount = 0;
  foreach (word; words) {
    if (word in commonWords) {
      commonWordsInSearch ~= word;
    }
    else {
      indexedWordCount++;
      writeln(word);
      foreach (loc; wordDict[word].byKey) {
        locOccurrences[loc]++;
      }
    }
  }

  foreach (keyVal; locOccurrences.byKeyValue) {
    auto loc         = keyVal.key;
    auto occurrences = keyVal.value;

    if (occurrences == indexedWordCount) {
      auto verseWords = allVerses[loc.book][loc.verseIndex].splitter(' ');

      bool addLoc = true;
      foreach (word; commonWordsInSearch) {
        if (!verseWords.canFind(word)) {
          addLoc = false;
          break;
        }
      }
      if (addLoc) {
        locations ~= loc;
      }
    }
  }

  foreach (loc; locations) {
    writeln(allVerses[loc.book][loc.verseIndex]);
    writeln(loc);
  }

  return locations;
}

Location[] testSearchDumb(bool[Location][string] wordDict, bool[string] commonWords, ref string[][Book.max+1] allVerses, string s) {
  Location[] result;
  result.reserve(100);
  foreach (bookId, book; allVerses) {
    foreach (verseId, verse; book) {
      if (verse.canFind(s)) {
        result ~= Location(cast(Book) bookId, cast(ushort) verseId);
        writeln(verse);
      }
    }
  }
  return result;
}

static immutable string[] commonFilter = [
  "the",
  "of",
  "to",
  "and",
  "a",
  "in",
  "is",
  "it",
  "you",
  "that",
  "he",
  "was",
  "for",
  "on",
  "are",
  "with",
  "as",
  "i",
  "they",
  "be",
  "at",
  "have",
  "this",
  "from",
  "or",
  "had",
  "by",
  "not",
  "but",
  "what",
  "some",
  "we",
  "can",
  "out",
  "other",
  "were",
  "all",
  "there",
  "when",
  "up",
  "use",
  "your",
  "yours",
  "how",
  "said",
  "an",
  "each",
  "she",
  "which",
  "do",
  "their",
  "if",
  "will",
  "way",
  "then",
  "them",
  "would",
  "like",
  "so",
  "these",
  "see",
  "him",
  "her",
  "his",
  "hers",
  "has",
  "more",
  "day",
  "could",
  "go",
  "did",
  "no",
  "most",
  "my",
  "than",
  "who",
  "may",
  "been",
  "now",
  "find",
  "any",
  "take",
  "get",
  "made",
  "where",
  "me",
  "our",
  "o",
  "thy",
  "thee",
  "thine",
  "ye",
  "thing",
];

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
  Book.Genesis          : "1 Genesis - King James Version (KJV).txt",
  Book.Exodus           : "2 Exodus - King James Version (KJV).txt",
  Book.Leviticus        : "3 Leviticus - King James Version (KJV).txt",
  Book.Numbers          : "4 Numbers - King James Version (KJV).txt",
  Book.Deuteronomy      : "5 Deuteronomy - King James Version (KJV).txt",
  Book.Joshua           : "6 Joshua - King James Version (KJV).txt",
  Book.Judges           : "7 Judges - King James Version (KJV).txt",
  Book.Ruth             : "8 Ruth - King James Version (KJV).txt",
  Book._1_Samuel        : "9 1 Samuel - King James Version (KJV).txt",
  Book._2_Samuel        : "10 2 Samuel - King James Version (KJV).txt",
  Book._1_Kings         : "11 1 Kings - King James Version (KJV).txt",
  Book._2_Kings         : "12 2 Kings - King James Version (KJV).txt",
  Book._1_Chronicles    : "13 1 Chronicles - King James Version (KJV).txt",
  Book._2_Chronicles    : "14 2 Chronicles - King James Version (KJV).txt",
  Book.Ezra             : "15 Ezra - King James Version (KJV).txt",
  Book.Nehemiah         : "16 Nehemiah - King James Version (KJV).txt",
  Book.Esther           : "17 Esther - King James Version (KJV).txt",
  Book.Job              : "18 Job - King James Version (KJV).txt",
  Book.Psalms           : "19 Psalms - King James Version (KJV).txt",
  Book.Proverbs         : "20 Proverbs - King James Version (KJV).txt",
  Book.Ecclesiastes     : "21 Ecclesiastes - King James Version (KJV).txt",
  Book.Song_of_Solomon  : "22 Song of Solomon - King James Version (KJV).txt",
  Book.Isaiah           : "23 Isaiah - King James Version (KJV).txt",
  Book.Jeremiah         : "24 Jeremiah - King James Version (KJV).txt",
  Book.Lamentations     : "25 Lamentations - King James Version (KJV).txt",
  Book.Ezekiel          : "26 Ezekiel - King James Version (KJV).txt",
  Book.Daniel           : "27 Daniel - King James Version (KJV).txt",
  Book.Hosea            : "28 Hosea - King James Version (KJV).txt",
  Book.Joel             : "29 Joel - King James Version (KJV).txt",
  Book.Amos             : "30 Amos - King James Version (KJV).txt",
  Book.Obadiah          : "31 Obadiah - King James Version (KJV).txt",
  Book.Jonah            : "32 Jonah - King James Version (KJV).txt",
  Book.Micah            : "33 Micah - King James Version (KJV).txt",
  Book.Nahum            : "34 Nahum - King James Version (KJV).txt",
  Book.Habakkuk         : "35 Habakkuk - King James Version (KJV).txt",
  Book.Zephaniah        : "36 Zephaniah - King James Version (KJV).txt",
  Book.Haggai           : "37 Haggai - King James Version (KJV).txt",
  Book.Zechariah        : "38 Zechariah - King James Version (KJV).txt",
  Book.Malachi          : "39 Malachi - King James Version (KJV).txt",
  Book.Matthew          : "40 Matthew - King James Version (KJV).txt",
  Book.Mark             : "41 Mark - King James Version (KJV).txt",
  Book.Luke             : "42 Luke - King James Version (KJV).txt",
  Book.John             : "43 John - King James Version (KJV).txt",
  Book.Acts             : "44 Acts - King James Version (KJV).txt",
  Book.Romans           : "45 Romans - King James Version (KJV).txt",
  Book._1_Corinthians   : "46 1 Corinthians - King James Version (KJV).txt",
  Book._2_Corinthians   : "47 2 Corinthians - King James Version (KJV).txt",
  Book.Galatians        : "48 Galatians - King James Version (KJV).txt",
  Book.Ephesians        : "49 Ephesians - King James Version (KJV).txt",
  Book.Philippians      : "50 Philippians - King James Version (KJV).txt",
  Book.Colossians       : "51 Colossians - King James Version (KJV).txt",
  Book._1_Thessalonians : "52 1 Thessalonians - King James Version (KJV).txt",
  Book._2_Thessalonians : "53 2 Thessalonians - King James Version (KJV).txt",
  Book._1_Timothy       : "54 1 Timothy - King James Version (KJV).txt",
  Book._2_Timothy       : "55 2 Timothy - King James Version (KJV).txt",
  Book.Titus            : "56 Titus - King James Version (KJV).txt",
  Book.Philemon         : "57 Philemon - King James Version (KJV).txt",
  Book.Hebrews          : "58 Hebrews - King James Version (KJV).txt",
  Book.James            : "59 James - King James Version (KJV).txt",
  Book._1_Peter         : "60 1 Peter - King James Version (KJV).txt",
  Book._2_Peter         : "61 2 Peter - King James Version (KJV).txt",
  Book._1_John          : "62 1 John - King James Version (KJV).txt",
  Book._2_John          : "63 2 John - King James Version (KJV).txt",
  Book._3_John          : "64 3 John - King James Version (KJV).txt",
  Book.Jude             : "65 Jude - King James Version (KJV).txt",
  Book.Revelation       : "66 Revelation - King James Version (KJV).txt",
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