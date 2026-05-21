# Bible for 3DS

<img src="screenshot.png" width="400" alt="Screenshot">

This started as both a devotional project and an attempt at faithfully recreating the 3DS's UI style. When done, this app should look and feel close to an official 3DS one.

## Translations supported

Basically just all the versions from @scrollmapper's [`bible_databases`](https://github.com/scrollmapper/bible_databases) repo:

* ASV
* BBE
* KJV
* WEB
* YLT
* ESV (manual steps required)

Unfortunately, we can't just add any translation due to copyright concerns. However, I do provide a script that can take a [free downloadble EPUB of the ESV](https://www.crossway.org/books/esv-classic-reference-bible-ebook/) and transform it into the crummy text format I support. Checkout the `esv` branch, and run:

```bash
python esv_epub_to_txt.py path/to/your_epub.py
```
...and then compile (see below). I apologize for the script being fairly slow. It's possible other EPUBs of the ESV will work with the script, but I have not tried any others. (I should probably make it so you don't have to compile a separate branch to add your own copy.)

## Compiling

First, go [install devkitPro](https://devkitpro.org/wiki/Getting_Started) like normal. Make sure to install 3DS support!

Also, go download/install the latest version of [LDC](https://github.com/ldc-developers/ldc). Make sure to add the `bin` folder to your path.

Then:

```sh
git clone https://github.com/TheGag96/bible3ds
make BUILD_TYPE=RELEASE -j8  # or DEBUG_FAST or DEBUG_SLOW
```

## Thanks to...

* @scrollmapper's [`bible_databases`](https://github.com/scrollmapper/bible_databases) for the plaintext Bibles
* Wild for his minimal object.d from [PowerNex](https://github.com/PowerNex/PowerNex)
* [DevkitPro](https://devkitpro.org/)
* The devs of [libctru](https://github.com/smealum/ctrulib)
* The devs of [citro3d](https://github.com/fincs/citro3d)
* The devs of [citro2d](https://github.com/fincs/citro2d)
* [dstep](https://github.com/jacob-carlborg/dstep) for C header file conversion