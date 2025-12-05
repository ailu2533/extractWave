import Foundation
@testable import SwiftWaveform
import Testing

@Suite("WaveformExtractor Tests")
struct WaveformExtractorTests {
    // MARK: - Helper

    func testAudioURL() -> URL? {
        Bundle.module.url(forResource: "adele", withExtension: "m4a")
    }

    func largeAudioURL() -> URL? {
        Bundle.module.url(forResource: "large", withExtension: "m4a")
    }

    func someoneLikeYouURL() -> URL? {
        Bundle.module.url(forResource: "someoneLikeYou", withExtension: "aac")
    }

    // MARK: - Basic Tests

    @Test("Extract waveform from audio file")
    func extractWaveform() async throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }

        let extractor = WaveformExtractor()
        let result = try await extractor.extract(url: url)

        #expect(result.duration > 0)
        #expect(result.sampleRate == 4000)
        #expect(result.totalSamples > 0)
        #expect(result.data.count == WaveformExtractor.defaultPoints)
        #expect(result.pointCount == result.data.count)
    }

    @Test("Extract with custom points")
    func extractWithCustomPoints() async throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }

        let extractor = WaveformExtractor()
        let customPoints = 200
        let result = try await extractor.extract(url: url, points: customPoints)

        #expect(result.data.count == customPoints)
    }

    @Test("Waveform values are normalized")
    func waveformValuesNormalized() async throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }

        let extractor = WaveformExtractor()
        let result = try await extractor.extract(url: url)

        for value in result.data {
            #expect(value >= 0.0 && value <= 1.0, "Value \(value) is out of range [0, 1]")
        }
    }

    // MARK: - Error Tests

    @Test("File not found throws error")
    func fileNotFound() async {
        let extractor = WaveformExtractor()
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.m4a")

        await #expect(throws: WaveformError.self) {
            try await extractor.extract(url: invalidURL)
        }
    }

    // MARK: - Cancel Tests

    @Test("Cancelled extraction throws CancellationError")
    func cancelledExtraction() async throws {
        guard let url = largeAudioURL() else {
            Issue.record("Large audio file not found")
            return
        }

        let extractor = WaveformExtractor()

        let extractTask = Task {
            try await extractor.extract(url: url)
        }

        // 等待一段时间让任务开始执行
        try await Task.sleep(for: .milliseconds(100))

        // 使用 Task.cancel() 取消任务
        extractTask.cancel()

        do {
            _ = try await extractTask.value
            Issue.record("Expected cancellation error")
        } catch is CancellationError {
            // 预期的取消错误
        }
    }

    // MARK: - Performance Tests

    @Test("Extract performance", .timeLimit(.minutes(1)))
    func extractPerformance() async throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }

        let extractor = WaveformExtractor()

        for _ in 0 ..< 3 {
            _ = try await extractor.extract(url: url)
        }
    }

    // MARK: - Precise Duration Tests

    @Test("Get precise audio duration with AVFoundation")
    func testAudioDuration() async throws {
        guard let url = someoneLikeYouURL() else {
            Issue.record("someoneLikeYou.aac not found")
            return
        }

        let duration = try await url.audioDuration()

        print("AVFoundation precise duration: \(duration ?? 0) seconds")

        #expect(duration != nil, "Duration should not be nil")
        #expect(duration! > 0, "Duration should be positive")
    }

    @Test("Get precise duration with FFmpeg seek")
    func testPreciseDuration() async throws {
        guard let url = someoneLikeYouURL() else {
            Issue.record("someoneLikeYou.aac not found")
            return
        }

        let duration = try await url.preciseDuration()

        print("FFmpeg precise duration: \(duration) seconds")

        #expect(duration > 0, "Duration should be positive")
    }

    @Test("Compare AVFoundation and FFmpeg duration")
    func compareDurations() async throws {
        guard let url = someoneLikeYouURL() else {
            Issue.record("someoneLikeYou.aac not found")
            return
        }

        let avDuration = try await url.audioDuration()
        let ffmpegDuration = try await url.preciseDuration()

        print("AVFoundation duration: \(avDuration ?? 0) seconds")
        print("FFmpeg duration: \(ffmpegDuration) seconds")

        if let avd = avDuration {
            let diff = abs(avd - ffmpegDuration)
            print("Difference: \(diff) seconds")
            #expect(diff < 1.0, "Duration difference should be less than 1 second")
        }
    }
}
