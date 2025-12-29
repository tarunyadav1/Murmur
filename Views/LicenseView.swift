import SwiftUI

/// License activation view - shown when user needs to enter license
struct LicenseView: View {
    @ObservedObject var licenseService: LicenseService
    let onActivated: () -> Void

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var animatePulse = false

    // Professional teal accent - matches SetupView
    private let accentTeal = Color(red: 0.0, green: 0.65, blue: 0.68)

    var body: some View {
        ZStack {
            // Background
            backgroundGradient

            VStack(spacing: 0) {
                Spacer()

                // Logo and branding
                brandingSection

                Spacer()

                // License form
                licenseFormSection
                    .frame(maxWidth: 400)
                    .padding(.horizontal, 60)

                Spacer()

                // Footer
                footerSection
                    .padding(.bottom, 30)
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .task {
            animatePulse = true
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
            // Animated icon
            ZStack {
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
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: animatePulse
                    )

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)

                Image(systemName: "key.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(accentTeal)
            }

            VStack(spacing: 8) {
                Text("Murmur")
                    .font(.system(size: 36, weight: .semibold, design: .default))

                Text("Enter your license key to continue")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - License Form

    private var licenseFormSection: some View {
        VStack(spacing: 20) {
            // License key input
            VStack(alignment: .leading, spacing: 8) {
                Text("License Key")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                TextField("XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX", text: $licenseService.licenseKeyInput)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                showError ? Color.red.opacity(0.5) : Color.secondary.opacity(0.2),
                                lineWidth: 1
                            )
                    )
                    .disabled(licenseService.validationState == .validating)
                    .onSubmit {
                        activateLicense()
                    }
            }

            // Error message
            if showError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Activate button
            Button(action: activateLicense) {
                HStack(spacing: 8) {
                    if licenseService.validationState == .validating {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                    }
                    Text(licenseService.validationState == .validating ? "Validating..." : "Activate License")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentTeal)
            .disabled(
                licenseService.licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                licenseService.validationState == .validating
            )
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .animation(.spring(duration: 0.3), value: showError)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Text("Don't have a license?")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let url = URL(string: Constants.License.gumroadPurchaseURL) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("Purchase on Gumroad")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .foregroundStyle(accentTeal)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func activateLicense() {
        guard licenseService.validationState != .validating else { return }

        showError = false

        Task {
            do {
                _ = try await licenseService.validateLicense()

                // Success animation delay
                try? await Task.sleep(for: .milliseconds(500))
                onActivated()

            } catch {
                withAnimation {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

#Preview {
    LicenseView(
        licenseService: LicenseService(),
        onActivated: {}
    )
}
