import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// Handles exporting audio to various formats
final class AudioExportService {

    enum ExportError: LocalizedError {
        case noAudioData
        case conversionFailed(String)
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .noAudioData:
                return "No audio data to export."
            case .conversionFailed(let reason):
                return "Audio conversion failed: \(reason)"
            case .saveFailed(let reason):
                return "Failed to save file: \(reason)"
            }
        }
    }

    private let sampleRate: Int

    init(sampleRate: Int = KokoroTTSService.sampleRate) {
        self.sampleRate = sampleRate
    }

    /// Exports audio samples to the specified format
    /// - Parameters:
    ///   - samples: PCM audio samples
    ///   - format: Target export format
    ///   - url: Destination file URL
    func export(
        samples: [Float],
        format: AudioExportFormat,
        to url: URL
    ) async throws {
        switch format {
        case .wav:
            try exportToWAV(samples: samples, url: url)
        case .m4a:
            try await exportToM4A(samples: samples, url: url)
        }
    }

    // MARK: - WAV Export

    private func exportToWAV(samples: [Float], url: URL) throws {
        let wavData = createWAVData(from: samples)
        try wavData.write(to: url)
    }

    // MARK: - M4A Export (using AVAssetExportSession)

    private func exportToM4A(samples: [Float], url: URL) async throws {
        // First create a temporary WAV file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        try exportToWAV(samples: samples, url: tempURL)

        // Convert WAV to M4A using AVAssetExportSession
        let asset = AVAsset(url: tempURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.conversionFailed("Could not create export session")
        }

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        exportSession.outputURL = url
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if let error = exportSession.error {
            throw ExportError.conversionFailed(error.localizedDescription)
        }

        guard exportSession.status == .completed else {
            throw ExportError.conversionFailed("Export did not complete successfully")
        }
    }

    // MARK: - WAV Data Creation

    private func createWAVData(from samples: [Float]) -> Data {
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(channels) * Int(bitsPerSample / 8))
        let blockAlign = Int16(channels * bitsPerSample / 8)
        let dataSize = Int32(samples.count * Int(bitsPerSample / 8))
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert Float samples to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16Sample = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16Sample.littleEndian) { Array($0) })
        }

        return data
    }

    // MARK: - Filename Generation

    static func generateFilename(prefix: String = "speech") -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "\(prefix)_\(timestamp)"
    }
}
