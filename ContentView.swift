import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    @EnvironmentObject var ttsService: TTSService
    @EnvironmentObject var audioPlayerService: AudioPlayerService
    @EnvironmentObject var settingsService: SettingsService

    @StateObject private var historyService = HistoryService()

    @State private var text: String = ""
    @State private var selectedVoice: Voice = .defaultVoice
    @State private var voiceSettings: VoiceSettings = .default
    @State private var generatedAudio: [Float]?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var generatedFilename: String = ""

    // Generation timing
    @State private var generationStartTime: Date?
    @State private var lastGenerationTime: Double?
    @State private var lastAudioDuration: Double?

    // UI State
    @State private var showHistory = false
    @State private var voiceSearchText: String = ""
    @State private var showQueue = false
    @State private var batchQueueViewModel: BatchQueueViewModel?
    @State private var showInspector = true

    private var wordCount: Int {
        text.split(separator: " ").count
    }

    private var estimatedTime: String {
        let estimatedSeconds = Double(wordCount) * 0.5
        if estimatedSeconds < 60 {
            return "~\(Int(estimatedSeconds))s"
        }
        return "~\(Int(estimatedSeconds / 60))m"
    }

    var body: some View {
        HSplitView {
            // Main Content Area
            mainContentPanel
                .frame(minWidth: 480)

            // Inspector Panel
            if showInspector {
                inspectorPanel
                    .frame(width: 340)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarItems
            }
        }
        .onAppear {
            selectedVoice = settingsService.settings.defaultVoice
            voiceSettings = settingsService.settings.voiceSettings

            if batchQueueViewModel == nil {
                batchQueueViewModel = BatchQueueViewModel(
                    ttsService: ttsService,
                    audioPlayerService: audioPlayerService
                )
            }
        }
    }

    // MARK: - Main Content Panel

    private var mainContentPanel: some View {
        VStack(spacing: 0) {
            // Text Input Area
            VStack(alignment: .leading, spacing: 16) {
                textEditorSection
                actionButtonsRow
            }
            .padding(24)

            // Audio Player (when available)
            if generatedAudio != nil {
                AudioPlayerCard(
                    filename: generatedFilename,
                    duration: audioPlayerService.duration,
                    currentTime: audioPlayerService.currentTime,
                    isPlaying: audioPlayerService.isPlaying,
                    samples: generatedAudio ?? [],
                    generationTime: lastGenerationTime,
                    onPlay: { audioPlayerService.play() },
                    onPause: { audioPlayerService.pause() },
                    onStop: { audioPlayerService.stop() },
                    onSeek: { audioPlayerService.seek(to: $0) },
                    onDownload: showExportPanel
                )
                .padding(.horizontal, 24)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            Spacer()

            // Status Bar
            statusBar
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Error Message
            if let error = errorMessage {
                errorBanner(error)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: generatedAudio != nil)
        .animation(.spring(duration: 0.3), value: errorMessage != nil)
    }

    private var textEditorSection: some View {
        HStack(alignment: .top, spacing: 12) {
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
                .frame(minHeight: 140)

            if !text.isEmpty {
                Button(action: copyText) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy text")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.2), value: text.isEmpty)
    }

    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            // Primary action group
            ControlGroup {
                Button(action: generate) {
                    HStack(spacing: 6) {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "waveform")
                                .symbolEffect(.pulse, isActive: ttsService.isModelLoaded && !text.isEmpty)
                        }
                        Text(isGenerating ? "Creating..." : "Create")
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating || !ttsService.isModelLoaded)
                .keyboardShortcut(.return, modifiers: .command)

                if isGenerating {
                    Button(action: stopGeneration) {
                        Image(systemName: "stop.fill")
                    }
                    .tint(.red)
                }
            }
            .controlGroupStyle(.navigation)

            // Add to Queue button
            if !isGenerating {
                Button(action: addToQueue) {
                    Label("Queue", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer()

            // Info chips
            HStack(spacing: 8) {
                if !text.isEmpty && !isGenerating {
                    Chip(text: estimatedTime, icon: "clock")
                }
                Chip(text: "\(wordCount) words", icon: "textformat")
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.5), radius: 4)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !ttsService.isModelLoaded && !ttsService.isLoading {
                    Button("Connect") {
                        Task { try? await ttsService.loadModel() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            Spacer()

            // Panel toggles
            HStack(spacing: 4) {
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showQueue.toggle()
                        if showQueue { showHistory = false }
                    }
                } label: {
                    Label {
                        HStack(spacing: 4) {
                            Text("Queue")
                            if let vm = batchQueueViewModel, vm.blocks.count > 0 {
                                Text("\(vm.blocks.count)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.tint.opacity(0.2), in: Capsule())
                            }
                        }
                    } icon: {
                        Image(systemName: "list.bullet")
                    }
                }
                .buttonStyle(.bordered)
                .tint(showQueue ? .accentColor : nil)
                .controlSize(.small)

                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showHistory.toggle()
                        if showHistory { showQueue = false }
                    }
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .tint(showHistory ? .accentColor : nil)
                .controlSize(.small)
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)

            Text(message)
                .font(.callout)

            Spacer()

            Button {
                withAnimation { errorMessage = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.red.opacity(0.3), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        if ttsService.isModelLoaded { return .green }
        if ttsService.isLoading { return .orange }
        return .red
    }

    private var statusText: String {
        if ttsService.isModelLoaded {
            return "Ready (Kokoro)"
        }
        if ttsService.isLoading { return "Connecting..." }
        return "Offline"
    }

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        Group {
            if showHistory {
                HistoryPanel(
                    historyService: historyService,
                    audioPlayerService: audioPlayerService,
                    onClose: { withAnimation { showHistory = false } },
                    onReuse: { record in
                        text = record.text
                        if let voice = Voice.builtInVoices.first(where: { $0.id == record.voiceId }) {
                            selectedVoice = voice
                        }
                        withAnimation { showHistory = false }
                    }
                )
            } else if showQueue, let queueVM = batchQueueViewModel {
                QueuePanel(
                    viewModel: queueVM,
                    selectedVoice: $selectedVoice,
                    voiceSettings: voiceSettings,
                    onClose: { withAnimation { showQueue = false } }
                )
            } else {
                voiceStylePanel
            }
        }
        .background(.ultraThinMaterial)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var voiceStylePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Voice & Style")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)

                // Kokoro Voice Selector
                KokoroVoiceSelector(
                    selectedVoiceId: $ttsService.selectedVoiceId,
                    voices: ttsService.kokoroVoices,
                    searchText: $voiceSearchText
                )

                // Speed info
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                    Text("Kokoro 82M - ~7x faster than real-time on Apple Silicon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                Divider()
                    .padding(.vertical, 4)

                // Fine-tune Controls
                VStack(alignment: .leading, spacing: 16) {
                    Text("Fine-Tune Controls")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ModernSlider(
                        title: "Pacing",
                        subtitle: "Slower ↔ Faster",
                        value: Binding(
                            get: { voiceSettings.pacing },
                            set: { voiceSettings.pacing = $0; voiceSettings.activePreset = nil }
                        ),
                        range: VoiceSettings.Ranges.pacing,
                        format: "%.2f×"
                    )

                    ModernSlider(
                        title: "Fade-Out",
                        subtitle: "Quick ↔ Long tail",
                        value: Binding(
                            get: { voiceSettings.fadeOutLength },
                            set: { voiceSettings.fadeOutLength = $0; voiceSettings.activePreset = nil }
                        ),
                        range: VoiceSettings.Ranges.fadeOutLength,
                        format: "%.1fs"
                    )
                }
            }
            .padding(24)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                showInspector.toggle()
            }
        } label: {
            Label("Inspector", systemImage: showInspector ? "sidebar.trailing" : "sidebar.trailing")
        }
        .help(showInspector ? "Hide Inspector" : "Show Inspector")
    }

    // MARK: - Actions

    private func generate() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        isGenerating = true
        errorMessage = nil
        generationStartTime = Date()

        Task {
            do {
                let audio = try await ttsService.generate(
                    text: trimmedText,
                    voice: selectedVoice,
                    speed: voiceSettings.pacing,
                    voiceSettings: voiceSettings
                )

                let generationTime = Date().timeIntervalSince(generationStartTime ?? Date())
                let audioDuration = Double(audio.count) / Double(TTSService.sampleRate)

                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                    generatedAudio = audio
                    generatedFilename = AudioExportService.generateFilename() + ".wav"
                    lastGenerationTime = generationTime
                    lastAudioDuration = audioDuration
                }

                try audioPlayerService.loadAudio(samples: audio)

                historyService.addRecord(
                    text: trimmedText,
                    voice: selectedVoice,
                    audioSamples: audio,
                    durationSeconds: audioDuration,
                    generationTimeSeconds: generationTime
                )

                if settingsService.settings.autoPlayOnGenerate {
                    audioPlayerService.play()
                }
            } catch {
                if !Task.isCancelled {
                    withAnimation {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            isGenerating = false
            generationStartTime = nil
        }
    }

    private func stopGeneration() {
        ttsService.cancelGeneration()
        isGenerating = false
        generationStartTime = nil
    }

    private func addToQueue() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        batchQueueViewModel?.addBlock(text: trimmedText)
        text = ""
        withAnimation(.spring(duration: 0.3)) {
            showQueue = true
        }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func showExportPanel() {
        guard let audio = generatedAudio else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav, .mpeg4Audio]
        panel.nameFieldStringValue = generatedFilename

        if let defaultLocation = settingsService.settings.defaultSaveLocation {
            panel.directoryURL = defaultLocation
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task {
                let exportService = AudioExportService()
                let format: AudioExportFormat = url.pathExtension == "m4a" ? .m4a : .wav

                do {
                    try await exportService.export(samples: audio, format: format, to: url)
                } catch {
                    await MainActor.run {
                        withAnimation {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Chip Component

struct Chip: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }
}

// MARK: - Queue Panel

struct QueuePanel: View {
    @ObservedObject var viewModel: BatchQueueViewModel
    @Binding var selectedVoice: Voice
    let voiceSettings: VoiceSettings
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Generation Queue")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            .padding(.bottom, -8)

            BatchQueueView(
                viewModel: viewModel,
                selectedVoice: $selectedVoice,
                speed: .constant(voiceSettings.pacing),
                voiceSettings: voiceSettings
            )
        }
    }
}

// MARK: - History Panel

struct HistoryPanel: View {
    @ObservedObject var historyService: HistoryService
    let audioPlayerService: AudioPlayerService
    let onClose: () -> Void
    let onReuse: (GenerationRecord) -> Void

    @State private var searchText = ""

    private var filteredRecords: [GenerationRecord] {
        historyService.search(searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)

                Spacer()

                if !historyService.records.isEmpty {
                    Button("Clear") {
                        historyService.clearHistory()
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
            }
            .padding(24)

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 24)

            // List
            if filteredRecords.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRecords) { record in
                            HistoryRow(
                                record: record,
                                onPlay: { playRecord(record) },
                                onReuse: { onReuse(record) },
                                onDelete: { historyService.deleteRecord(record) }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
                .symbolEffect(.pulse, options: .repeating)
            Text(searchText.isEmpty ? "No history yet" : "No matches")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func playRecord(_ record: GenerationRecord) {
        do {
            let samples = try historyService.loadAudio(for: record)
            try audioPlayerService.loadAudio(samples: samples)
            audioPlayerService.play()
        } catch {
            // Handle error silently
        }
    }
}

struct HistoryRow: View {
    let record: GenerationRecord
    let onPlay: () -> Void
    let onReuse: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.textPreview)
                .font(.subheadline)
                .lineLimit(2)

            HStack(spacing: 12) {
                Label(record.voiceName, systemImage: "person.wave.2")
                Label(record.formattedDuration, systemImage: "waveform")
                Spacer()
                Text(record.displayDate)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onPlay) {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onReuse) {
                        Label("Reuse", systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.3) : .clear, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.2), value: isHovered)
    }
}

// MARK: - Audio Player Card

struct AudioPlayerCard: View {
    let filename: String
    let duration: TimeInterval
    let currentTime: TimeInterval
    let isPlaying: Bool
    let samples: [Float]
    var generationTime: Double? = nil
    let onPlay: () -> Void
    let onPause: () -> Void
    let onStop: () -> Void
    let onSeek: (TimeInterval) -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 14) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(.tint.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: "waveform")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(filename)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        Text("\(formatTime(currentTime)) / \(formatTime(duration))")
                            .monospacedDigit()

                        if let genTime = generationTime {
                            Text("Generated in \(String(format: "%.1fs", genTime))")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Playback Controls
                ControlGroup {
                    Button(action: isPlaying ? onPause : onPlay) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .keyboardShortcut(.space, modifiers: [])

                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                    }

                    Divider()

                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle")
                    }
                    .help("Export audio")
                }
                .controlGroupStyle(.navigation)
            }

            // Waveform
            WaveformView(
                samples: samples,
                progress: duration > 0 ? currentTime / duration : 0,
                onSeek: { progress in
                    onSeek(progress * duration)
                }
            )
            .frame(height: 56)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform View

struct WaveformView: View {
    let samples: [Float]
    let progress: Double
    let onSeek: (Double) -> Void

    @State private var isHovering = false
    @State private var hoverProgress: Double = 0

    private let barCount = 80

    var body: some View {
        GeometryReader { geometry in
            let barWidth = geometry.size.width / CGFloat(barCount)
            let reducedSamples = reduceSamples(to: barCount)

            ZStack(alignment: .leading) {
                // Background bars
                HStack(spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let height = CGFloat(reducedSamples[index]) * geometry.size.height
                        let barProgress = Double(index) / Double(barCount)
                        let isPast = barProgress < progress

                        RoundedRectangle(cornerRadius: 2)
                            .fill(isPast ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: barWidth - 2, height: max(4, height))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)

                // Hover indicator
                if isHovering {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 2)
                        .offset(x: hoverProgress * geometry.size.width)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        onSeek(progress)
                    }
            )
            .onHover { hovering in
                isHovering = hovering
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverProgress = location.x / geometry.size.width
                case .ended:
                    break
                }
            }
        }
    }

    private func reduceSamples(to count: Int) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: 0.15, count: count)
        }

        let chunkSize = max(1, samples.count / count)
        var result: [Float] = []

        for i in 0..<count {
            let start = i * chunkSize
            let end = min(start + chunkSize, samples.count)
            if start < samples.count {
                let chunk = samples[start..<end]
                let maxVal = chunk.map { abs($0) }.max() ?? 0
                result.append(max(0.08, min(1.0, maxVal * 2.2)))
            } else {
                result.append(0.08)
            }
        }

        return result
    }
}

