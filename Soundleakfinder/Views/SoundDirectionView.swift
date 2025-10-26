import SwiftUI

/// Cute and minimal visual indicator showing sound source direction
struct SoundDirectionView: View {
    let direction: SoundDirection?
    let isDetecting: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Sound Direction")
                .font(.headline)
            
            ZStack {
                // Background circle (radar-style)
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                    .frame(width: 200, height: 200)
                
                // Inner circles for depth
                Circle()
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                    .frame(width: 150, height: 150)
                
                Circle()
                    .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                    .frame(width: 100, height: 100)
                
                // Center dot (you are here)
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                
                // Cardinal direction labels
                VStack {
                    Text("N")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("S")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(height: 220)
                
                HStack {
                    Text("W")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("E")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .frame(width: 220)
                
                // Direction arrow
                if let direction = direction, isDetecting {
                    DirectionArrow(direction: direction)
                        .frame(width: 200, height: 200)
                } else {
                    // No detection indicator
                    Text("🔇")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.3))
                }
            }
            .frame(width: 240, height: 240)
            
            // Direction info
            if let direction = direction, isDetecting {
                VStack(spacing: 4) {
                    HStack(spacing: 16) {
                        // Intensity indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(
                                    red: direction.intensityColor.red,
                                    green: direction.intensityColor.green,
                                    blue: direction.intensityColor.blue
                                ))
                                .frame(width: 12, height: 12)
                            Text(intensityLabel(direction.intensity))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Distance
                        HStack(spacing: 4) {
                            Image(systemName: "ruler")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(direction.distanceString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Angle
                    Text("\(String(format: "%.0f", direction.angle))°")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Confidence bar
                    HStack(spacing: 4) {
                        Text("Confidence:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ProgressView(value: Double(direction.confidence), total: 1.0)
                            .frame(width: 80)
                        Text(String(format: "%.0f%%", direction.confidence * 100))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Listening for sounds...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func intensityLabel(_ intensity: Float) -> String {
        if intensity > 0.7 {
            return "Loud"
        } else if intensity > 0.4 {
            return "Moderate"
        } else {
            return "Quiet"
        }
    }
}

/// Animated arrow pointing toward sound source
struct DirectionArrow: View {
    let direction: SoundDirection
    
    var body: some View {
        ZStack {
            // Pulsing circle at arrow tip (sound source location)
            Circle()
                .fill(Color(
                    red: direction.intensityColor.red,
                    green: direction.intensityColor.green,
                    blue: direction.intensityColor.blue
                ).opacity(0.3))
                .frame(width: 30, height: 30)
                .offset(y: -70)  // Position at arrow tip
                .scaleEffect(pulseScale)
                .animation(
                    Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // Arrow shape
            ArrowShape()
                .fill(Color(
                    red: direction.intensityColor.red,
                    green: direction.intensityColor.green,
                    blue: direction.intensityColor.blue
                ))
                .frame(width: 40, height: 80)
                .shadow(color: Color(
                    red: direction.intensityColor.red,
                    green: direction.intensityColor.green,
                    blue: direction.intensityColor.blue
                ).opacity(0.5), radius: 8)
        }
        .rotationEffect(.degrees(direction.angle))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: direction.angle)
    }
    
    private var pulseScale: CGFloat {
        1.0 + CGFloat(direction.intensity) * 0.5
    }
}

/// Custom arrow shape
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        // Arrow pointing up
        path.move(to: CGPoint(x: width / 2, y: 0))  // Tip
        path.addLine(to: CGPoint(x: width * 0.2, y: height * 0.4))  // Left wing
        path.addLine(to: CGPoint(x: width * 0.4, y: height * 0.4))  // Left shaft
        path.addLine(to: CGPoint(x: width * 0.4, y: height))  // Left bottom
        path.addLine(to: CGPoint(x: width * 0.6, y: height))  // Right bottom
        path.addLine(to: CGPoint(x: width * 0.6, y: height * 0.4))  // Right shaft
        path.addLine(to: CGPoint(x: width * 0.8, y: height * 0.4))  // Right wing
        path.closeSubpath()
        
        return path
    }
}

// Preview
#Preview {
    VStack(spacing: 20) {
        // With detection
        SoundDirectionView(
            direction: SoundDirection(
                angle: 45,
                intensity: 0.8,
                confidence: 0.9,
                distance: 1.5
            ),
            isDetecting: true
        )
        
        // No detection
        SoundDirectionView(
            direction: nil,
            isDetecting: false
        )
    }
    .padding()
    .frame(width: 400)
}

