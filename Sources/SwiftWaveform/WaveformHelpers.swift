import Accelerate
import FFmpegKitSPM
import Foundation

// MARK: - Helper Functions

extension WaveformExtractor {
    func findAudioStream(fmtCtx: UnsafeMutablePointer<AVFormatContext>) throws -> Int {
        let nbStreams = Int(fmtCtx.pointee.nb_streams)
        for i in 0 ..< nbStreams {
            if let stream = fmtCtx.pointee.streams[i],
               let codecParams = stream.pointee.codecpar,
               codecParams.pointee.codec_type == AVMEDIA_TYPE_AUDIO
            {
                return i
            }
        }
        throw WaveformError.noAudioStream
    }

    func createCodecContext(codecParams: UnsafeMutablePointer<AVCodecParameters>) throws -> UnsafeMutablePointer<AVCodecContext>? {
        guard let codec = avcodec_find_decoder(codecParams.pointee.codec_id) else {
            throw WaveformError.codecNotFound
        }

        var codecCtx: UnsafeMutablePointer<AVCodecContext>? = avcodec_alloc_context3(codec)
        guard codecCtx != nil else {
            throw WaveformError.codecOpenFailed("Cannot allocate codec context")
        }

        if avcodec_parameters_to_context(codecCtx, codecParams) < 0 {
            avcodec_free_context(&codecCtx)
            throw WaveformError.codecOpenFailed("Cannot copy codec parameters")
        }

        if avcodec_open2(codecCtx, codec, nil) < 0 {
            avcodec_free_context(&codecCtx)
            throw WaveformError.codecOpenFailed("Cannot open codec")
        }

        return codecCtx
    }

    func createResampler(codecCtx: UnsafeMutablePointer<AVCodecContext>) throws -> OpaquePointer? {
        var swrCtx: OpaquePointer?

        // Setup input channel layout
        var inChLayout = AVChannelLayout()
        av_channel_layout_copy(&inChLayout, &codecCtx.pointee.ch_layout)

        // Setup output channel layout (mono)
        var outChLayout = AVChannelLayout()
        av_channel_layout_default(&outChLayout, 1) // 1 channel = mono

        // Allocate resampler with new API - use S16 to match C++ version
        let ret = swr_alloc_set_opts2(
            &swrCtx,
            &outChLayout,
            AV_SAMPLE_FMT_S16, // Match C++ version
            Self.targetSampleRate,
            &inChLayout,
            codecCtx.pointee.sample_fmt,
            codecCtx.pointee.sample_rate,
            0,
            nil
        )

        guard ret >= 0, let ctx = swrCtx else {
            throw WaveformError.resamplerFailed
        }

        if swr_init(ctx) < 0 {
            swr_free(&swrCtx)
            throw WaveformError.resamplerFailed
        }

        return ctx
    }

    func getDuration(fmtCtx: UnsafeMutablePointer<AVFormatContext>,
                     stream: UnsafeMutablePointer<AVStream>) -> Double
    {
        if stream.pointee.duration > 0 {
            let timeBase = stream.pointee.time_base
            return Double(stream.pointee.duration) * Double(timeBase.num) / Double(timeBase.den)
        }
        if fmtCtx.pointee.duration > 0 {
            return Double(fmtCtx.pointee.duration) / Double(AV_TIME_BASE)
        }
        return 0
    }

    func processFrame(frame: UnsafeMutablePointer<AVFrame>,
                      swrCtx: OpaquePointer,
                      processor: inout StreamingWaveformProcessor) throws
    {
        let srcNbSamples = frame.pointee.nb_samples
        let dstNbSamples = swr_get_out_samples(swrCtx, srcNbSamples)

        guard dstNbSamples > 0 else { return }

        // Allocate output buffer (Int16 samples to match C++ version)
        let outputBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(dstNbSamples))
        defer { outputBuffer.deallocate() }

        // Convert to the format swr_convert expects
        var outPtr: UnsafeMutablePointer<UInt8>? = UnsafeMutableRawPointer(outputBuffer)
            .assumingMemoryBound(to: UInt8.self)

        // Get input data pointer
        let srcData = UnsafePointer<UnsafePointer<UInt8>?>(
            OpaquePointer(frame.pointee.extended_data)
        )

        let converted = swr_convert(
            swrCtx,
            &outPtr,
            dstNbSamples,
            srcData,
            srcNbSamples
        )

        if converted > 0 {
            // Batch process using Accelerate-optimized method
            processor.addSamples(outputBuffer, count: Int(converted))
        }
    }

    func processFrameForRMS(frame: UnsafeMutablePointer<AVFrame>,
                            swrCtx: OpaquePointer) -> (sumSquares: Double, count: Int)
    {
        let srcNbSamples = frame.pointee.nb_samples
        let dstNbSamples = swr_get_out_samples(swrCtx, srcNbSamples)

        guard dstNbSamples > 0 else { return (0, 0) }

        // Allocate output buffer (Int16 to match C++ version)
        let outputBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(dstNbSamples))
        defer { outputBuffer.deallocate() }

        var outPtr: UnsafeMutablePointer<UInt8>? = UnsafeMutableRawPointer(outputBuffer)
            .assumingMemoryBound(to: UInt8.self)

        // Get input data pointer
        let srcData = UnsafePointer<UnsafePointer<UInt8>?>(
            OpaquePointer(frame.pointee.extended_data)
        )

        let converted = swr_convert(
            swrCtx,
            &outPtr,
            dstNbSamples,
            srcData,
            srcNbSamples
        )

        if converted > 0 {
            // Use Accelerate for vectorized computation
            var floatBuffer = [Float](repeating: 0, count: Int(converted))
            vDSP_vflt16(outputBuffer, 1, &floatBuffer, 1, vDSP_Length(converted))

            // Normalize by 32768 and compute sum of squares
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(floatBuffer, 1, &scale, &floatBuffer, 1, vDSP_Length(converted))

            var sumSquares: Float = 0
            vDSP_svesq(floatBuffer, 1, &sumSquares, vDSP_Length(converted))

            return (Double(sumSquares), Int(converted))
        }

        return (0, 0)
    }
}
