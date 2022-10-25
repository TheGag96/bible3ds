module ogg.config_types;

import core.stdc.config;

extern (C): nothrow: @nogc:

/* these are filled in by configure */
enum INCLUDE_INTTYPES_H = 1;
enum INCLUDE_STDINT_H = 1;
enum INCLUDE_SYS_TYPES_H = 1;

alias ogg_int16_t = short;
alias ogg_uint16_t = ushort;
alias ogg_int32_t = int;
alias ogg_uint32_t = uint;
alias ogg_int64_t = c_long;

