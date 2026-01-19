import Foundation
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "History")

/// Represents a single generation in history
struct GenerationRecord: Identifiable, Codable {
    let id: UUID
    let text: String
    let voiceId: String
    let voiceName: String
    let createdAt: Date
    let durationSeconds: Double
    let generationTimeSeconds: Double
    let audioFilename: String

    var displayDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var formattedDuration: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "0:%02d", seconds)
    }

    var formattedGenerationTime: String {
        return String(format: "%.1fs", generationTimeSeconds)
    }

    var textPreview: String {
        let maxLength = 80
        if text.count <= maxLength {
            return text
        }
        return String(text.prefix(maxLength)) + "..."
    }
}

/// Service for managing generation history with WAV file storage
@MainActor
final class HistoryService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var records: [GenerationRecord] = []

    // MARK: - Configuration

    /// Maximum number of records to keep
    let maxRecords: Int

    /// Maximum total size of audio files in bytes (default 500MB)
    let maxStorageBytes: Int64

    // MARK: - Paths

    private var historyDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Murmur/History", isDirectory: true)
    }

    private var metadataURL: URL {
        historyDirectory.appendingPathComponent("history.json")
    }

    // MARK: - Initialization

    init(maxRecords: Int = 100, maxStorageBytes: Int64 = 500_000_000) {
        self.maxRecords = maxRecords
        self.maxStorageBytes = maxStorageBytes
        loadHistory()
    }

    // MARK: - Public Methods

    /// Add a new generation to history
    func addRecord(
        text: String,
        voice: Voice,
        audioSamples: [Float],
        durationSeconds: Double,
        generationTimeSeconds: Double
    ) {
        // Create directory if needed
        try? FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)

        // Generate filename
        let filename = "murmur_\(Date().timeIntervalSince1970).wav"
        let audioURL = historyDirectory.appendingPathComponent(filename)

        // Save WAV file
        do {
            try saveWAV(samples: audioSamples, to: audioURL)
        } catch {
            logger.error("Failed to save audio file: \(error.localizedDescription)")
            return
        }

        // Create record
        let record = GenerationRecord(
            id: UUID(),
            text: text,
            voiceId: voice.id,
            voiceName: voice.name,
            createdAt: Date(),
            durationSeconds: durationSeconds,
            generationTimeSeconds: generationTimeSeconds,
            audioFilename: filename
        )

        // Add to beginning (newest first)
        records.insert(record, at: 0)

        // Enforce limits
        enforceStorageLimits()

        // Save metadata
        saveHistory()

        logger.info("Added generation to history: \(record.id)")
    }

    /// Get audio samples for a record
    func loadAudio(for record: GenerationRecord) throws -> [Float] {
        let audioURL = historyDirectory.appendingPathComponent(record.audioFilename)
        let data = try Data(contentsOf: audioURL)
        return try extractSamplesFromWAV(data)
    }

    /// Get URL for audio file
    func audioURL(for record: GenerationRecord) -> URL {
        historyDirectory.appendingPathComponent(record.audioFilename)
    }

    /// Delete a specific record
    func deleteRecord(_ record: GenerationRecord) {
        // Delete audio file
        let audioURL = historyDirectory.appendingPathComponent(record.audioFilename)
        try? FileManager.default.removeItem(at: audioURL)

        // Remove from list
        records.removeAll { $0.id == record.id }

        // Save metadata
        saveHistory()
    }

    /// Clear all history
    func clearHistory() {
        // Delete all audio files
        for record in records {
            let audioURL = historyDirectory.appendingPathComponent(record.audioFilename)
            try? FileManager.default.removeItem(at: audioURL)
        }

        records.removeAll()
        saveHistory()
    }

    /// Search history by text
    func search(_ query: String) -> [GenerationRecord] {
        guard !query.isEmpty else { return records }
        let lowercaseQuery = query.lowercased()
        return records.filter {
            $0.text.lowercased().contains(lowercaseQuery) ||
            $0.voiceName.lowercased().contains(lowercaseQuery)
        }
    }

    // MARK: - Private Methods

    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            logger.info("No history file found")
            return
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            records = try JSONDecoder().decode([GenerationRecord].self, from: data)
            logger.info("Loaded \(self.records.count) history records")

            // Verify audio files exist
            records = records.filter { record in
                let audioURL = historyDirectory.appendingPathComponent(record.audioFilename)
                return FileManager.default.fileExists(atPath: audioURL.path)
            }
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: metadataURL)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    private func enforceStorageLimits() {
        // Remove excess records
        while records.count > maxRecords {
            if let oldest = records.last {
                deleteRecord(oldest)
            }
        }

        // Check total storage size
        var totalSize: Int64 = 0
        for record in records {
            let audioURL = historyDirectory.appendingPathComponent(record.audioFilename)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }

        // Remove oldest records until under limit
        while totalSize > maxStorageBytes && records.count > 0 {
            if let oldest = records.last {
                let audioURL = historyDirectory.appendingPathComponent(oldest.audioFilename)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
                   let size = attrs[.size] as? Int64 {
                    totalSize -= size
                }
                deleteRecord(oldest)
            }
        }
    }

    private func saveWAV(samples: [Float], to url: URL) throws {
        let sampleRate: UInt32 = 24000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16

        var data = Data()

        // Convert float samples to Int16
        let int16Samples = samples.map { sample -> Int16 in
            let clamped = max(-1.0, min(1.0, sample))
            return Int16(clamped * 32767)
        }

        let dataSize = UInt32(int16Samples.count * 2)
        let fileSize = dataSize + 36

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        let byteRate = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = numChannels * (bitsPerSample / 8)
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        for sample in int16Samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }

        try data.write(to: url)
    }

    private func extractSamplesFromWAV(_ data: Data) throws -> [Float] {
        guard data.count > 44 else {
            throw NSError(domain: "HistoryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid WAV file"])
        }

        // Find "data" chunk
        var dataOffset = 12
        while dataOffset < data.count - 8 {
            let chunkID = String(data: data[dataOffset..<dataOffset+4], encoding: .ascii)
            let chunkSize = data.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: dataOffset + 4, as: UInt32.self)
            }

            if chunkID == "data" {
                dataOffset += 8
                break
            }
            dataOffset += 8 + Int(chunkSize)
        }

        guard dataOffset < data.count else {
            throw NSError(domain: "HistoryService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No data chunk found"])
        }

        let audioData = data[dataOffset...]
        var samples: [Float] = []

        // Ensure we only process complete 16-bit sample pairs (2 bytes each)
        let validByteCount = (audioData.count / 2) * 2
        samples.reserveCapacity(validByteCount / 2)

        for i in stride(from: 0, to: validByteCount, by: 2) {
            let index = audioData.startIndex + i
            let low = Int16(audioData[index])
            let high = Int16(audioData[index + 1]) << 8
            let sample = low | high
            samples.append(Float(sample) / 32768.0)
        }

        return samples
    }
}
