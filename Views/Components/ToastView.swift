import SwiftUI

// MARK: - Toast Types

enum ToastType {
    case success
    case error
    case info
    case generating

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .generating: return "waveform"
        }
    }

    var color: Color {
        switch self {
        case .success: return MurmurDesign.Colors.success
        case .error: return MurmurDesign.Colors.error
        case .info: return MurmurDesign.Colors.voicePrimary
        case .generating: return MurmurDesign.Colors.warning
        }
    }
}

// MARK: - Toast Model

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let message: String
    var duration: TimeInterval = 3.0
    var action: (() -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast Manager

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(_ toast: Toast) {
        dismissTask?.cancel()

        withAnimation(MurmurDesign.Animations.toastIn) {
            currentToast = toast
        }

        // Auto-dismiss unless it's a generating toast
        if toast.type != .generating {
            dismissTask = Task {
                try? await Task.sleep(for: .seconds(toast.duration))
                if !Task.isCancelled {
                    dismiss()
                }
            }
        }
    }

    func show(_ type: ToastType, message: String, duration: TimeInterval = 3.0) {
        show(Toast(type: type, message: message, duration: duration))
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(MurmurDesign.Animations.toastOut) {
            currentToast = nil
        }
    }

    func showSuccess(_ message: String) {
        show(.success, message: message)
    }

    func showError(_ message: String) {
        show(.error, message: message, duration: 5.0)
    }

    func showGenerating() {
        show(.generating, message: "Creating your audio...")
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon with animation
            ZStack {
                Circle()
                    .fill(toast.type.color.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: toast.type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(toast.type.color)
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeating,
                        isActive: toast.type == .generating
                    )
            }
            .softGlow(toast.type.color, radius: 6, isActive: toast.type == .generating)

            // Message
            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)

            Spacer(minLength: 8)

            // Dismiss button (on hover or generating)
            if isHovered || toast.type == .generating {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                        .padding(6)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: MurmurDesign.Radius.lg)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: MurmurDesign.Radius.lg)
                .strokeBorder(toast.type.color.opacity(0.3), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .animation(MurmurDesign.Animations.quick, value: isHovered)
    }
}

// MARK: - Toast Container

struct ToastContainer: View {
    @ObservedObject var toastManager = ToastManager.shared

    var body: some View {
        VStack {
            HStack {
                Spacer()
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast, onDismiss: toastManager.dismiss)
                        .frame(maxWidth: 360)
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .topTrailing)),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            )
                        )
                }
            }
            Spacer()
        }
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                ToastContainer()
            }
    }
}

extension View {
    func withToasts() -> some View {
        modifier(ToastModifier())
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ToastView(toast: Toast(type: .success, message: "Audio generated successfully!"), onDismiss: {})
        ToastView(toast: Toast(type: .error, message: "Failed to connect to server"), onDismiss: {})
        ToastView(toast: Toast(type: .generating, message: "Creating your audio..."), onDismiss: {})
        ToastView(toast: Toast(type: .info, message: "Try pressing ⌘↩ to generate faster"), onDismiss: {})
    }
    .padding(40)
    .frame(width: 500, height: 400)
}
