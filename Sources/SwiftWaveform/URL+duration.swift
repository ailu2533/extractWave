//
//  URL+duration.swift
//  SwiftWaveform
//
//  Created by Lu Ai on 2025/11/29.
//

import AVFoundation
import FFmpegKitSPM
import Foundation

private let avNoPtsValue = Int64(bitPattern: UInt64(0x8000000000000000))
private let avTimeBase: Double = 1000000.0 // AV_TIME_BASE = 1000000 (微秒)

// wma,tta,wv,mka,voc
public extension URL {
    /// 从文件头部元数据快速获取音频时长（异步版本，推荐使用）
    /// - 在后台线程执行，避免阻塞主线程
    /// - 优先使用 AVStream.duration（流级别时长）
    /// - 备选使用 AVFormatContext.duration（容器级别时长）
    /// - 某些格式（如纯 MP3 无 Xing header）可能返回不准确的值
    /// - Returns: 时长（秒），如果无法获取则返回 nil
    func headerDuration() async throws -> Double? {
        try await Task.detached(priority: .userInitiated) {
            try self.headerDurationSync()
        }.value
    }

    /// 从文件头部元数据快速获取音频时长（同步版本）
    /// - Warning: 涉及文件 I/O，不建议在主线程调用
    /// - 优先使用 AVStream.duration（流级别时长）
    /// - 备选使用 AVFormatContext.duration（容器级别时长）
    /// - 某些格式（如纯 MP3 无 Xing header）可能返回不准确的值
    /// - Returns: 时长（秒），如果无法获取则返回 nil
    func headerDurationSync() throws -> Double? {
        let path = path(percentEncoded: false)

        // 打开输入文件
        var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&fmtCtx, path, nil, nil) >= 0 else {
            throw WaveformError.fileNotFound(path)
        }
        defer { avformat_close_input(&fmtCtx) }

        // 读取流信息（只读取头部，不扫描全文件）
        guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
            throw WaveformError.decodeFailed("Cannot find stream info")
        }

        // 查找音频流
        let audioStreamIndex = av_find_best_stream(fmtCtx, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        guard audioStreamIndex >= 0 else {
            throw WaveformError.noAudioStream
        }

        let stream = fmtCtx!.pointee.streams[Int(audioStreamIndex)]!

        // 方法1：从流的 duration 获取（更精确）
        let streamDuration = stream.pointee.duration
        if streamDuration != avNoPtsValue, streamDuration > 0 {
            let timeBase = stream.pointee.time_base
            return Double(streamDuration) * av_q2d(timeBase)
        }

        // 方法2：从容器的 duration 获取（单位是 AV_TIME_BASE，即微秒）
        let containerDuration = fmtCtx!.pointee.duration
        if containerDuration != avNoPtsValue, containerDuration > 0 {
            return Double(containerDuration) / avTimeBase
        }

        // 无法从头部获取时长
        return nil
    }

    var isAVAssetSupported: Bool {
        // Get the file's UTType
        guard let resourceValues = try? resourceValues(forKeys: [.contentTypeKey]),
              let contentType = resourceValues.contentType
        else {
            return false
        }

        // Get all supported types from AVURLAsset
        if #available(iOS 26.0, *) {
            // iOS 26.0+: audiovisualContentTypes returns [UTType]
            let supportedTypes = AVURLAsset.audiovisualContentTypes
            return supportedTypes.contains { contentType.conforms(to: $0) }
        } else {
            // Earlier versions: audiovisualTypes() returns [AVFileType]
            let supportedTypes = AVURLAsset.audiovisualTypes()
            return supportedTypes.contains { fileType in
                contentType.conforms(to: UTType(fileType.rawValue) ?? .data)
            }
        }
    }

    /// 获取音频时长
    /// - Parameter precise: 是否需要精确时长（默认为 true，可能更慢）
    public func audioDuration(precise: Bool = true) async throws -> Double? {
        let options: [String: Any]? = precise ? [AVURLAssetPreferPreciseDurationAndTimingKey: true] : nil
        let asset = AVURLAsset(url: self, options: options)

        let duration = try await asset.load(.duration)
        guard duration.isValid, !duration.isIndefinite else { return nil }
        return duration.seconds
    }

    public func preciseDuration() async throws -> Double {
        try await Task.detached(priority: .userInitiated) {
            try self.preciseDurationSync()
        }.value
    }

    /// 使用FFmpeg通过seek到最后一帧获取精确的音频时长
    /// 对于不支持seek的格式（如VOC），会扫描所有packets获取精确时长
    func preciseDurationSync() throws -> Double {
        let path = path(percentEncoded: false)

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

        // 尝试 seek 到末尾
        let seekResult = av_seek_frame(fmtCtx, Int32(audioStreamIndex), Int64.max, AVSEEK_FLAG_BACKWARD)

        // 分配packet
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        guard packet != nil else {
            throw WaveformError.decodeFailed("Cannot allocate packet")
        }
        defer { av_packet_free(&packet) }

        // 读取最后几个packet，找到最大的pts + duration
        var maxEndTime: Int64 = 0

        // 如果 seek 失败，从头开始扫描所有 packets
        if seekResult < 0 {
            // Seek 失败，重新打开文件从头扫描
            avformat_close_input(&fmtCtx)
            guard avformat_open_input(&fmtCtx, path, nil, nil) >= 0 else {
                throw WaveformError.fileNotFound(path)
            }
            guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
                throw WaveformError.decodeFailed("Cannot find stream info")
            }
        }

        while av_read_frame(fmtCtx, packet) >= 0 {
            defer { av_packet_unref(packet) }

            if packet!.pointee.stream_index == Int32(audioStreamIndex) {
                let pts = packet!.pointee.pts
                let duration = packet!.pointee.duration

                if pts != avNoPtsValue {
                    let endTime = pts + duration
                    if endTime > maxEndTime {
                        maxEndTime = endTime
                    }
                }
            }
        }

        // 如果 seek 成功但没有读取到任何 packet，说明 seek 把位置移到了文件末尾之后
        // 这种情况需要回退到扫描所有 packets（如 VOC 格式）
        if maxEndTime == 0, seekResult >= 0 {
            // 重新打开并扫描所有 packets
            avformat_close_input(&fmtCtx)
            guard avformat_open_input(&fmtCtx, path, nil, nil) >= 0 else {
                throw WaveformError.fileNotFound(path)
            }
            guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
                throw WaveformError.decodeFailed("Cannot find stream info")
            }

            while av_read_frame(fmtCtx, packet) >= 0 {
                defer { av_packet_unref(packet) }

                if packet!.pointee.stream_index == Int32(audioStreamIndex) {
                    let pts = packet!.pointee.pts
                    let duration = packet!.pointee.duration

                    if pts != avNoPtsValue {
                        let endTime = pts + duration
                        if endTime > maxEndTime {
                            maxEndTime = endTime
                        }
                    }
                }
            }
        }

        // 转换为秒
        return Double(maxEndTime) * av_q2d(timeBase)
    }
}
