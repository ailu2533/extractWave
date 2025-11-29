//
//  WaveformData.swift
//  SwiftWaveform
//
//  Created by Lu Ai on 2025/11/29.
//

import Foundation

public struct WaveformData: Sendable {
    public let duration: Double
    public let sampleRate: Int
    public let totalSamples: Int
    public let samplesPerPoint: Int
    public let data: [Double]

    public var pointCount: Int { data.count }
}
