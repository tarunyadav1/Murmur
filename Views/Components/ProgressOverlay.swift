import SwiftUI

struct ProgressOverlay: View {

    let progress: Double
    let message: String

    init(progress: Double, message: String = "Loading...") {
        self.progress = progress
        self.message = message
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)

                Text(message)
                    .font(.headline)
                    .foregroundColor(.white)

                if progress > 0 && progress < 1 {
                    ProgressView(value: progress)
                        .frame(width: 200)

                    Text("\(Int(progress * 100))%")
                        .foregroundColor(.white)
                        .monospacedDigit()
                }

                Text("Please wait...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
        }
    }
}
