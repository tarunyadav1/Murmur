import SwiftUI

struct TextInputView: View {

    @ObservedObject var viewModel: TextInputViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Text to Speak")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    viewModel.clear()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(viewModel.isEmpty)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))

                if viewModel.isEmpty {
                    Text("Enter or paste text to convert to speech...")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 200)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )

            HStack {
                Text("\(viewModel.characterCount) characters")
                Text("•")
                Text("\(viewModel.wordCount) words")
                Text("•")
                Text("~\(viewModel.estimatedDuration)")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}
