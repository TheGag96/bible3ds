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

Unfortunately, we can't just add any translation due to copyright concerns.

**Note**: Need to actually add an options menu to change the translation...!

## Compiling

LDC has made this process simpler!

First, go [install devkitPro](https://devkitpro.org/wiki/Getting_Started) like normal. Make sure to install 3DS support!

Then, clone this repo.

```sh
git clone https://github.com/TheGag96/bible3ds
```

Go download/install the latest version of [LDC](https://github.com/ldc-developers/ldc). Make sure to add the `bin` folder to your path.

I've forked tex3ds, so go ahead and fetch its submodule:

```sh
git submodule update --init --recursive
```

Go try and build it. You may need to grab extra dependencies? Please contact me if you have trouble with this.

```sh
cd tools/tex3ds
./autogen.sh
./configure
make
mv tex3ds tex3ds.exe  # <-- do this line if on Linux/Mac only
cd ../../             # go back to root folder
```

Then, finally (and for every subsequent time building)...

```sh
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