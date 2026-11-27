import SwiftUI

struct CircularScanButton: View {
    let title: String
    let subtitle: String
    let isScanning: Bool
    let action: () -> Void

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CompanionTheme.accent.opacity(0.28),
                                CompanionTheme.accent.opacity(0.08),
                                .clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 120
                        )
                    )
                    .frame(width: 220, height: 220)
                    .scaleEffect(isScanning && pulse ? 1.07 : 0.96)
                    .animation(
                        isScanning && !reduceMotion
                            ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                            : .default,
                        value: isScanning && pulse
                    )

                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                CompanionTheme.accent,
                                CompanionTheme.accent.opacity(0.45),
                                CompanionTheme.accent
                            ],
                            center: .center
                        ),
                        lineWidth: isScanning ? 5 : 3
                    )
                    .frame(width: 152, height: 152)
                    .rotationEffect(.degrees(isScanning ? 360 : 0))
                    .animation(
                        isScanning && !reduceMotion
                            ? .linear(duration: 1.6).repeatForever(autoreverses: false)
                            : .default,
                        value: isScanning
                    )

                Circle()
                    .fill(CompanionTheme.accent)
                    .frame(width: 132, height: 132)
                    .shadow(color: CompanionTheme.accent.opacity(0.35), radius: 18, y: 6)

                VStack(spacing: 4) {
                    Image(systemName: isScanning ? AppConstants.Icons.waveform : AppConstants.Icons.arrowClockwise)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.88))
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.65))
                }
            }
            .drawingGroup()
        }
        .buttonStyle(.plain)
        .onChange(of: isScanning) { _, scanning in
            pulse = scanning
        }
    }
}
