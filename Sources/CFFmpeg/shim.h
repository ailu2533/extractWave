#ifndef CFFMPEG_SHIM_H
#define CFFMPEG_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>

// Swift 无法直接访问 C 宏，需要包装成函数

static inline int ffmpeg_averror_eof(void) {
    return AVERROR_EOF;
}

static inline int ffmpeg_averror_eagain(void) {
    return AVERROR(EAGAIN);
}

static inline int64_t ffmpeg_av_nopts_value(void) {
    return (int64_t)AV_NOPTS_VALUE;
}

static inline int64_t ffmpeg_av_time_base(void) {
    return AV_TIME_BASE;
}

// FFmpeg 7.0+ uses new channel layout API
// 获取 channel layout 的 channel 数量
static inline int ffmpeg_get_nb_channels(const AVChannelLayout *layout) {
    return layout->nb_channels;
}

// 设置默认 channel layout
static inline void ffmpeg_set_default_channel_layout(AVChannelLayout *layout, int nb_channels) {
    av_channel_layout_default(layout, nb_channels);
}

// 设置 mono channel layout
static inline void ffmpeg_set_mono_channel_layout(AVChannelLayout *layout) {
    av_channel_layout_default(layout, 1);
}

// 复制 channel layout
static inline int ffmpeg_channel_layout_copy(AVChannelLayout *dst, const AVChannelLayout *src) {
    return av_channel_layout_copy(dst, src);
}

// 检查错误码
static inline int ffmpeg_is_error(int ret) {
    return ret < 0;
}

// 获取错误描述
static inline void ffmpeg_get_error_string(int errnum, char *buf, size_t buf_size) {
    av_strerror(errnum, buf, buf_size);
}

#ifdef __cplusplus
}
#endif

#endif // CFFMPEG_SHIM_H
