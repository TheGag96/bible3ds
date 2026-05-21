# This is a very thrown-together script that takes an ESV EPUB and turns it into the text file format my Bible app
# needs. It does an okay job of keeping the format correct but there are some imperfections, like multi-paragraph
# quotations, "She" and "He" section markers in Song of Solomon, etc.

from bs4 import *
from bs4.element import *
from pathlib import *
import re
import sys
import zipfile
import subprocess

BOOK_FILENAMES = [
  "1 Genesis.txt",
  "2 Exodus.txt",
  "3 Leviticus.txt",
  "4 Numbers.txt",
  "5 Deuteronomy.txt",
  "6 Joshua.txt",
  "7 Judges.txt",
  "8 Ruth.txt",
  "9 1 Samuel.txt",
  "10 2 Samuel.txt",
  "11 1 Kings.txt",
  "12 2 Kings.txt",
  "13 1 Chronicles.txt",
  "14 2 Chronicles.txt",
  "15 Ezra.txt",
  "16 Nehemiah.txt",
  "17 Esther.txt",
  "18 Job.txt",
  "19 Psalms.txt",
  "20 Proverbs.txt",
  "21 Ecclesiastes.txt",
  "22 Song of Solomon.txt",
  "23 Isaiah.txt",
  "24 Jeremiah.txt",
  "25 Lamentations.txt",
  "26 Ezekiel.txt",
  "27 Daniel.txt",
  "28 Hosea.txt",
  "29 Joel.txt",
  "30 Amos.txt",
  "31 Obadiah.txt",
  "32 Jonah.txt",
  "33 Micah.txt",
  "34 Nahum.txt",
  "35 Habakkuk.txt",
  "36 Zephaniah.txt",
  "37 Haggai.txt",
  "38 Zechariah.txt",
  "39 Malachi.txt",
  "40 Matthew.txt",
  "41 Mark.txt",
  "42 Luke.txt",
  "43 John.txt",
  "44 Acts.txt",
  "45 Romans.txt",
  "46 1 Corinthians.txt",
  "47 2 Corinthians.txt",
  "48 Galatians.txt",
  "49 Ephesians.txt",
  "50 Philippians.txt",
  "51 Colossians.txt",
  "52 1 Thessalonians.txt",
  "53 2 Thessalonians.txt",
  "54 1 Timothy.txt",
  "55 2 Timothy.txt",
  "56 Titus.txt",
  "57 Philemon.txt",
  "58 Hebrews.txt",
  "59 James.txt",
  "60 1 Peter.txt",
  "61 2 Peter.txt",
  "62 1 John.txt",
  "63 2 John.txt",
  "64 3 John.txt",
  "65 Jude.txt",
  "66 Revelation.txt",
]

BOOK_NAMES = [
  "Genesis",
  "Exodus",
  "Leviticus",
  "Numbers",
  "Deuteronomy",
  "Joshua",
  "Judges",
  "Ruth",
  "1 Samuel",
  "2 Samuel",
  "1 Kings",
  "2 Kings",
  "1 Chronicles",
  "2 Chronicles",
  "Ezra",
  "Nehemiah",
  "Esther",
  "Job",
  "Psalms",
  "Proverbs",
  "Ecclesiastes",
  "Song of Solomon",
  "Isaiah",
  "Jeremiah",
  "Lamentations",
  "Ezekiel",
  "Daniel",
  "Hosea",
  "Joel",
  "Amos",
  "Obadiah",
  "Jonah",
  "Micah",
  "Nahum",
  "Habakkuk",
  "Zephaniah",
  "Haggai",
  "Zechariah",
  "Malachi",
  "Matthew",
  "Mark",
  "Luke",
  "John",
  "Acts",
  "Romans",
  "1 Corinthians",
  "2 Corinthians",
  "Galatians",
  "Ephesians",
  "Philippians",
  "Colossians",
  "1 Thessalonians",
  "2 Thessalonians",
  "1 Timothy",
  "2 Timothy",
  "Titus",
  "Philemon",
  "Hebrews",
  "James",
  "1 Peter",
  "2 Peter",
  "1 John",
  "2 John",
  "3 John",
  "Jude",
  "Revelation",
]

def read_entire_file(path):
  with open(path, 'r', newline = '\n', encoding = 'utf-8') as file:
    return file.read()

if len(sys.argv) != 2:
  print(f"Usage: {Path(__file__).name} your_esv.epub")
  exit(1)

path_epub = Path(sys.argv[1])

dir_working   = Path('./working')
dir_extracted = dir_working / 'esv'
dir_txt       = dir_working / 'esv_out'
dir_dest      = Path('./romfs/bibles/esv')

dir_extracted.mkdir(parents = True, exist_ok = True)
dir_txt.mkdir(parents = True, exist_ok = True)
dir_dest.mkdir(parents = True, exist_ok = True)

with zipfile.ZipFile(path_epub, 'r') as zip_ref:
  zip_ref.extractall(dir_extracted)

folder_texts = dir_extracted / 'OEBPS' / 'Text'
re_verse_class = r'h\d+'

for i in range(66):
  book_paths = [x for x in folder_texts.rglob('b%02d.*.text.xhtml' % (i+1))]

  cur_chapter = 0
  cur_verse   = 0
  last_verse_id = ''

  print(BOOK_FILENAMES[i])

  with open(dir_txt / BOOK_FILENAMES[i], 'w', newline = '\n', encoding = 'utf-8') as out:
    out.write(f'{BOOK_NAMES[i]} - English Standard Version 2016 (ESV)\n')

    for book_path in book_paths:
      html_text = read_entire_file(book_path)
      html_tree = BeautifulSoup(html_text, 'lxml')

      for span in html_tree.find_all('span', class_ = ['crossref', 'footnote', 'book-name']):
        span.decompose()

      for node in html_tree.find_all('header'):
        node.decompose()

      for span in html_tree.find_all('span', class_ = ['h', False]):
        span.unwrap()

      for node in html_tree.find_all('p'):
        node.unwrap()


      for span in html_tree.find_all('span'):
        class_child = span.get('class')
        class_child = class_child[0] if class_child is not None else class_child
        if class_child is not None and re.search(re_verse_class, class_child):
          if len(span.contents) > 0:
            copied = html_tree.new_tag(span.name, attrs = span.attrs)
            span.contents[0].insert_before(copied)
            span.unwrap()

      for section in html_tree.find_all('section'):
        if section.get('epub:type') == 'chapter':
          for child in section.children:
            class_child = child.get('class') if type(child) != NavigableString else None
            class_child = class_child[0] if class_child is not None else class_child

            if class_child is not None and re.search(re_verse_class, class_child):
              if class_child == last_verse_id:
                out.write(' ')
              last_verse_id = class_child

            if class_child == 'chapter-num':
              cur_chapter = int(child.text)
              cur_verse   = 1
              if cur_chapter != 1:
                out.write(f'\n')
              out.write(f'[{cur_chapter}:{cur_verse}] ')
              verse_start = True
            elif class_child == 'verse-num':
              cur_verse = int(child.text)
              out.write(f'\n[{cur_chapter}:{cur_verse}] ')
              verse_start = True
            elif cur_chapter != 0 and cur_verse != 0:
              # if not verse_start:
              #   out.write(' ')
              # breakpoint()
              out.write(child.text.replace('\n', ''))
              verse_start = False

for filename_book in BOOK_FILENAMES:
  path_uncomp = dir_txt / filename_book
  path_comp   = (dir_dest / filename_book).with_suffix('.lz11')

  subprocess.run(['gbalzss', '--lz11', 'e', str(path_uncomp), str(path_comp)])

