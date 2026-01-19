import SwiftUI

/// Simplified setup view for native Swift model loading
/// Replaces SetupView.swift which required Python environment setup
struct ModelSetupView: View {
    @ObservedObject var ttsService: KokoroTTSService
    let onComplete: () -> Void

    @State private var animateWave = false
    @State private var animatePulse = false

    // Professional teal accent color - matches original SetupView
    private let accentTeal = Color(red: 0.0, green: 0.65, blue: 0.68)

    var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                Spacer()
                brandingSection
                Spacer()
                statusSection
                    .frame(height: 180)
                    .padding(.horizontal, 60)
                Spacer()

                if ttsService.isLoading {
                    Text("Setting up your private voice engine")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 30)
                        .transition(.opacity)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task {
            animateWave = true
            animatePulse = true
            await loadModel()
        }
        .onChange(of: ttsService.isModelLoaded) { _, isLoaded in
            if isLoaded {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onComplete()
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
            RadialGradient(
                colors: [accentTeal.opacity(0.06), Color.clear],
                center: .top,
                startRadius: 100,
                endRadius: 400
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Branding

    private var brandingSection: some View {
        VStack(spacing: 20) {
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accentTeal.opacity(0.25), accentTeal.opacity(0.0)],
                            center: .center,
                            startRadius: 40,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(animatePulse ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: animatePulse)

                // Inner circle
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                // Icon
                Image(systemName: "waveform")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(accentTeal)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: animateWave)
            }

            VStack(spacing: 8) {
                Text("Murmur")
                    .font(.system(size: 36, weight: .semibold, design: .default))
                Text("Private Voice Generation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Group {
            if let error = ttsService.lastError {
                failedView(error: error.localizedDescription)
            } else if ttsService.isModelLoaded {
                readyView
            } else {
                progressView
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 20) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    .frame(width: 64, height: 64)

                Circle()
                    .trim(from: 0, to: ttsService.loadingProgress)
                    .stroke(accentTeal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: ttsService.loadingProgress)

                Text("\(Int(ttsService.loadingProgress * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Text(ttsService.loadingMessage.isEmpty ? "Loading..." : ttsService.loadingMessage)
                    .font(.system(size: 15, weight: .medium))

                if ttsService.isLoading && ttsService.loadingProgress < 0.5 {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("This only happens once")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var readyView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentTeal.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(accentTeal)
                    .symbolEffect(.bounce, value: ttsService.isModelLoaded)
            }

            Text("You're all set")
                .font(.system(size: 16, weight: .semibold))
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accentTeal.opacity(0.3), lineWidth: 1)
        )
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: 8) {
                Text("Setup didn't complete")
                    .font(.system(size: 16, weight: .semibold))
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Button(action: { Task { await loadModel() } }) {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentTeal)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func loadModel() async {
        do {
            try await ttsService.loadModel()
        } catch {
            // Error is captured in ttsService.lastError
        }
    }
}

#Preview {
    ModelSetupView(
        ttsService: KokoroTTSService(),
        onComplete: {}
    )
}
