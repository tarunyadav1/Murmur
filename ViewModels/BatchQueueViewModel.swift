import Foundation

@MainActor
final class BatchQueueViewModel: ObservableObject {

    @Published var blocks: [TextBlock] = []
    @Published var currentBlockId: UUID?
    @Published var isProcessing: Bool = false

    private let ttsService: KokoroTTSService
    private let audioPlayerService: AudioPlayerService

    init(ttsService: KokoroTTSService, audioPlayerService: AudioPlayerService) {
        self.ttsService = ttsService
        self.audioPlayerService = audioPlayerService
    }

    // MARK: - Queue Management

    func addBlock(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let block = TextBlock(text: text)
        blocks.append(block)
    }

    func addBlocks(texts: [String]) {
        for text in texts {
            addBlock(text: text)
        }
    }

    func removeBlock(id: UUID) {
        blocks.removeAll { $0.id == id }
    }

    func moveBlock(from source: IndexSet, to destination: Int) {
        blocks.move(fromOffsets: source, toOffset: destination)
    }

    func clearQueue() {
        blocks.removeAll()
        currentBlockId = nil
    }

    func clearCompleted() {
        blocks.removeAll { $0.status == .completed }
    }

    // MARK: - Generation

    func generateAll(voice: Voice, speed: Float, voiceSettings: VoiceSettings = .default) async {
        isProcessing = true

        for index in blocks.indices {
            guard blocks[index].status == .pending else { continue }

            blocks[index].status = .generating
            currentBlockId = blocks[index].id

            do {
                let audio = try await ttsService.generate(
                    text: blocks[index].text,
                    voice: voice,
                    speed: speed,
                    voiceSettings: voiceSettings
                )
                blocks[index].generatedAudio = audio
                blocks[index].status = .completed
            } catch {
                blocks[index].status = .failed
                blocks[index].errorMessage = error.localizedDescription
            }
        }

        currentBlockId = nil
        isProcessing = false
    }

    func generateBlock(id: UUID, voice: Voice, speed: Float, voiceSettings: VoiceSettings = .default) async {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }

        blocks[index].status = .generating
        blocks[index].errorMessage = nil
        currentBlockId = id

        do {
            let audio = try await ttsService.generate(
                text: blocks[index].text,
                voice: voice,
                speed: speed,
                voiceSettings: voiceSettings
            )
            blocks[index].generatedAudio = audio
            blocks[index].status = .completed
        } catch {
            blocks[index].status = .failed
            blocks[index].errorMessage = error.localizedDescription
        }

        currentBlockId = nil
    }

    func retryBlock(id: UUID, voice: Voice, speed: Float, voiceSettings: VoiceSettings = .default) async {
        await generateBlock(id: id, voice: voice, speed: speed, voiceSettings: voiceSettings)
    }

    // MARK: - Playback

    func playBlock(id: UUID) throws {
        guard let block = blocks.first(where: { $0.id == id }),
              let audio = block.generatedAudio else {
            return
        }

        try audioPlayerService.loadAudio(samples: audio)
        audioPlayerService.play()
    }

    // MARK: - Combined Audio

    var allGeneratedAudio: [Float] {
        blocks
            .filter { $0.status == .completed }
            .compactMap { $0.generatedAudio }
            .flatMap { $0 }
    }

    var hasCompletedBlocks: Bool {
        blocks.contains { $0.status == .completed }
    }

    var hasPendingBlocks: Bool {
        blocks.contains { $0.status == .pending }
    }

    var completedCount: Int {
        blocks.filter { $0.status == .completed }.count
    }

    var totalCount: Int {
        blocks.count
    }
}
