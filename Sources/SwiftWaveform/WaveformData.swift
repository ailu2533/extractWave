//
//  WaveformData.swift
//  SwiftWaveform
//
//  Created by Lu Ai on 2025/11/29.
//

import Foundation

public struct WaveformData: Sendable, Codable {
    public let duration: Double
    public let sampleRate: Int
    public let totalSamples: Int
    public let samplesPerPoint: Int
    public let data: [Double]

    public var pointCount: Int { data.count }

    // For Codable: waveformPoints is stored in JSON
    public var waveformPoints: Int { data.count }

    // Custom coding keys to match JSON format with snake_case
    enum CodingKeys: String, CodingKey {
        case duration
        case sampleRate = "sample_rate"
        case totalSamples = "total_samples"
        case waveformPoints = "waveform_points"
        case samplesPerPoint = "samples_per_point"
        case data
    }

    public init(duration: Double, sampleRate: Int, totalSamples: Int, samplesPerPoint: Int, data: [Double]) {
        self.duration = duration
        self.sampleRate = sampleRate
        self.totalSamples = totalSamples
        self.samplesPerPoint = samplesPerPoint
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = try container.decode(Double.self, forKey: .duration)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        totalSamples = try container.decode(Int.self, forKey: .totalSamples)
        samplesPerPoint = try container.decode(Int.self, forKey: .samplesPerPoint)
        data = try container.decode([Double].self, forKey: .data)
        // waveformPoints is ignored during decoding, computed from data.count
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(duration, forKey: .duration)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(totalSamples, forKey: .totalSamples)
        try container.encode(waveformPoints, forKey: .waveformPoints)
        try container.encode(samplesPerPoint, forKey: .samplesPerPoint)
        try container.encode(data, forKey: .data)
    }
}

// MARK: - Sample Data for Previews

extension WaveformData {
    /// Generate sample waveform data for SwiftUI previews
    public static var sample: WaveformData {
        let points = 250
        let data = (0 ..< points).map { _ in 0.0 }

        return WaveformData(
            duration: 251.0,
            sampleRate: 44100,
            totalSamples: 11071318,
            samplesPerPoint: 44285,
            data: data
        )
    }
}