// MARK: - Voice Selector

struct VoiceSelector: View {
    @Binding var selectedVoice: Voice
    @Binding var searchText: String

    @State private var isExpanded = false
    @StateObject private var previewService = VoicePreviewService.shared

    private var filteredVoices: [Voice] {
        if searchText.isEmpty {
            return Voice.builtInVoices
        }
        let query = searchText.lowercased()
        return Voice.builtInVoices.filter {
            $0.name.lowercased().contains(query) ||
            $0.description.lowercased().contains(query) ||
            $0.gender.displayName.lowercased().contains(query) ||
            $0.style.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Selected voice button
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedVoice.name)
                            .foregroundStyle(.primary)
                        if selectedVoice.id != "default" {
                            Text("\(selectedVoice.gender.displayName) • \(selectedVoice.style.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isExpanded ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Expanded list
            if isExpanded {
                VStack(spacing: 10) {
                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        TextField("Search voices...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                    }
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))

                    // Voice list
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(filteredVoices) { voice in
                                HStack(spacing: 8) {
                                    // Play preview button
                                    if voice.hasSample {
                                        Button {
                                            previewService.toggle(voice: voice)
                                        } label: {
                                            Image(systemName: previewService.currentlyPlayingVoiceId == voice.id ? "stop.circle.fill" : "play.circle")
                                                .font(.system(size: 20))
                                                .foregroundStyle(previewService.currentlyPlayingVoiceId == voice.id ? .orange : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Preview voice")
                                    } else {
                                        Color.clear.frame(width: 20)
                                    }

                                    // Voice selection button
                                    Button {
                                        selectedVoice = voice
                                        previewService.stop()
                                        withAnimation(.spring(duration: 0.2)) {
                                            isExpanded = false
                                            searchText = ""
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(voice.name)
                                                    .foregroundStyle(.primary)
                                                if voice.id != "default" {
                                                    Text("\(voice.gender.displayName) • \(voice.style.displayName)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            if selectedVoice.id == voice.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.tint)
                                                    .symbolEffect(.bounce, value: selectedVoice.id)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(
                                    selectedVoice.id == voice.id
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }
}

// MARK: - Modern Slider

struct ModernSlider: View {
    let title: String
    let subtitle: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Text(String(format: format, value))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)

                    Button(action: resetValue) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isDefaultValue ? 0.3 : 1)
                    .disabled(isDefaultValue)
                }
            }

            Slider(value: $value, in: range)
                .tint(.accentColor)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var isDefaultValue: Bool {
        let defaults = VoiceSettings.default
        switch title {
        case "Emotion / Energy": return value == defaults.emotionEnergy
        case "Voice Match": return value == defaults.voiceMatchStrength
        case "Pacing": return value == defaults.pacing
        case "Fade-Out": return value == defaults.fadeOutLength
        default: return false
        }
    }

    private func resetValue() {
        withAnimation(.spring(duration: 0.2)) {
            let defaults = VoiceSettings.default
            switch title {
            case "Emotion / Energy": value = defaults.emotionEnergy
            case "Voice Match": value = defaults.voiceMatchStrength
            case "Pacing": value = defaults.pacing
            case "Fade-Out": value = defaults.fadeOutLength
            default: break
            }
        }
    }
}

// MARK: - Kokoro Voice Selector

struct KokoroVoiceSelector: View {
    @Binding var selectedVoiceId: String
    let voices: [KokoroVoice]
    @Binding var searchText: String

    @State private var isExpanded = false

    private var filteredVoices: [KokoroVoice] {
        if searchText.isEmpty {
            return voices
        }
        let query = searchText.lowercased()
        return voices.filter {
            $0.name.lowercased().contains(query) ||
            $0.accent.lowercased().contains(query) ||
            $0.gender.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    private var selectedVoice: KokoroVoice? {
        voices.first { $0.id == selectedVoiceId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            // Selected voice button
            Button {
                withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedVoice?.name ?? "Select Voice")
                            .foregroundStyle(.primary)
                        if let voice = selectedVoice {
                            Text("\(voice.gender.capitalized) • \(voice.accent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isExpanded ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Expanded list
            if isExpanded {
                VStack(spacing: 10) {
                    // Search
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        TextField("Search voices...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                    }
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))

                    // Voice list
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(filteredVoices) { voice in
                                Button {
                                    selectedVoiceId = voice.id
                                    withAnimation(.spring(duration: 0.2)) {
                                        isExpanded = false
                                        searchText = ""
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(voice.name)
                                                .foregroundStyle(.primary)
                                            Text("\(voice.gender.capitalized) • \(voice.accent)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedVoiceId == voice.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(10)
                                .background(
                                    selectedVoiceId == voice.id
                                        ? Color.accentColor.opacity(0.1)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }
}
