import FFmpegKitSPM
import Foundation

// MARK: - Public Types

public struct WaveformData: Sendable {
    public let duration: Double
    public let sampleRate: Int
    public let totalSamples: Int
    public let samplesPerPoint: Int
    public let data: [Double]

    public var pointCount: Int { data.count }
}

public enum WaveformError: Error, LocalizedError {
    case fileNotFound(String)
    case noAudioStream
    case codecNotFound
    case codecOpenFailed(String)
    case resamplerFailed
    case decodeFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .fileNotFound(path): "File not found: \(path)"
        case .noAudioStream: "No audio stream found"
        case .codecNotFound: "Codec not found"
        case let .codecOpenFailed(msg): "Failed to open codec: \(msg)"
        case .resamplerFailed: "Failed to create resampler"
        case let .decodeFailed(msg): "Decode failed: \(msg)"
        case .cancelled: "Operation cancelled"
        }
    }
}

// MARK: - Cancel Flag

public final class CancelFlag: @unchecked Sendable {
    private var _cancelled = false
    private let lock = NSLock()

    public init() {}

    public func cancel() {
        lock.lock()
        _cancelled = true
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        _cancelled = false
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }
}

// MARK: - Waveform Extractor

public final class WaveformExtractor: @unchecked Sendable {
    public static let defaultPoints = 120
    public static let targetSampleRate: Int32 = 4000
    private static let amplitudeBoost: Double = 2.5 // Match C++ version

    private let cancelFlag = CancelFlag()

    public init() {}

    public func cancel() {
        cancelFlag.cancel()
    }

    public func reset() {
        cancelFlag.reset()
    }

    public var isCancelled: Bool {
        cancelFlag.isCancelled
    }

    /// Extract waveform (full decode, accurate)
    public func extract(path: String, points: Int = defaultPoints) throws -> WaveformData {
        reset()
        return try extractWaveform(path: path, points: points, fast: false)
    }

   
}

// MARK: - Private Implementation

extension WaveformExtractor {
    private func checkCancelled() throws {
        if cancelFlag.isCancelled {
            throw WaveformError.cancelled
        }
    }

    private func extractWaveform(path: String, points: Int, fast _: Bool) throws -> WaveformData {
        // Open input file
        var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        guard avformat_open_input(&fmtCtx, path, nil, nil) >= 0 else {
            throw WaveformError.fileNotFound(path)
        }
        defer { avformat_close_input(&fmtCtx) }

        guard avformat_find_stream_info(fmtCtx, nil) >= 0 else {
            throw WaveformError.decodeFailed("Cannot find stream info")
        }

        // Find audio stream
        let audioStreamIndex = try findAudioStream(fmtCtx: fmtCtx!)
        let stream = fmtCtx!.pointee.streams[audioStreamIndex]!
        let codecParams = stream.pointee.codecpar!

        // Create codec context
        var codecCtx = try createCodecContext(codecParams: codecParams)
        defer { avcodec_free_context(&codecCtx) }

        // Create resampler
        var swrCtx = try createResampler(codecCtx: codecCtx!)
        defer { swr_free(&swrCtx) }

        // Get duration
        let duration = getDuration(fmtCtx: fmtCtx!, stream: stream)

        // Allocate packet and frame
        var packet: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        guard packet != nil else {
            throw WaveformError.decodeFailed("Cannot allocate packet")
        }
        defer { av_packet_free(&packet) }

        var frame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        guard frame != nil else {
            throw WaveformError.decodeFailed("Cannot allocate frame")
        }
        defer { av_frame_free(&frame) }

        // Estimate total samples for proper distribution
        let estimatedSamples = Int(duration * Double(Self.targetSampleRate))

        // Decode and process
        var processor = StreamingWaveformProcessor(points: points, estimatedTotalSamples: estimatedSamples)
        var frameCount = 0

        while av_read_frame(fmtCtx, packet) >= 0 {
            defer { av_packet_unref(packet) }

            if packet!.pointee.stream_index != Int32(audioStreamIndex) {
                continue
            }

            // Check cancellation every 100 frames
            frameCount += 1
            if frameCount % 100 == 0 {
                try checkCancelled()
            }

            // Send packet to decoder
            if avcodec_send_packet(codecCtx, packet) < 0 {
                continue
            }

            // Receive frames
            while avcodec_receive_frame(codecCtx, frame) >= 0 {
                try processFrame(frame: frame!, swrCtx: swrCtx!, processor: &processor)
            }
        }

        // Flush decoder
        avcodec_send_packet(codecCtx, nil)
        while avcodec_receive_frame(codecCtx, frame) >= 0 {
            try processFrame(frame: frame!, swrCtx: swrCtx!, processor: &processor)
        }

        // Drain resampler (get remaining samples in resampler buffer)
        let delay = swr_get_delay(swrCtx!, Int64(codecCtx!.pointee.sample_rate))
        let pendingOut = av_rescale_rnd(delay, Int64(Self.targetSampleRate),
                                        Int64(codecCtx!.pointee.sample_rate), AV_ROUND_UP)
        if pendingOut > 0 {
            let bufferSize = Int(pendingOut) + 512
            let drainBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: bufferSize)
            defer { drainBuffer.deallocate() }

            var outPtr: UnsafeMutablePointer<UInt8>? = UnsafeMutableRawPointer(drainBuffer)
                .assumingMemoryBound(to: UInt8.self)

            let drained = swr_convert(swrCtx!, &outPtr, Int32(bufferSize), nil, 0)
            if drained > 0 {
                processor.addSamples(drainBuffer, count: Int(drained))
            }
        }

        return WaveformData(
            duration: duration,
            sampleRate: Int(Self.targetSampleRate),
            totalSamples: processor.totalSamples,
            samplesPerPoint: processor.samplesPerPointValue,
            data: processor.finalize()
        )
    }
}
