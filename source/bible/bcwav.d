module bible.bcwav;

import ctru.ndsp.ndsp;

@nogc: nothrow:

struct BcwavHeader {
  enum char[4] MAGIC = "CWAV";
  enum Endianness : ushort {
    little = 0xFEFF,
    big    = 0xFFFE,
  }
  enum ushort HEADER_SIZE = 0x40;
  enum uint VERSION = 0x02010000;
  enum ushort NUMBER_OF_BLOCKS = 2;

  char[4] magic = MAGIC;
  Endianness endianness;
  ushort headerSize = HEADER_SIZE;
  uint version_ = VERSION;
  uint fileSize;
  ushort numberOfBlocks = NUMBER_OF_BLOCKS;
  ushort reserved;
  SizedReference infoBlockReference;
  SizedReference dataBlockReference;
}

struct BcwavBlockHeader {
  enum char[4] INFO_MAGIC = "INFO";
  enum char[4] DATA_MAGIC = "DATA";

  char[4] magic;
  uint size;
}

struct BcwavInfoBlock {
  enum Encoding : ubyte {
    pcm8 = 0,
    pcm16,
    dsp_adpcm,
    ima_adpcm,
  }

  enum Loop : ubyte {
    dont_loop = 0,
    loop
  }

  BcwavBlockHeader blockHeader;
  Encoding encoding;
  Loop loop;
  ushort padding;
  uint sampleRate;
  uint loopStartFrame;
  uint loopEndFrame;
  uint reserved;
  ReferenceTable channelInfos;
  //entries follow, then DSP/IMA ADPCM entries
}

struct BcwavChannelInfo {
  Reference samples;
  Reference adpcmInfo; //relative to samples field
  uint reserved;
}

struct BcwavDspAdpcmInfo {
  //struct Context {
  //  ubyte predictorAndScale;
  //  ubyte reserved;
  //  short previousSample;
  //  short secondPreviousSample;
  //}

  ushort[16] coefficients;
  ndspAdpcmData context;
  ndspAdpcmData loopContext;
  ushort padding;
}

struct BcwavImaAdpcmInfo {
  struct Context {
    ushort data;
    ubyte tableIndex;
    ubyte padding;
  }

  Context context;
  Context loopContext;
}

struct BcwavDataBlock { //aligned to 0x20 bytes
  struct Header {
    uint magic;
    uint size;
  }

  Header header;
  ubyte[0] data; //data of header.size-8 follows
}

struct Reference {
  enum uint NULL_OFFSET = 0xFFFFFFFF;
  enum ReferenceType : ushort {
    dsp_adpcm_info = 0x0300,
    ima_adpcm_info = 0x0301,
    sample_data    = 0x1F00,
    info_block     = 0x7000,
    data_block     = 0x7001,
    channel_info   = 0x7100,
  }

  ReferenceType typeId;
  ushort padding;
  uint offset;
}

struct SizedReference {
  Reference reference;
  uint size;
}

struct ReferenceTable {
  uint count;
  Reference[0] references;
}

struct Bcwav {
  struct Channel {
    ubyte* samples;
    BcwavDspAdpcmInfo* adpcmInfo;
  }
  ubyte[] bytes;
  short[] samples;
  BcwavHeader* header;
  BcwavInfoBlock* info;
  BcwavDataBlock* data;
  BcwavInfoBlock.Encoding encoding;
  Channel[2] channels;
  ubyte numChannels;
}

Bcwav parseBcwav(ubyte[] bytes) {
  Bcwav result;
  result.bytes = bytes;

  assert(bytes.length > BcwavHeader.sizeof);

  auto header = cast(BcwavHeader*) bytes.ptr;
  result.header = header;
  assert(header.magic == BcwavHeader.MAGIC);

  auto infoBlock = cast(BcwavInfoBlock*) (bytes.ptr + header.infoBlockReference.reference.offset);
  result.encoding = infoBlock.encoding;

  auto dataBlock = cast(BcwavDataBlock*) (bytes.ptr + header.dataBlockReference.reference.offset);
  result.info = infoBlock;
  result.data = dataBlock;

  result.numChannels = cast(ubyte) infoBlock.channelInfos.count;

  foreach (i; 0..result.numChannels) {
    auto reference = cast(Reference*) (cast(ubyte*) (&infoBlock.channelInfos.count) + 4 + Reference.sizeof * i);
    auto channelInfo = cast(BcwavChannelInfo*) (cast(ubyte*) (&infoBlock.channelInfos.count) + reference.offset);
    result.channels[i].samples = cast(ubyte*) &dataBlock.data + channelInfo.samples.offset;

    if (infoBlock.encoding == BcwavInfoBlock.Encoding.dsp_adpcm || infoBlock.encoding == BcwavInfoBlock.Encoding.ima_adpcm) {
      result.channels[i].adpcmInfo = cast(BcwavDspAdpcmInfo*) (cast(ubyte*) &channelInfo.samples + channelInfo.adpcmInfo.offset);
    }
  }

  return result;
}