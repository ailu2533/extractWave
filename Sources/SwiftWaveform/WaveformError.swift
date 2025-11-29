//
//  WaveformError.swift
//  SwiftWaveform
//
//  Created by Lu Ai on 2025/11/29.
//

import Foundation

public enum WaveformError: Error, LocalizedError, Equatable {
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
