import SwiftUI

/// Sheet for previewing imported PDF and generating audio
struct DocumentImportSheet: View {

    let importResult: DocumentImportService.ImportResult
    let onGenerateAudio: ([String]) -> Void  // Pass chunks array for chunked generation
    let onCancel: () -> Void

    @State private var showFullText = false

    /// Combined text from all chunks
    private var combinedText: String {
        importResult.chunks.map { $0.text }.joined(separator: "\n\n")
    }

    private var wordCount: Int {
        combinedText.split(separator: " ").count
    }

    private var estimatedDuration: String {
        let seconds = Double(wordCount) * 0.5
        if seconds < 60 {
            return "\(Int(seconds))s"
        }
        let minutes = Int(seconds / 60)
        let remainingSeconds = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(remainingSeconds)s"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(24)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Document stats
                    statsBar

                    // Text preview
                    textPreview
                }
                .padding(24)
            }

            Divider()

            // Footer
            footer
                .padding(24)
        }
        .frame(width: 580, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            HStack(spacing: 14) {
                // PDF icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 44, height: 44)

                    Image(systemName: "doc.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(importResult.documentName)
                        .font(.headline)
                        .lineLimit(1)

                    Text("PDF Document")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: 0) {
            statItem(icon: "doc.text", value: "\(importResult.pageCount)", label: "Pages")

            Divider()
                .frame(height: 32)
                .padding(.horizontal, 16)

            statItem(icon: "textformat.abc", value: "\(wordCount)", label: "Words")

            Divider()
                .frame(height: 32)
                .padding(.horizontal, 16)

            statItem(icon: "clock", value: estimatedDuration, label: "Est. Duration")

            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Text Preview

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Text Preview")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(showFullText ? "Show Less" : "Show All") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFullText.toggle()
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            Text(combinedText)
                .font(.body)
                .lineLimit(showFullText ? nil : 12)
                .lineSpacing(4)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Info text
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to generate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Audio will be created from the full document")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button {
                    let chunkTexts = importResult.chunks.map { $0.text }
                    onGenerateAudio(chunkTexts)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform")
                        Text("Generate Audio")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(MurmurDesign.Colors.voicePrimary)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    DocumentImportSheet(
        importResult: DocumentImportService.ImportResult(
            documentName: "Sample Document",
            pageCount: 5,
            chunks: [
                DocumentImportService.TextChunk(
                    text: "This is the first chunk of text from the document. It contains some important information that the user might want to convert to speech.",
                    pageNumber: 1
                ),
                DocumentImportService.TextChunk(
                    text: "Here is another chunk with different content. It could be from a different paragraph or section of the PDF.",
                    pageNumber: 1
                ),
            ],
            totalCharacters: 500
        ),
        onGenerateAudio: { chunks in
            print("Generate audio for \(chunks.count) chunks")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
