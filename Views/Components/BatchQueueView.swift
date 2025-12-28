import SwiftUI

struct BatchQueueView: View {

    @ObservedObject var viewModel: BatchQueueViewModel
    @Binding var selectedVoice: Voice
    @Binding var speed: Float
    var voiceSettings: VoiceSettings = .default

    @State private var newBlockText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Add new block
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(.tertiary)
                    TextField("Add text block...", text: $newBlockText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            addBlock()
                        }
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

                Button {
                    addBlock()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .disabled(newBlockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)

            Divider()
                .padding(.horizontal, 20)

            // Queue list
            if viewModel.blocks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.blocks) { block in
                            BatchQueueRow(
                                block: block,
                                onRemove: {
                                    withAnimation(.spring(duration: 0.2)) {
                                        viewModel.removeBlock(id: block.id)
                                    }
                                },
                                onPlay: {
                                    try? viewModel.playBlock(id: block.id)
                                },
                                onRetry: {
                                    Task {
                                        await viewModel.retryBlock(
                                            id: block.id,
                                            voice: selectedVoice,
                                            speed: speed,
                                            voiceSettings: voiceSettings
                                        )
                                    }
                                }
                            )
                        }
                        .onMove { from, to in
                            viewModel.moveBlock(from: from, to: to)
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
                .padding(.horizontal, 20)

            // Actions footer
            actionsFooter
                .padding(20)
        }
        .frame(minWidth: 280)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
                .symbolEffect(.pulse, options: .repeating)

            VStack(spacing: 4) {
                Text("No items in queue")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Add text blocks above to batch process")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var actionsFooter: some View {
        HStack(spacing: 12) {
            // Clear buttons
            Menu {
                Button("Clear All", role: .destructive) {
                    withAnimation {
                        viewModel.clearQueue()
                    }
                }
                if viewModel.hasCompletedBlocks {
                    Button("Clear Completed") {
                        withAnimation {
                            viewModel.clearCompleted()
                        }
                    }
                }
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .menuStyle(.borderlessButton)
            .disabled(viewModel.blocks.isEmpty)

            Spacer()

            // Progress or Generate button
            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)

                    Text("\(viewModel.completedCount)/\(viewModel.totalCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            } else {
                Button {
                    Task {
                        await viewModel.generateAll(
                            voice: selectedVoice,
                            speed: speed,
                            voiceSettings: voiceSettings
                        )
                    }
                } label: {
                    Label("Generate All", systemImage: "waveform")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.blocks.isEmpty || !viewModel.hasPendingBlocks)
            }
        }
    }

    private func addBlock() {
        let trimmed = newBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(.spring(duration: 0.3)) {
            viewModel.addBlock(text: trimmed)
        }
        newBlockText = ""
    }
}

struct BatchQueueRow: View {

    let block: TextBlock
    let onRemove: () -> Void
    let onPlay: () -> Void
    let onRetry: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                statusIcon
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(block.preview)
                        .font(.subheadline)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Text("\(block.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isHovered || block.status != .pending {
                    actionButtons
                        .transition(.scale.combined(with: .opacity))
                }
            }

            if let error = block.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(.red)
                .padding(.leading, 36)
            }

            if block.status == .generating {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.leading, 36)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.2), value: isHovered)
    }

    private var borderColor: Color {
        switch block.status {
        case .completed:
            return .green.opacity(0.3)
        case .failed:
            return .red.opacity(0.3)
        case .generating:
            return .accentColor.opacity(0.3)
        default:
            return isHovered ? .accentColor.opacity(0.2) : .clear
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch block.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)

        case .generating:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, options: .repeating)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: block.status)

        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            if block.status == .completed {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("Play")
            }

            if block.status == .failed {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Retry")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
    }
}
