import SwiftUI

struct SpeedControlView: View {

    @Binding var speed: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speed")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1fx", speed))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("0.5x")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Slider(
                    value: $speed,
                    in: Constants.Speed.minimum...Constants.Speed.maximum,
                    step: Constants.Speed.step
                )

                Text("2.0x")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(Constants.Speed.presets, id: \.self) { preset in
                    Button(formatPreset(preset)) {
                        speed = preset
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(speed == preset ? .accentColor : nil)
                }
            }
        }
    }

    private func formatPreset(_ value: Float) -> String {
        if value == Float(Int(value)) {
            return "\(Int(value))x"
        }
        return String(format: "%.2gx", value)
    }
}
