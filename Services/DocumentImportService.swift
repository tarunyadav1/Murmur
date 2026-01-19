import Foundation
import PDFKit
import NaturalLanguage
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "DocumentImport")

/// Service for importing PDF documents and extracting text chunks for TTS generation
final class DocumentImportService {

    // MARK: - Types

    enum ImportError: LocalizedError {
        case fileNotFound
        case encryptedPDF
        case emptyDocument
        case imageOnlyPDF
        case extractionFailed(String)
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "File not found"
            case .encryptedPDF:
                return "Cannot read encrypted PDF. Please unlock the file first."
            case .emptyDocument:
                return "Document contains no text"
            case .imageOnlyPDF:
                return "PDF contains only images. OCR not supported."
            case .extractionFailed(let reason):
                return "Text extraction failed: \(reason)"
            case .unsupportedFormat:
                return "Unsupported file format"
            }
        }
    }

    struct ImportResult {
        let documentName: String
        let pageCount: Int
        let chunks: [TextChunk]
        let totalCharacters: Int

        var isEmpty: Bool { chunks.isEmpty }
    }

    struct TextChunk: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let pageNumber: Int?
        var isSelected: Bool = true

        var preview: String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count <= 100 {
                return trimmed
            }
            return String(trimmed.prefix(97)) + "..."
        }

        var wordCount: Int {
            text.split(separator: " ").count
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }

        static func == (lhs: TextChunk, rhs: TextChunk) -> Bool {
            lhs.id == rhs.id
        }
    }

    // MARK: - Configuration

    private let minChunkSize = 400
    private let maxChunkSize = 1000
    private let idealChunkSize = 500

    // MARK: - Public Methods

    /// Import a PDF file and extract text chunks
    func importPDF(url: URL) async throws -> ImportResult {
        logger.info("Importing PDF from: \(url.path)")

        // Verify file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.fileNotFound
        }

        // Load PDF document
        guard let document = PDFDocument(url: url) else {
            throw ImportError.extractionFailed("Failed to open PDF file")
        }

        // Check if encrypted
        if document.isEncrypted && document.isLocked {
            throw ImportError.encryptedPDF
        }

        let pageCount = document.pageCount
        logger.info("PDF has \(pageCount) pages")

        // Extract text from all pages
        var fullText = ""
        var pageTexts: [(pageNumber: Int, text: String)] = []

        for i in 0..<pageCount {
            guard let page = document.page(at: i),
                  let pageText = page.string else {
                continue
            }

            let cleanedText = cleanText(pageText)
            if !cleanedText.isEmpty {
                pageTexts.append((pageNumber: i + 1, text: cleanedText))
                fullText += cleanedText + "\n\n"
            }
        }

        // Check if document has any text
        let trimmedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            // Check if PDF has any content (images)
            if pageCount > 0 {
                throw ImportError.imageOnlyPDF
            }
            throw ImportError.emptyDocument
        }

        // Create chunks using smart chunking algorithm
        let chunks = createChunks(from: pageTexts)

        if chunks.isEmpty {
            throw ImportError.emptyDocument
        }

        logger.info("Created \(chunks.count) chunks from \(trimmedText.count) characters")

        return ImportResult(
            documentName: url.deletingPathExtension().lastPathComponent,
            pageCount: pageCount,
            chunks: chunks,
            totalCharacters: trimmedText.count
        )
    }

    // MARK: - Text Processing

    /// Clean extracted text by removing excessive whitespace and artifacts
    private func cleanText(_ text: String) -> String {
        var cleaned = text

        // Replace multiple spaces with single space
        cleaned = cleaned.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

        // Replace multiple newlines with double newline (paragraph separator)
        cleaned = cleaned.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        // Remove form feed and other control characters
        cleaned = cleaned.replacingOccurrences(of: "[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]", with: "", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Create chunks from page texts using smart chunking algorithm
    private func createChunks(from pageTexts: [(pageNumber: Int, text: String)]) -> [TextChunk] {
        var chunks: [TextChunk] = []

        for (pageNumber, text) in pageTexts {
            // Split into paragraphs first
            let paragraphs = text.components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var currentChunk = ""

            for paragraph in paragraphs {
                // If paragraph alone is larger than max, split it further
                if paragraph.count > maxChunkSize {
                    // Flush current chunk first
                    if !currentChunk.isEmpty {
                        chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
                        currentChunk = ""
                    }

                    // Split large paragraph by sentences
                    let sentenceChunks = splitBySentences(paragraph, pageNumber: pageNumber)
                    chunks.append(contentsOf: sentenceChunks)
                }
                // If adding paragraph would exceed max, flush current chunk
                else if currentChunk.count + paragraph.count + 2 > maxChunkSize {
                    if !currentChunk.isEmpty {
                        chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
                    }
                    currentChunk = paragraph
                }
                // Otherwise, add to current chunk
                else {
                    if currentChunk.isEmpty {
                        currentChunk = paragraph
                    } else {
                        currentChunk += "\n\n" + paragraph
                    }
                }
            }

            // Flush remaining chunk
            if !currentChunk.isEmpty {
                chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
            }
        }

        // Merge small chunks with neighbors
        return mergeSmallChunks(chunks)
    }

    /// Split a large paragraph into sentence-based chunks
    private func splitBySentences(_ text: String, pageNumber: Int) -> [TextChunk] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        // If tokenizer didn't work, fall back to simple split
        if sentences.isEmpty {
            sentences = text.components(separatedBy: ". ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // Group sentences into chunks of appropriate size
        var chunks: [TextChunk] = []
        var currentChunk = ""

        for sentence in sentences {
            // If single sentence is too large, split by word boundary
            if sentence.count > maxChunkSize {
                if !currentChunk.isEmpty {
                    chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
                    currentChunk = ""
                }

                let wordChunks = splitByWords(sentence, pageNumber: pageNumber)
                chunks.append(contentsOf: wordChunks)
            }
            else if currentChunk.count + sentence.count + 1 > maxChunkSize {
                if !currentChunk.isEmpty {
                    chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
                }
                currentChunk = sentence
            }
            else {
                if currentChunk.isEmpty {
                    currentChunk = sentence
                } else {
                    currentChunk += " " + sentence
                }
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
        }

        return chunks
    }

    /// Split text by word boundaries as last resort
    private func splitByWords(_ text: String, pageNumber: Int) -> [TextChunk] {
        let words = text.split(separator: " ")
        var chunks: [TextChunk] = []
        var currentChunk = ""

        for word in words {
            if currentChunk.count + word.count + 1 > maxChunkSize {
                if !currentChunk.isEmpty {
                    chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
                }
                currentChunk = String(word)
            } else {
                if currentChunk.isEmpty {
                    currentChunk = String(word)
                } else {
                    currentChunk += " " + word
                }
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(TextChunk(text: currentChunk, pageNumber: pageNumber))
        }

        return chunks
    }

    /// Merge small chunks with their neighbors
    private func mergeSmallChunks(_ chunks: [TextChunk]) -> [TextChunk] {
        guard chunks.count > 1 else { return chunks }

        var result: [TextChunk] = []
        var i = 0

        while i < chunks.count {
            var currentChunk = chunks[i]

            // Try to merge with next chunk if current is too small
            while currentChunk.text.count < minChunkSize && i + 1 < chunks.count {
                let nextChunk = chunks[i + 1]
                let combinedLength = currentChunk.text.count + nextChunk.text.count + 2

                // Only merge if combined size is acceptable
                if combinedLength <= maxChunkSize {
                    let combinedText = currentChunk.text + "\n\n" + nextChunk.text
                    currentChunk = TextChunk(
                        text: combinedText,
                        pageNumber: currentChunk.pageNumber
                    )
                    i += 1
                } else {
                    break
                }
            }

            result.append(currentChunk)
            i += 1
        }

        return result
    }
}
