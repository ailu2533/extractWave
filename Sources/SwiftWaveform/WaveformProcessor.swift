import Accelerate
import Foundation

// Match C++ version constants
private let amplitudeBoost: Double = 2.5

/// A processor that distributes samples properly (matches C++ WaveformProcessor)
/// Optimized with batch processing and Accelerate framework
struct StreamingWaveformProcessor {
    private let points: Int
    private var rmsAccumulators: [Double]
    private var samplesInBucket: [Int]
    private(set) var totalSamples: Int = 0
    private let samplesPerPoint: Int

    init(points: Int, estimatedTotalSamples: Int = 0) {
        self.points = points
        rmsAccumulators = [Double](repeating: 0, count: points)
        samplesInBucket = [Int](repeating: 0, count: points)
        samplesPerPoint = max(1, estimatedTotalSamples / points)
    }

    /// Add samples in batch (optimized)
    mutating func addSamples(_ buffer: UnsafePointer<Int16>, count: Int) {
        var i = 0
        while i < count {
            let bucket = totalSamples / samplesPerPoint
            if bucket >= points {
                totalSamples += (count - i)
                break
            }

            // Calculate how many samples fit in current bucket
            let samplesUntilNextBucket = samplesPerPoint - (totalSamples % samplesPerPoint)
            let samplesToProcess = min(samplesUntilNextBucket, count - i)

            // Use Accelerate to compute sum of squares for this chunk
            var sumSquares: Float = 0
            let bufferPtr = buffer.advanced(by: i)

            // Convert Int16 to Float and compute sum of squares
            var floatBuffer = [Float](repeating: 0, count: samplesToProcess)
            vDSP_vflt16(bufferPtr, 1, &floatBuffer, 1, vDSP_Length(samplesToProcess))

            // Normalize by 32768 and square
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(floatBuffer, 1, &scale, &floatBuffer, 1, vDSP_Length(samplesToProcess))
            vDSP_svesq(floatBuffer, 1, &sumSquares, vDSP_Length(samplesToProcess))

            rmsAccumulators[bucket] += Double(sumSquares)
            samplesInBucket[bucket] += samplesToProcess
            totalSamples += samplesToProcess
            i += samplesToProcess
        }
    }

    var samplesPerPointValue: Int {
        samplesPerPoint
    }

    /// Finalize and return waveform data (matches C++ generateOutput)
    mutating func finalize() -> [Double] {
        var result = [Double](repeating: 0, count: points)

        for i in 0 ..< points {
            if samplesInBucket[i] == 0 {
                result[i] = 0.0
            } else {
                let rms = sqrt(rmsAccumulators[i] / Double(samplesInBucket[i]))
                result[i] = min(rms * amplitudeBoost, 1.0)
            }
        }

        return result
    }
}
