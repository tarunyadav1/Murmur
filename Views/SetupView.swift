import SwiftUI

/// First-launch setup view with polished, modern Apple design
struct SetupView: View {
    @ObservedObject var pythonEnv: PythonEnvironmentService
    @ObservedObject var serverManager: ServerManager
    let onComplete: () -> Void

    @State private var showRetry = false
    @State private var animateWave = false
    @State private var animatePulse = false

    // Professional teal accent color - conveys trust, privacy, and calm
    private let accentTeal = Color(red: 0.0, green: 0.65, blue: 0.68)

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient

            VStack(spacing: 0) {
                Spacer()

                // Logo and branding
                brandingSection

                Spacer()

                // Status area
                statusSection
                    .frame(height: 180)
                    .padding(.horizontal, 60)

                Spacer()

                // Footer
                if isSettingUp {
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
            await startSetupFlow()
        }
        .onChange(of: serverManager.serverState) { _, newState in
            if newState == .running {
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

            // Subtle radial gradient with professional teal
            RadialGradient(
                colors: [
                    accentTeal.opacity(0.06),
                    Color.clear
                ],
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
            // Animated icon
            ZStack {
                // Outer glow - subtle teal
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentTeal.opacity(0.25),
                                accentTeal.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(animatePulse ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: animatePulse
                    )

                // Inner circle
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                // Icon - solid teal color, no gradient
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
            if case .failed(let error) = pythonEnv.setupState {
                failedView(error: error, isServerError: false)
            } else if case .failed(let error) = serverManager.serverState {
                failedView(error: error, isServerError: true)
            } else if serverManager.serverState == .running && pythonEnv.setupState == .ready {
                readyView
            } else {
                progressView
            }
        }
    }

    // MARK: - Computed Properties

    private var isSettingUp: Bool {
        switch pythonEnv.setupState {
        case .notStarted, .ready:
            return false
        case .failed:
            return false
        default:
            return true
        }
    }

    private var currentStatusMessage: String {
        if pythonEnv.setupState == .ready {
            switch serverManager.serverState {
            case .starting:
                return serverManager.statusMessage.isEmpty ? "Starting up..." : serverManager.statusMessage
            case .running:
                return "Ready"
            case .failed:
                return "Connection issue"
            case .stopped:
                return "Preparing..."
            }
        }

        switch pythonEnv.setupState {
        case .notStarted:
            return "Getting ready..."
        case .checkingPython:
            return "Preparing your Mac..."
        case .creatingEnvironment:
            return "Setting things up..."
        case .installingDependencies:
            return "Installing voice engine..."
        case .ready:
            return "Almost there..."
        case .failed:
            return "Something went wrong"
        }
    }

    // MARK: - Views

    private var progressView: some View {
        VStack(spacing: 20) {
            // Progress ring - solid teal color
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                    .frame(width: 64, height: 64)

                Circle()
                    .trim(from: 0, to: effectiveProgress)
                    .stroke(
                        accentTeal,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: effectiveProgress)

                Text("\(Int(effectiveProgress * 100))%")
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Text(currentStatusMessage)
                    .font(.system(size: 15, weight: .medium))

                if pythonEnv.setupState != .ready || serverManager.serverState != .running {
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
                    .symbolEffect(.bounce, value: serverManager.serverState == .running)
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

    private func failedView(error: String, isServerError: Bool) -> some View {
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
                Text(isServerError ? "Couldn't start" : "Setup didn't complete")
                    .font(.system(size: 16, weight: .semibold))

                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Button(action: isServerError ? retryServer : retrySetup) {
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

    // MARK: - Progress Calculation

    private var effectiveProgress: Double {
        if pythonEnv.setupState == .ready {
            switch serverManager.serverState {
            case .stopped:
                return 0.85
            case .starting:
                return 0.92
            case .running:
                return 1.0
            case .failed:
                return 0.85
            }
        }
        return pythonEnv.setupProgress * 0.85
    }

    // MARK: - Actions

    private func startSetupFlow() async {
        let alreadySetup = await pythonEnv.checkExistingSetup()

        if alreadySetup {
            await serverManager.startServer()
        } else {
            await pythonEnv.setup()

            if pythonEnv.setupState == .ready {
                await serverManager.startServer()
            }
        }
    }

    private func retrySetup() {
        Task {
            await pythonEnv.setup()
            if pythonEnv.setupState == .ready {
                await serverManager.startServer()
            }
        }
    }

    private func retryServer() {
        Task {
            await serverManager.startServer()
        }
    }
}

#Preview {
    SetupView(
        pythonEnv: PythonEnvironmentService(),
        serverManager: ServerManager(pythonEnvironment: PythonEnvironmentService()),
        onComplete: {}
    )
}
