import SwiftUI

/// Sound level meter visualization - Minimal Apple design
struct SoundLevelMeterView: View {
    let soundLevel: SoundLevel?
    let isDetecting: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            if let level = soundLevel, isDetecting {
                VStack(spacing: 0) {
                    Spacer()

                    // Main circular meter - hero element
                    ZStack {
                        // Subtle background ring
                        Circle()
                            .stroke(.quaternary, lineWidth: 1)
                            .frame(width: 240, height: 240)

                        // Animated level ring
                        Circle()
                            .trim(from: 0, to: CGFloat(level.decibelLevel / 100.0))
                            .stroke(
                                levelColor(for: level),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 240, height: 240)
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: level.decibelLevel)

                        // Center content
                        VStack(spacing: 8) {
                            Text("\(Int(level.decibelLevel))")
                                .font(.system(size: 72, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())

                            Text("dB")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 48)

                    // Intensity label - minimal
                    Text(level.intensityLabel)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(levelColor(for: level))
                        .padding(.bottom, 64)

                    // Minimal metrics - only essential info
                    HStack(spacing: 48) {
                        VStack(spacing: 4) {
                            Text("PEAK")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .tracking(0.6)
                            Text(String(format: "%.2f", level.peakLevel))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        VStack(spacing: 4) {
                            Text("RMS")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .tracking(0.6)
                            Text(String(format: "%.2f", level.rmsLevel))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                // Waiting state - ultra minimal
                VStack(spacing: 0) {
                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(.quaternary, lineWidth: 1)
                            .frame(width: 240, height: 240)

                        VStack(spacing: 8) {
                            Text("--")
                                .font(.system(size: 72, weight: .semibold, design: .rounded))
                                .foregroundStyle(.quaternary)

                            Text("dB")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.bottom, 48)

                    Text("Waiting...")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 64)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            colorScheme == .dark ?
                Color(red: 0.11, green: 0.11, blue: 0.12) :
                Color(red: 0.98, green: 0.98, blue: 0.99)
        )
    }

    // MARK: - Helper Functions

    private func levelColor(for level: SoundLevel) -> Color {
        if level.decibelLevel > 75 {
            return .red
        } else if level.decibelLevel > 50 {
            return .orange
        } else if level.decibelLevel > 25 {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Preview
#Preview("Active") {
    SoundLevelMeterView(
        soundLevel: SoundLevel(
            peakLevel: 0.8,
            rmsLevel: 0.6,
            intensity: 0.75,
            decibelLevel: 65,
            stability: 0.85
        ),
        isDetecting: true
    )
    .frame(width: 600, height: 600)
}

#Preview("Waiting") {
    SoundLevelMeterView(
        soundLevel: nil,
        isDetecting: false
    )
    .frame(width: 600, height: 600)
}

