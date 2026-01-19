import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {

    @EnvironmentObject var ttsService: KokoroTTSService
    @EnvironmentObject var audioPlayerService: AudioPlayerService
    @EnvironmentObject var settingsService: SettingsService

    @StateObject private var historyService = HistoryService()
    @ObservedObject private var toastManager = ToastManager.shared

    @State private var text: String = ""
    @State private var selectedVoice: Voice = .defaultVoice
    @State private var voiceSettings: VoiceSettings = .default
    @State private var generatedAudio: [Float]?
    @State private var generatedWaveform: [Float] = []
    @State private var isGenerating = false
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
    @State private var showInspector = false // Collapsed by default now
    @State private var isDropTargeted = false
    @State private var createButtonPressed = false
    @State private var selectedHistoryRecord: GenerationRecord?  // For full-screen player

    // Language detection
    @State private var detectedLanguage: Language?
    @State private var showLanguageSuggestion = false
    @State private var languageDetectionTask: Task<Void, Never>?

    // Document import state
    @State private var showImportSheet = false
    @State private var importResult: DocumentImportService.ImportResult?
    @State private var isImporting = false
    private let documentImportService = DocumentImportService()

    // Document generation progress state
    @State private var isGeneratingDocument = false
    @State private var documentGenerationName = ""
    @State private var documentCurrentChunk = 0
    @State private var documentTotalChunks = 0
    @State private var documentGenerationTask: Task<Void, Never>?

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
        ZStack {
            HSplitView {
                // Main Content Area - Content First!
                if let record = selectedHistoryRecord {
                    // History Player View takes over main area
                    HistoryPlayerView(
                        record: record,
                        audioPlayerService: audioPlayerService,
                        historyService: historyService,
                        onClose: {
                            withAnimation(MurmurDesign.Animations.panelSlide) {
                                selectedHistoryRecord = nil
                            }
                        },
                        onRegenerate: { rec in
                            text = rec.text
                            if let voice = Voice.builtInVoices.first(where: { $0.id == rec.voiceId }) {
                                selectedVoice = voice
                            }
                            withAnimation(MurmurDesign.Animations.panelSlide) {
                                selectedHistoryRecord = nil
                                showHistory = false
                            }
                        }
                    )
                    .frame(minWidth: 520)
                    .transition(.opacity)
                } else {
                    mainContentPanel
                        .frame(minWidth: 520)
                }

                // Inspector Panel - Collapsed by default
                if showInspector {
                    inspectorPanel
                        .frame(width: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(MurmurDesign.Animations.panelSlide, value: selectedHistoryRecord?.id)

            // Floating Audio Player
            if generatedAudio != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingAudioPlayer(
                            filename: generatedFilename,
                            duration: audioPlayerService.duration,
                            currentTime: audioPlayerService.currentTime,
                            isPlaying: audioPlayerService.isPlaying,
                            waveformData: generatedWaveform,
                            generationTime: lastGenerationTime,
                            onPlay: { audioPlayerService.play() },
                            onPause: { audioPlayerService.pause() },
                            onStop: { audioPlayerService.stop() },
                            onSeek: { audioPlayerService.seek(to: $0) },
                            onExport: showExportPanel,
                            onDismiss: {
                                withAnimation(MurmurDesign.Animations.panelSlide) {
                                    generatedAudio = nil
                                    generatedWaveform = []
                                    audioPlayerService.stop()
                                }
                            }
                        )
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)),
                    removal: .opacity
                ))
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .withToasts()
        .withOnboarding()
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                toolbarItems
            }
        }
        .onDrop(of: [.text, .plainText, .fileURL, .pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showImportSheet) {
            if let result = importResult {
                DocumentImportSheet(
                    importResult: result,
                    onGenerateAudio: { chunks in
                        showImportSheet = false
                        let docName = importResult?.documentName ?? "Document"
                        importResult = nil
                        // Generate audio from chunks
                        generateFromChunks(chunks, documentName: docName)
                    },
                    onCancel: {
                        showImportSheet = false
                        importResult = nil
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDocument)) { _ in
            showOpenPanel()
        }
        .overlay {
            // Drop zone indicator
            if isDropTargeted {
                RoundedRectangle(cornerRadius: MurmurDesign.Radius.lg)
                    .strokeBorder(MurmurDesign.Colors.voicePrimary, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .background(MurmurDesign.Colors.voicePrimary.opacity(0.05))
                    .padding(8)
                    .transition(.opacity)
            }

            // Document generation progress overlay
            if isGeneratingDocument {
                DocumentGenerationOverlay(
                    documentName: documentGenerationName,
                    currentChunk: documentCurrentChunk,
                    totalChunks: documentTotalChunks,
                    onCancel: cancelDocumentGeneration
                )
                .transition(.opacity)
            }
        }
        .animation(MurmurDesign.Animations.quick, value: isDropTargeted)
        .animation(MurmurDesign.Animations.quick, value: isGeneratingDocument)
        .animation(MurmurDesign.Animations.panelSlide, value: showInspector)
        .animation(MurmurDesign.Animations.panelSlide, value: generatedAudio != nil)
        .onAppear {
            selectedVoice = settingsService.settings.defaultVoice
            voiceSettings = settingsService.settings.voiceSettings

            // Sync ttsService with initial selected voice
            if selectedVoice.id != "default" {
                ttsService.selectedVoiceId = selectedVoice.id
            }

            if batchQueueViewModel == nil {
                batchQueueViewModel = BatchQueueViewModel(
                    ttsService: ttsService,
                    audioPlayerService: audioPlayerService
                )
            }
        }
        .onChange(of: selectedVoice) { _, newVoice in
            // Propagate local Voice selection to TTSService if it's not the placeholder
            if newVoice.id != "default" {
                ttsService.selectedVoiceId = newVoice.id
            }
        }
        .onChange(of: ttsService.selectedVoiceId) { _, newVoiceId in
            // Keep local Voice in sync if TTSService changes (e.g. from compact menu)
            if selectedVoice.id != newVoiceId {
                if let voice = Voice.builtInVoices.first(where: { $0.id == newVoiceId }) {
                    selectedVoice = voice
                }
            }
        }
        .onChange(of: text) { _, newText in
            detectLanguage(in: newText)
        }
    }

    // MARK: - Language Detection

    /// Current voice's language
    private var currentVoiceLanguage: Language? {
        ttsService.kokoroVoices
            .first { $0.id == ttsService.selectedVoiceId }?
            .language
    }

    /// Whether the detected language differs from the selected voice's language
    private var languageMismatch: Bool {
        guard let detected = detectedLanguage,
              let current = currentVoiceLanguage else { return false }
        // English US and UK are compatible
        if (detected == .englishUS || detected == .englishUK) &&
           (current == .englishUS || current == .englishUK) {
            return false
        }
        return detected != current
    }

    /// Detect language from text with debouncing
    private func detectLanguage(in text: String) {
        // Cancel any existing detection task
        languageDetectionTask?.cancel()

        // Don't detect for very short text (10 chars minimum for non-Latin, 15 for Latin)
        let minLength = text.unicodeScalars.contains { !$0.isASCII } ? 10 : 15
        guard text.count >= minLength else {
            detectedLanguage = nil
            showLanguageSuggestion = false
            return
        }

        // Debounce: wait 500ms before detecting
        languageDetectionTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            let detected = LanguageDetectionService.shared.detectLanguageWithConfidence(from: text)

            await MainActor.run {
                if let result = detected, result.confidence > 0.5 {
                    let newLanguage = result.language
                    self.detectedLanguage = newLanguage

                    // Auto-switch if language doesn't match current voice
                    if self.languageMismatch {
                        // Auto-switch to detected language
                        ttsService.switchToLanguage(newLanguage)
                        // Show toast notification
                        ToastManager.shared.show(
                            .success,
                            message: "Switched to \(newLanguage.displayName) voice"
                        )
                        self.showLanguageSuggestion = false
                    }
                } else {
                    self.detectedLanguage = nil
                    self.showLanguageSuggestion = false
                }
            }
        }
    }

    /// Switch to a voice matching the detected language
    private func switchToDetectedLanguage() {
        guard let targetLanguage = detectedLanguage else { return }

        ttsService.switchToLanguage(targetLanguage)
        withAnimation {
            showLanguageSuggestion = false
        }
    }

    /// Language suggestion banner
    @ViewBuilder
    private func languageSuggestionBanner(for language: Language) -> some View {
        HStack(spacing: 12) {
            Image(systemName: language.icon)
                .font(.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(language.displayName) detected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Switch voice for better pronunciation?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Switch") {
                switchToDetectedLanguage()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                withAnimation {
                    showLanguageSuggestion = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: MurmurDesign.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: MurmurDesign.Radius.md)
                .strokeBorder(.tint.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Main Content Panel

    private var mainContentPanel: some View {
        VStack(spacing: 0) {
            // Compact toolbar with voice selector
            compactToolbar
                .padding(.horizontal, MurmurDesign.Spacing.lg)
                .padding(.top, MurmurDesign.Spacing.md)

            // Hero: Text Input Area
            VStack(alignment: .leading, spacing: MurmurDesign.Spacing.md) {
                heroTextEditor

                // Language suggestion banner
                if showLanguageSuggestion, let detected = detectedLanguage {
                    languageSuggestionBanner(for: detected)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                actionButtonsRow
            }
            .padding(MurmurDesign.Spacing.lg)
            .animation(MurmurDesign.Animations.quick, value: showLanguageSuggestion)

            Spacer(minLength: 0)

            // Minimal status bar
            minimalStatusBar
                .padding(.horizontal, MurmurDesign.Spacing.lg)
                .padding(.bottom, MurmurDesign.Spacing.md)
        }
    }

    // MARK: - Compact Toolbar

    private var compactToolbar: some View {
        HStack(spacing: MurmurDesign.Spacing.sm) {
            // Voice selector - compact
            Menu {
                if ttsService.kokoroVoices.isEmpty {
                    Button("Loading voices...") { }
                        .disabled(true)
                    Button("Retry") {
                        Task { await ttsService.refreshVoices() }
                    }
                } else {
                    ForEach(ttsService.kokoroVoices) { voice in
                        Button {
                            ttsService.selectedVoiceId = voice.id
                            // Reset to default so generate() uses selectedVoiceId
                            selectedVoice = .defaultVoice
                        } label: {
                            HStack {
                                Text(voice.name)
                                if ttsService.selectedVoiceId == voice.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.wave.2")
                        .font(.caption)
                    Text(selectedVoiceName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            // Quick stats
            if !text.isEmpty {
                HStack(spacing: MurmurDesign.Spacing.xs) {
                    Chip(text: "\(wordCount) words", icon: "textformat")
                    if !isGenerating {
                        Chip(text: estimatedTime, icon: "clock")
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(MurmurDesign.Animations.quick, value: text.isEmpty)
    }

    private var selectedVoiceName: String {
        ttsService.kokoroVoices.first { $0.id == ttsService.selectedVoiceId }?.name ?? "Select Voice"
    }

    // MARK: - Hero Text Editor

    private var heroTextEditor: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Placeholder with upload hint
                if text.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What would you like to say?")
                            .font(.title3)
                            .foregroundStyle(.tertiary)

                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.caption)
                            Text("Drop a PDF here or press ⌘O to import")
                                .font(.caption)
                        }
                        .foregroundStyle(.quaternary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.title3)
                    .scrollContentBackground(.hidden)
                    .padding(14)
            }
            .frame(minHeight: 200, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: MurmurDesign.Radius.lg)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: MurmurDesign.Radius.lg)
                    .strokeBorder(
                        isDropTargeted ? MurmurDesign.Colors.voicePrimary : Color.secondary.opacity(0.2),
                        lineWidth: isDropTargeted ? 2 : 0.5
                    )
            }
        }
    }

    // MARK: - Action Buttons with Micro-animations

    private var actionButtonsRow: some View {
        HStack(spacing: MurmurDesign.Spacing.sm) {
            // Primary Create button with animation
            Button(action: generate) {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: ttsService.isModelLoaded && !text.isEmpty)
                    }
                    Text(isGenerating ? "Creating..." : "Create")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(MurmurDesign.Colors.voicePrimary)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating || !ttsService.isModelLoaded)
            .keyboardShortcut(.return, modifiers: .command)
            .scaleEffect(createButtonPressed ? 0.95 : 1.0)
            .animation(MurmurDesign.Animations.buttonPress, value: createButtonPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in createButtonPressed = true }
                    .onEnded { _ in createButtonPressed = false }
            )

            // Keyboard hint on hover
            KeyboardHint(keys: "⌘↩")
                .opacity(createButtonPressed ? 0 : 0.7)

            if isGenerating {
                Button(action: stopGeneration) {
                    Image(systemName: "stop.fill")
                        .foregroundStyle(MurmurDesign.Colors.error)
                }
                .buttonStyle(.bordered)
                .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            // Import PDF button
            Button(action: showOpenPanel) {
                Label("Import PDF", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.bordered)
            .help("Import PDF document (⌘O)")

            // Copy button
            if !text.isEmpty {
                Button(action: copyText) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("Copy text")
                .transition(.scale.combined(with: .opacity))
            }

            // Add to Queue
            if !isGenerating && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: addToQueue) {
                    Label("Queue", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(MurmurDesign.Animations.quick, value: isGenerating)
        .animation(MurmurDesign.Animations.quick, value: text.isEmpty)
    }

    // MARK: - Minimal Status Bar

    private var minimalStatusBar: some View {
        HStack(spacing: MurmurDesign.Spacing.md) {
            // Connection indicator - minimal
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .softGlow(statusColor, radius: 4)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !ttsService.isModelLoaded && !ttsService.isLoading {
                Button("Connect") {
                    Task { try? await ttsService.loadModel() }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            Spacer()

            // Panel toggles - icon only
            HStack(spacing: 2) {
                Button {
                    withAnimation(MurmurDesign.Animations.panelSlide) {
                        showQueue.toggle()
                        if showQueue {
                            showHistory = false
                            showInspector = true
                        }
                    }
                } label: {
                    ZStack {
                        Image(systemName: "list.bullet")
                        if let vm = batchQueueViewModel, vm.blocks.count > 0 {
                            Text("\(vm.blocks.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(MurmurDesign.Colors.voicePrimary, in: Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .tint(showQueue ? MurmurDesign.Colors.voicePrimary : nil)
                .controlSize(.small)
                .help("Queue")

                Button {
                    withAnimation(MurmurDesign.Animations.panelSlide) {
                        showHistory.toggle()
                        if showHistory {
                            showQueue = false
                            showInspector = true
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .tint(showHistory ? MurmurDesign.Colors.voicePrimary : nil)
                .controlSize(.small)
                .help("History")
            }
        }
    }

    private var statusColor: Color {
        if ttsService.isModelLoaded { return .green }
        if ttsService.isLoading { return .orange }
        return .red
    }

    private var statusText: String {
        if ttsService.isModelLoaded {
            return "Ready"
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
                    selectedRecordId: selectedHistoryRecord?.id,
                    onClose: { withAnimation { showHistory = false } },
                    onReuse: { record in
                        text = record.text
                        if let voice = Voice.builtInVoices.first(where: { $0.id == record.voiceId }) {
                            selectedVoice = voice
                        }
                        withAnimation { showHistory = false }
                    },
                    onSelectRecord: { record in
                        withAnimation(MurmurDesign.Animations.panelSlide) {
                            selectedHistoryRecord = record
                        }
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

                // Voice Selector
                KokoroVoiceSelector(
                    selectedVoiceId: $ttsService.selectedVoiceId,
                    voices: ttsService.kokoroVoices,
                    searchText: $voiceSearchText,
                    onRetryLoadVoices: {
                        await ttsService.refreshVoices()
                    },
                    suggestedLanguage: detectedLanguage,
                    onLanguageSelected: { _ in
                        // Dismiss suggestion when user manually selects a voice
                        showLanguageSuggestion = false
                    },
                    onVoiceSelected: {
                        // Reset to default so generate() uses selectedVoiceId
                        selectedVoice = .defaultVoice
                    }
                )

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

        // Prevent double-clicking - if already generating, ignore
        guard !isGenerating else { return }

        isGenerating = true
        let startTime = Date() // Capture locally to avoid @State race conditions
        generationStartTime = startTime
        toastManager.showGenerating()

        Task {
            do {
                // Use the unified selectedVoiceId from ttsService
                let effectiveVoiceId = ttsService.selectedVoiceId

                // Find matching local Voice for history tracking
                let voiceToTrack = Voice.builtInVoices.first(where: { $0.id == effectiveVoiceId }) ?? selectedVoice

                let audio = try await ttsService.generate(
                    text: trimmedText,
                    voice: nil, // Passing nil uses ttsService.selectedVoiceId internally
                    speed: voiceSettings.pacing,
                    voiceSettings: voiceSettings
                )

                let generationTime = Date().timeIntervalSince(startTime)
                let audioDuration = Double(audio.count) / Double(KokoroTTSService.sampleRate)

                // Compute waveform on background thread
                let waveform = await Task.detached(priority: .userInitiated) {
                    FloatingAudioPlayer.computeWaveform(from: audio)
                }.value

                withAnimation(MurmurDesign.Animations.panelSlide) {
                    generatedAudio = audio
                    generatedWaveform = waveform
                    generatedFilename = AudioExportService.generateFilename() + ".wav"
                    lastGenerationTime = generationTime
                    lastAudioDuration = audioDuration
                }

                try audioPlayerService.loadAudio(samples: audio)

                historyService.addRecord(
                    text: trimmedText,
                    voice: voiceToTrack,
                    audioSamples: audio,
                    durationSeconds: audioDuration,
                    generationTimeSeconds: generationTime
                )

                // Success toast
                toastManager.showSuccess("Audio ready! \(String(format: "%.1fs", generationTime))")

                if settingsService.settings.autoPlayOnGenerate {
                    audioPlayerService.play()
                }
            } catch {
                if !Task.isCancelled {
                    toastManager.showError(error.localizedDescription)
                }
            }

            isGenerating = false
            generationStartTime = nil
        }
    }

    /// Generate audio from multiple chunks (for PDF imports)
    private func generateFromChunks(_ chunks: [String], documentName: String) {
        guard !chunks.isEmpty else { return }

        // Setup overlay state
        documentGenerationName = documentName
        documentTotalChunks = chunks.count
        documentCurrentChunk = 0
        isGeneratingDocument = true
        isGenerating = true
        let startTime = Date() // Capture locally to avoid @State race conditions
        generationStartTime = startTime

        // Cancel any existing task
        documentGenerationTask?.cancel()

        documentGenerationTask = Task {
            do {
                let audio = try await ttsService.generateChunked(
                    chunks: chunks,
                    voice: nil,
                    speed: voiceSettings.pacing,
                    voiceSettings: voiceSettings,
                    onProgress: { current, total in
                        Task { @MainActor in
                            documentCurrentChunk = current
                        }
                    }
                )

                // Check if cancelled
                try Task.checkCancellation()

                let generationTime = Date().timeIntervalSince(startTime)
                let audioDuration = Double(audio.count) / Double(KokoroTTSService.sampleRate)

                // Compute waveform on background thread
                let waveform = await Task.detached(priority: .userInitiated) {
                    FloatingAudioPlayer.computeWaveform(from: audio)
                }.value

                // Hide overlay first
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isGeneratingDocument = false
                    }
                }

                // Small delay for smooth transition
                try? await Task.sleep(nanoseconds: 200_000_000)

                // Load audio on background thread first (before showing player)
                try await Task.detached(priority: .userInitiated) {
                    try await MainActor.run {
                        try audioPlayerService.loadAudio(samples: audio)
                    }
                }.value

                await MainActor.run {
                    withAnimation(MurmurDesign.Animations.panelSlide) {
                        generatedAudio = audio
                        generatedWaveform = waveform
                        generatedFilename = "\(documentName).wav"
                        lastGenerationTime = generationTime
                        lastAudioDuration = audioDuration
                    }
                }

                // Success toast with duration info
                await MainActor.run {
                    let durationStr = audioDuration >= 60
                        ? String(format: "%.1f min", audioDuration / 60)
                        : String(format: "%.1fs", audioDuration)
                    toastManager.showSuccess("Audio ready! \(durationStr)")

                    // Only autoplay if setting is enabled
                    if settingsService.settings.autoPlayOnGenerate {
                        audioPlayerService.play()
                    }
                }

            } catch is CancellationError {
                await MainActor.run {
                    toastManager.show(.info, message: "Generation cancelled")
                }
            } catch {
                await MainActor.run {
                    toastManager.showError(error.localizedDescription)
                }
            }

            await MainActor.run {
                isGenerating = false
                isGeneratingDocument = false
                generationStartTime = nil
                documentGenerationTask = nil
            }
        }
    }

    /// Cancel ongoing document generation
    private func cancelDocumentGeneration() {
        documentGenerationTask?.cancel()
        ttsService.cancelGeneration()

        withAnimation(.easeOut(duration: 0.3)) {
            isGeneratingDocument = false
            isGenerating = false
        }
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Handle file URLs (including PDFs) - use loadFileRepresentation for better compatibility
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, error in
                    guard let url = url else {
                        DispatchQueue.main.async {
                            self.toastManager.showError("Failed to load file: \(error?.localizedDescription ?? "Unknown error")")
                        }
                        return
                    }

                    // Check if it's a PDF
                    if url.pathExtension.lowercased() == "pdf" {
                        Task { @MainActor in
                            await self.handlePDFImport(url: url)
                        }
                    } else {
                        // Try to read as text file
                        do {
                            let fileContent = try String(contentsOf: url, encoding: .utf8)
                            DispatchQueue.main.async {
                                withAnimation(MurmurDesign.Animations.quick) {
                                    self.text = fileContent
                                }
                                self.toastManager.show(.info, message: "Text loaded from file")
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.toastManager.showError("Could not read file: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                return true
            }

            // Handle plain text
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let droppedText = String(data: data, encoding: .utf8) else { return }

                    DispatchQueue.main.async {
                        withAnimation(MurmurDesign.Animations.quick) {
                            self.text = droppedText
                        }
                        toastManager.show(.info, message: "Text dropped")
                    }
                }
                return true
            }

            // Handle string directly
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { droppedText, _ in
                    guard let droppedText = droppedText else { return }

                    DispatchQueue.main.async {
                        withAnimation(MurmurDesign.Animations.quick) {
                            self.text = droppedText
                        }
                        toastManager.show(.info, message: "Text dropped")
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - Document Import

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select a PDF document to import"
        panel.prompt = "Import"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            Task { @MainActor in
                await handlePDFImport(url: url)
            }
        }
    }

    private func handlePDFImport(url: URL) async {
        isImporting = true
        toastManager.show(.info, message: "Importing PDF...")

        do {
            let result = try await documentImportService.importPDF(url: url)
            importResult = result
            showImportSheet = true
            toastManager.dismiss()
        } catch {
            toastManager.showError(error.localizedDescription)
        }

        isImporting = false
    }

    private func addChunksToQueue(_ chunks: [String]) {
        guard !chunks.isEmpty else { return }

        batchQueueViewModel?.addBlocks(texts: chunks)

        // Show queue panel
        withAnimation(.spring(duration: 0.3)) {
            showQueue = true
            showInspector = true
        }

        toastManager.showSuccess("\(chunks.count) blocks added to queue")
    }

    private func stopGeneration() {
        ttsService.cancelGeneration()
        isGenerating = false
        generationStartTime = nil
        toastManager.dismiss()
        toastManager.show(.info, message: "Generation cancelled")
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
                    await MainActor.run {
                        toastManager.showSuccess("Audio exported successfully")
                    }
                } catch {
                    await MainActor.run {
                        toastManager.showError(error.localizedDescription)
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
    @ObservedObject var audioPlayerService: AudioPlayerService
    let selectedRecordId: UUID?  // Currently selected record for highlighting
    let onClose: () -> Void
    let onReuse: (GenerationRecord) -> Void
    let onSelectRecord: (GenerationRecord) -> Void

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
                                audioPlayerService: audioPlayerService,
                                isSelected: selectedRecordId == record.id,
                                onSelect: { onSelectRecord(record) },
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
}

struct HistoryRow: View {
    let record: GenerationRecord
    @ObservedObject var audioPlayerService: AudioPlayerService
    let isSelected: Bool
    let onSelect: () -> Void
    let onReuse: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var isPlaying: Bool {
        audioPlayerService.playingRecordId == record.id && audioPlayerService.isPlaying
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(record.textPreview)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    // Play indicator if this record is playing
                    if isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(MurmurDesign.Colors.voicePrimary)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 12) {
                    Label(record.voiceName, systemImage: "person.wave.2")
                    Label(record.formattedDuration, systemImage: "waveform")
                    Spacer()
                    Text(record.displayDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? MurmurDesign.Colors.voicePrimary.opacity(0.15) : Color.clear)
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? MurmurDesign.Colors.voicePrimary :
                        (isPlaying ? MurmurDesign.Colors.voicePrimary.opacity(0.5) :
                        (isHovered ? Color.accentColor.opacity(0.3) : .clear)),
                        lineWidth: isSelected ? 2 : (isPlaying ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.2), value: isHovered)
        .animation(.spring(duration: 0.2), value: isPlaying)
        .animation(.spring(duration: 0.2), value: isSelected)
        .contextMenu {
            Button(action: onSelect) {
                Label("Open Player", systemImage: "play.circle")
            }

            Button(action: onReuse) {
                Label("Reuse Text", systemImage: "arrow.uturn.left")
            }

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
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
    var onRetryLoadVoices: (() async -> Void)? = nil
    var suggestedLanguage: Language? = nil
    var onLanguageSelected: ((Language) -> Void)? = nil
    var onVoiceSelected: (() -> Void)? = nil

    @State private var isExpanded = false
    @State private var isRetrying = false
    @State private var expandedLanguages: Set<Language> = []

    /// Group voices by language
    private var voicesByLanguage: [(language: Language, voices: [KokoroVoice])] {
        let grouped = Dictionary(grouping: voices) { voice -> Language in
            voice.language ?? .englishUS
        }

        // Sort languages: suggested first, then by display name
        return Language.allCases
            .filter { grouped[$0] != nil }
            .sorted { lang1, lang2 in
                if lang1 == suggestedLanguage { return true }
                if lang2 == suggestedLanguage { return false }
                return lang1.displayName < lang2.displayName
            }
            .map { ($0, grouped[$0] ?? []) }
    }

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
            HStack {
                Text("Voice")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                // Show current language badge
                if let voice = selectedVoice, let lang = voice.language {
                    HStack(spacing: 4) {
                        Image(systemName: lang.icon)
                            .font(.caption2)
                        Text(lang.shortName)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                }
            }

            // Empty state with retry
            if voices.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No voices available")
                            .foregroundStyle(.secondary)
                        Text("Server may still be loading")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Retry") {
                            Task {
                                isRetrying = true
                                await onRetryLoadVoices?()
                                isRetrying = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
            } else {
                // Selected voice button
                Button {
                    withAnimation(.spring(duration: 0.25, bounce: 0.2)) {
                        isExpanded.toggle()
                        // Auto-expand the selected voice's language
                        if isExpanded, let lang = selectedVoice?.language {
                            expandedLanguages.insert(lang)
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedVoice?.name ?? "Select Voice")
                                .foregroundStyle(.primary)
                            if let voice = selectedVoice {
                                HStack(spacing: 4) {
                                    Text("\(voice.gender.capitalized) • \(voice.accent)")
                                    if !voice.description.isEmpty {
                                        Text("•")
                                        Text(voice.description)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
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

                // Expanded list with language grouping
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

                        // Voice list grouped by language
                        ScrollView {
                            VStack(spacing: 8) {
                                if searchText.isEmpty {
                                    // Grouped view
                                    ForEach(voicesByLanguage, id: \.language) { group in
                                        LanguageVoiceGroup(
                                            language: group.language,
                                            voices: group.voices,
                                            selectedVoiceId: $selectedVoiceId,
                                            isExpanded: expandedLanguages.contains(group.language),
                                            isSuggested: group.language == suggestedLanguage,
                                            onToggle: {
                                                withAnimation(.spring(duration: 0.2)) {
                                                    if expandedLanguages.contains(group.language) {
                                                        expandedLanguages.remove(group.language)
                                                    } else {
                                                        expandedLanguages.insert(group.language)
                                                    }
                                                }
                                            },
                                            onVoiceSelected: { voiceId in
                                                selectedVoiceId = voiceId
                                                self.onVoiceSelected?()
                                                withAnimation(.spring(duration: 0.2)) {
                                                    isExpanded = false
                                                    searchText = ""
                                                }
                                                if let lang = group.language as Language? {
                                                    onLanguageSelected?(lang)
                                                }
                                            }
                                        )
                                    }
                                } else {
                                    // Flat filtered view
                                    ForEach(filteredVoices) { voice in
                                        VoiceRowButton(
                                            voice: voice,
                                            isSelected: selectedVoiceId == voice.id,
                                            onSelect: {
                                                selectedVoiceId = voice.id
                                                onVoiceSelected?()
                                                withAnimation(.spring(duration: 0.2)) {
                                                    isExpanded = false
                                                    searchText = ""
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 300)
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
        .onAppear {
            // Auto-expand suggested language if set
            if let suggested = suggestedLanguage {
                expandedLanguages.insert(suggested)
            }
        }
        .onChange(of: suggestedLanguage) { _, newValue in
            if let lang = newValue {
                withAnimation {
                    expandedLanguages.insert(lang)
                }
            }
        }
    }
}

// MARK: - Language Voice Group

struct LanguageVoiceGroup: View {
    let language: Language
    let voices: [KokoroVoice]
    @Binding var selectedVoiceId: String
    let isExpanded: Bool
    let isSuggested: Bool
    let onToggle: () -> Void
    let onVoiceSelected: (String) -> Void

    private var hasSelectedVoice: Bool {
        voices.contains { $0.id == selectedVoiceId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Language header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Image(systemName: language.icon)
                        .font(.caption)
                        .foregroundStyle(isSuggested ? Color.accentColor : Color.secondary)

                    Text(language.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(hasSelectedVoice ? .primary : .secondary)

                    if isSuggested {
                        Text("Detected")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                    }

                    Spacer()

                    Text("\(voices.count)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if hasSelectedVoice {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSuggested ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 6))

            // Voices in this language
            if isExpanded {
                VStack(spacing: 2) {
                    ForEach(voices) { voice in
                        VoiceRowButton(
                            voice: voice,
                            isSelected: selectedVoiceId == voice.id,
                            onSelect: { onVoiceSelected(voice.id) }
                        )
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }
}

// MARK: - Voice Row Button

struct VoiceRowButton: View {
    let voice: KokoroVoice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(voice.name)
                            .foregroundStyle(.primary)
                        Text(voice.gender == "female" ? "F" : "M")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                        if !voice.description.isEmpty {
                            Text("– \(voice.description)")
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
