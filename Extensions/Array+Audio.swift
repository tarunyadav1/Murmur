import Foundation
import Accelerate

extension Array where Element == Float {

    /// Normalizes audio to prevent clipping
    func normalized() -> [Float] {
        guard !isEmpty else { return [] }

        var maxValue: Float = 0
        vDSP_maxmgv(self, 1, &maxValue, vDSP_Length(count))

        guard maxValue > 0 else { return self }

        var result = [Float](repeating: 0, count: count)
        var scale = 1.0 / maxValue * 0.95 // Leave some headroom
        vDSP_vsmul(self, 1, &scale, &result, 1, vDSP_Length(count))

        return result
    }

    /// Calculates duration in seconds at given sample rate
    func duration(sampleRate: Int = Constants.sampleRate) -> TimeInterval {
        TimeInterval(count) / TimeInterval(sampleRate)
    }

    /// Concatenates multiple audio arrays with optional crossfade
    static func concatenate(_ arrays: [[Float]], crossfadeSamples: Int = 0) -> [Float] {
        guard !arrays.isEmpty else { return [] }
        guard arrays.count > 1 else { return arrays[0] }

        var result = arrays[0]

        for i in 1..<arrays.count {
            let next = arrays[i]

            if crossfadeSamples > 0 && result.count >= crossfadeSamples && next.count >= crossfadeSamples {
                // Apply crossfade
                for j in 0..<crossfadeSamples {
                    let fadeOut = Float(crossfadeSamples - j) / Float(crossfadeSamples)
                    let fadeIn = Float(j) / Float(crossfadeSamples)
                    let idx = result.count - crossfadeSamples + j
                    result[idx] = result[idx] * fadeOut + next[j] * fadeIn
                }
                result.append(contentsOf: next.dropFirst(crossfadeSamples))
            } else {
                result.append(contentsOf: next)
            }
        }

        return result
    }
}
