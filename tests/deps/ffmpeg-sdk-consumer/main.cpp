// FFmpeg's version headers compile as C++ inside extern "C" (M4 design D3); nothing of FFmpeg is
// linked.
#include <cstdint>
#include <cstdio>

extern "C" {
#include <libavcodec/version_major.h>
#include <libavformat/version_major.h>
#include <libavutil/version.h>
}

int main() {
    std::printf("avutil %d avcodec %d avformat %d\n", LIBAVUTIL_VERSION_MAJOR,
                LIBAVCODEC_VERSION_MAJOR, LIBAVFORMAT_VERSION_MAJOR);
    return 0;
}
