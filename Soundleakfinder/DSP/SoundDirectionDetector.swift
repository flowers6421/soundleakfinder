import Foundation
import Combine

/// Detects sound source direction and intensity
@MainActor
class SoundDirectionDetector: ObservableObject {
    
    @Published var soundDirection: SoundDirection?
    @Published var isDetecting = false
    
    // Smoothing for stable direction estimates
    private var directionHistory: [SoundDirection] = []
    private let historySize = 5  // Average over last 5 detections
    
    /// Detect sound direction from audio level
    /// For now, uses a simple model based on audio intensity
    /// In future: integrate with TDOA for multi-microphone direction finding
    func detectDirection(peakLevel: Float, rmsLevel: Float) {
        // MUCH lower threshold - detect even very quiet sounds
        // This allows detection of ambient noise and quiet sounds
        guard peakLevel > 0.00001 || rmsLevel > 0.000001 else {
            // Extremely quiet - no clear direction
            soundDirection = nil
            isDetecting = false
            return
        }

        isDetecting = true
        
        // Calculate intensity (0-1 scale)
        let intensity = min(1.0, max(peakLevel, rmsLevel * 3.0))
        
        // For single microphone: simulate direction based on intensity variations
        // This is a placeholder - real direction requires multiple microphones
        // The angle will vary based on audio characteristics
        let angle = calculateAngleFromAudioCharacteristics(peak: peakLevel, rms: rmsLevel)
        
        // Calculate confidence based on signal strength
        let confidence = min(1.0, intensity * 2.0)
        
        // Estimate distance (inverse relationship with intensity)
        let distance = estimateDistance(intensity: intensity)
        
        let newDirection = SoundDirection(
            angle: angle,
            intensity: intensity,
            confidence: confidence,
            distance: distance
        )
        
        // Add to history for smoothing
        directionHistory.append(newDirection)
        if directionHistory.count > historySize {
            directionHistory.removeFirst()
        }
        
        // Calculate smoothed direction
        soundDirection = smoothDirection(directionHistory)
    }
    
    /// Calculate angle from audio characteristics
    /// This is a simplified model - real implementation needs TDOA from multiple mics
    private func calculateAngleFromAudioCharacteristics(peak: Float, rms: Float) -> Double {
        // Use audio characteristics to estimate direction
        // This creates variation based on signal properties
        let ratio = peak / max(rms, 0.0001)
        let baseAngle = Double(ratio * 180.0).truncatingRemainder(dividingBy: 360.0)
        
        // Add some temporal variation for demonstration
        let timeVariation = sin(Date().timeIntervalSinceReferenceDate) * 30.0
        
        return (baseAngle + timeVariation).truncatingRemainder(dividingBy: 360.0)
    }
    
    /// Estimate distance based on intensity
    private func estimateDistance(intensity: Float) -> Float {
        // Inverse square law approximation
        // Louder sounds are closer
        if intensity > 0.7 {
            return 0.5  // Very close (< 0.5m)
        } else if intensity > 0.4 {
            return 1.5  // Close (1-2m)
        } else if intensity > 0.2 {
            return 3.0  // Medium (2-4m)
        } else {
            return 5.0  // Far (> 4m)
        }
    }
    
    /// Smooth direction estimates using moving average
    private func smoothDirection(_ history: [SoundDirection]) -> SoundDirection? {
        guard !history.isEmpty else { return nil }
        
        // Average the angles (handling circular nature)
        var sinSum: Double = 0
        var cosSum: Double = 0
        var intensitySum: Float = 0
        var confidenceSum: Float = 0
        var distanceSum: Float = 0
        
        for direction in history {
            let radians = direction.angle * .pi / 180.0
            sinSum += sin(radians)
            cosSum += cos(radians)
            intensitySum += direction.intensity
            confidenceSum += direction.confidence
            distanceSum += direction.distance
        }
        
        let count = Float(history.count)
        let avgAngle = atan2(sinSum, cosSum) * 180.0 / .pi
        let normalizedAngle = avgAngle < 0 ? avgAngle + 360.0 : avgAngle
        
        return SoundDirection(
            angle: normalizedAngle,
            intensity: intensitySum / count,
            confidence: confidenceSum / count,
            distance: distanceSum / count
        )
    }
    
    /// Reset detection state
    func reset() {
        soundDirection = nil
        directionHistory.removeAll()
        isDetecting = false
    }
}

/// Represents detected sound source direction and properties
struct SoundDirection {
    /// Angle in degrees (0° = front, 90° = right, 180° = back, 270° = left)
    let angle: Double
    
    /// Sound intensity (0-1, where 1 is loudest)
    let intensity: Float
    
    /// Confidence of detection (0-1)
    let confidence: Float
    
    /// Estimated distance in meters
    let distance: Float
    
    /// Color for visualization based on intensity
    var intensityColor: (red: Double, green: Double, blue: Double) {
        if intensity > 0.7 {
            // Red for loud sounds
            return (1.0, 0.2, 0.2)
        } else if intensity > 0.4 {
            // Yellow for moderate sounds
            return (1.0, 0.8, 0.2)
        } else {
            // Green for quiet sounds
            return (0.3, 0.9, 0.3)
        }
    }
    
    /// Formatted distance string
    var distanceString: String {
        if distance < 1.0 {
            return String(format: "%.1fm", distance)
        } else {
            return String(format: "%.0fm", distance)
        }
    }
}

