//
//  URL+duration.swift
//  SwiftWaveform
//
//  Created by Lu Ai on 2025/11/29.
//

import AVFoundation
import FFmpegKitSPM
import Foundation

extension URL {
    /// 使用 AVURLAssetPreferPreciseDurationAndTimingKey 获取精确的音频时长
    public func audioDuration() async throws -> Double? {
        let options = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        let asset = AVURLAsset(url: self, options: options)

        // Load duration asynchronously
        let duration = try await asset.load(.duration)

        // Check if duration is valid
        guard duration.isValid, !duration.isIndefinite else {
            return nil
        }

        // Convert CMTime to seconds
        return duration.seconds
    }

    /// 使用FFmpeg通过seek到最后一帧获取精确的音频时长
    public func preciseDuration() throws -> Double {
        let path = self.path(percentEncoded: false)

        // 打开输入文件
        var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&fmtCtx, path, nil, nil) >= 0 else {
            throw WaveformError.fileNotFound(path)
        }
        defer { avformat_close_input(&fmtCtx) }

        guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
            throw WaveformError.decodeFailed("Cannot find stream info")
        }

        // 查找最佳音频流
        let audioStreamIndex = av_find_best_stream(fmtCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        guard audioStreamIndex >= 0 else {
            throw WaveformError.noAudioStream
        }

        let stream = fmtCtx!.pointee.streams[Int(audioStreamIndex)]!
        let timeBase = stream.pointee.time_base

        // Seek到文件末尾，AVSEEK_FLAG_BACKWARD 会让它定位到最后一个可用的关键帧
        av_seek_frame(fmtCtx, Int32(audioStreamIndex), Int64.max, AVSEEK_FLAG_BACKWARD)

        // 分配packet
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        guard packet != nil else {
            throw WaveformError.decodeFailed("Cannot allocate packet")
        }
        defer { av_packet_free(&packet) }

        // 读取最后几个packet，找到最大的pts + duration
        var maxEndTime: Int64 = 0

        while av_read_frame(fmtCtx, packet) >= 0 {
            defer { av_packet_unref(packet) }

            if packet!.pointee.stream_index == Int32(audioStreamIndex) {
                let pts = packet!.pointee.pts
                let duration = packet!.pointee.duration

                if pts != Int64(bitPattern: UInt64(0x8000000000000000)) { // AV_NOPTS_VALUE
                    let endTime = pts + duration
                    if endTime > maxEndTime {
                        maxEndTime = endTime
                    }
                }
            }
        }

        // 转换为秒
        return Double(maxEndTime) * av_q2d(timeBase)
    }
}
