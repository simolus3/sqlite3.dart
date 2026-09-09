// When compiling for Linux, we force-include this file as a hack to avoid
// references to __isoc23_strtol which is unsupported on older glibc versions.
// Inspired by https://patchwork.yoctoproject.org/project/oe-core/patch/20230817140712.681363-1-richard.purdie@linuxfoundation.org/

#ifndef _GNU_SOURCE
#define _GNU_SOURCE 1
#endif
#include <features.h>

#undef  __GLIBC_USE_C23_STRTOL
#define __GLIBC_USE_C23_STRTOL 0
