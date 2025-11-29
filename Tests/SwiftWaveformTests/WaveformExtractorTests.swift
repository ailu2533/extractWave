import Foundation
import Testing
@testable import SwiftWaveform

@Suite("WaveformExtractor Tests")
struct WaveformExtractorTests {
    
    let extractor = WaveformExtractor()
    
    // MARK: - Helper
    
    func testAudioURL() -> URL? {
        Bundle.module.url(forResource: "adele", withExtension: "m4a")
    }
    
    // MARK: - Basic Tests
    
    @Test("Extract waveform from audio file")
    func extractWaveform() throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }
        
        let result = try extractor.extract(url: url)
        
        #expect(result.duration > 0)
        #expect(result.sampleRate == 4000)
        #expect(result.totalSamples > 0)
        #expect(result.data.count == WaveformExtractor.defaultPoints)
        #expect(result.pointCount == result.data.count)
    }
    
    @Test("Extract with custom points")
    func extractWithCustomPoints() throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }
        
        let customPoints = 200
        let result = try extractor.extract(url: url, points: customPoints)
        
        #expect(result.data.count == customPoints)
    }
    
    @Test("Waveform values are normalized")
    func waveformValuesNormalized() throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }
        
        let result = try extractor.extract(url: url)
        
        // All values should be between 0 and 1 (after amplitude boost and clamping)
        for value in result.data {
            #expect(value >= 0.0 && value <= 1.0, "Value \(value) is out of range [0, 1]")
        }
    }
    
    // MARK: - Error Tests
    
    @Test("File not found throws error")
    func fileNotFound() {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.m4a")
        
        #expect(throws: WaveformError.self) {
            try extractor.extract(url: invalidURL)
        }
    }
    
    // MARK: - Cancel Tests
    
    @Test("Cancel flag works")
    func cancelFlag() {
        #expect(extractor.isCancelled == false)
        
        extractor.cancel()
        #expect(extractor.isCancelled == true)
        
        extractor.reset()
        #expect(extractor.isCancelled == false)
    }
    
    @Test("Cancelled extraction throws error")
    func cancelledExtraction() async throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }

        // Start extraction in background and cancel immediately
        let extractTask = Task.detached {
            try self.extractor.extract(url: url)
        }

        // Give it a tiny moment to start, then cancel
        try await Task.sleep(for: .milliseconds(10))
        extractor.cancel()

        do {
            _ = try await extractTask.value
            Issue.record("Expected cancellation error")
        } catch let error as WaveformError {
            #expect(error == .cancelled)
        }
    }
    
    // MARK: - Performance Tests
    
    @Test("Extract performance", .timeLimit(.minutes(1)))
    func extractPerformance() throws {
        guard let url = testAudioURL() else {
            Issue.record("Test audio file not found")
            return
        }
        
        // Run multiple times to measure performance
        for _ in 0..<3 {
            _ = try extractor.extract(url: url)
        }
    }
}

