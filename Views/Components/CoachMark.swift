import SwiftUI

// MARK: - Onboarding Manager

@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var currentStep: OnboardingStep?
    @Published var hasCompletedOnboarding: Bool

    private let completedKey = "murmur.onboarding.completed"
    private let seenTipsKey = "murmur.onboarding.seenTips"

    private var seenTips: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenTipsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenTipsKey) }
    }

    enum OnboardingStep: String, CaseIterable {
        case welcome
        case createButton
        case voiceSelector
        case dragDrop
        case keyboard

        var title: String {
            switch self {
            case .welcome: return "Welcome to Murmur"
            case .createButton: return "Create Audio"
            case .voiceSelector: return "Choose a Voice"
            case .dragDrop: return "Drag & Drop"
            case .keyboard: return "Keyboard Power"
            }
        }

        var message: String {
            switch self {
            case .welcome: return "Turn your words into natural speech. Let's show you around!"
            case .createButton: return "Type your text and press Create (or ⌘↩) to generate audio instantly."
            case .voiceSelector: return "Pick from many voices. Each has its own personality."
            case .dragDrop: return "Drop text files here, or drag audio out to save it anywhere."
            case .keyboard: return "Use ⌘↩ to create, Space to play/pause. You're all set!"
            }
        }

        var icon: String {
            switch self {
            case .welcome: return "waveform.circle.fill"
            case .createButton: return "waveform"
            case .voiceSelector: return "person.wave.2"
            case .dragDrop: return "arrow.up.doc"
            case .keyboard: return "keyboard"
            }
        }

        var next: OnboardingStep? {
            guard let currentIndex = OnboardingStep.allCases.firstIndex(of: self),
                  currentIndex + 1 < OnboardingStep.allCases.count else { return nil }
            return OnboardingStep.allCases[currentIndex + 1]
        }
    }

    private init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: completedKey)
    }

    func startOnboarding() {
        guard !hasCompletedOnboarding else { return }
        withAnimation(MurmurDesign.Animations.panelSlide) {
            currentStep = .welcome
        }
    }

    func nextStep() {
        guard let current = currentStep else { return }

        if let next = current.next {
            withAnimation(MurmurDesign.Animations.panelSlide) {
                currentStep = next
            }
        } else {
            completeOnboarding()
        }
    }

    func skipOnboarding() {
        completeOnboarding()
    }

    private func completeOnboarding() {
        withAnimation(MurmurDesign.Animations.panelSlide) {
            currentStep = nil
            hasCompletedOnboarding = true
            UserDefaults.standard.set(true, forKey: completedKey)
        }
    }

    func showTip(_ tipId: String) -> Bool {
        guard !seenTips.contains(tipId) else { return false }
        return true
    }

    func markTipSeen(_ tipId: String) {
        var tips = seenTips
        tips.insert(tipId)
        seenTips = tips
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = nil
        seenTips = []
        UserDefaults.standard.removeObject(forKey: completedKey)
    }
}

// MARK: - Coach Mark View

struct CoachMarkView: View {
    let step: OnboardingManager.OnboardingStep
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            cardContent
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
        .onAppear {
            withAnimation(MurmurDesign.Animations.breathing) {
                isAnimating = true
            }
        }
    }

    private var cardContent: some View {
        VStack(spacing: 24) {
            iconView
            textContent
            progressDots
            buttonRow
        }
        .padding(32)
        .background(cardBackground)
    }

    private var iconView: some View {
        ZStack {
            Circle()
                .fill(MurmurDesign.Colors.voicePrimary.opacity(0.15))
                .frame(width: 80, height: 80)
                .scaleEffect(isAnimating ? 1.1 : 1.0)

            Image(systemName: step.icon)
                .font(.system(size: 32))
                .foregroundStyle(MurmurDesign.Colors.voicePrimary)
        }
    }

    private var textContent: some View {
        VStack(spacing: 12) {
            Text(step.title)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.rounded)

            Text(step.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingManager.OnboardingStep.allCases, id: \.self) { s in
                let isActive = s == step
                Circle()
                    .fill(isActive ? MurmurDesign.Colors.voicePrimary : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 8)
    }

    private var buttonRow: some View {
        HStack(spacing: 16) {
            Button(action: onSkip) {
                Text("Skip")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button(action: onNext) {
                HStack(spacing: 6) {
                    Text(step.next == nil ? "Get Started" : "Next")
                    if step.next != nil {
                        Image(systemName: "arrow.right")
                            .font(.caption)
                    }
                }
                .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(MurmurDesign.Colors.voicePrimary)
        }
        .padding(.top, 8)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.2), radius: 40, y: 20)
    }
}

// MARK: - Keyboard Tip Nudge

struct KeyboardTipNudge: View {
    let message: String
    let keys: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: MurmurDesign.Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.subheadline)

            KeyboardHint(keys: keys)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MurmurDesign.Spacing.md)
        .padding(.vertical, MurmurDesign.Spacing.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
}

// MARK: - Onboarding Overlay Modifier

struct OnboardingOverlay: ViewModifier {
    @ObservedObject var onboardingManager = OnboardingManager.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if let step = onboardingManager.currentStep {
                    CoachMarkView(
                        step: step,
                        onNext: onboardingManager.nextStep,
                        onSkip: onboardingManager.skipOnboarding
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(MurmurDesign.Animations.panelSlide, value: onboardingManager.currentStep)
    }
}

extension View {
    func withOnboarding() -> some View {
        modifier(OnboardingOverlay())
    }
}

// MARK: - Preview

#Preview("Coach Mark") {
    CoachMarkView(
        step: .welcome,
        onNext: {},
        onSkip: {}
    )
    .frame(width: 600, height: 500)
}

#Preview("Keyboard Tip") {
    VStack {
        KeyboardTipNudge(
            message: "Pro tip: Press",
            keys: "⌘↩",
            onDismiss: {}
        )
    }
    .frame(width: 400, height: 200)
    .background(Color(NSColor.windowBackgroundColor))
}
