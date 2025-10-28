import Foundation
import Combine

/// Detects sound levels and provides audio metrics
@MainActor
class SoundLevelDetector: ObservableObject {
    
    @Published var soundLevel: SoundLevel?
    @Published var isDetecting = false
    
    // MARK: - Smoothing Parameters
    
    // Exponential Moving Average (EMA) for smoothing
    private let smoothingFactor: Float = 0.2  // EMA alpha (0-1, lower = more smoothing)
    
    // Signal stability tracking
    private var recentIntensities: [Float] = []
    private let stabilityWindowSize = 10
    
    // Previous values for stability calculation
    private var previousPeak: Float = 0
    private var previousRMS: Float = 0
    
    // Frame counter for periodic updates
    private var frameCounter: Int = 0
    
    /// Detect sound level from audio metrics
    func detectLevel(peakLevel: Float, rmsLevel: Float) {
        frameCounter += 1
        
        // Ultra-low threshold - detect even the quietest sounds
        guard peakLevel > 0.000001 || rmsLevel > 0.0000001 else {
            // Extremely quiet - no detection
            soundLevel = nil
            isDetecting = false
            recentIntensities.removeAll()
            return
        }
        
        isDetecting = true
        
        // Calculate intensity (0-1 scale)
        let intensity = min(1.0, max(peakLevel, rmsLevel * 3.0))
        
        // Track intensity for stability calculation
        recentIntensities.append(intensity)
        if recentIntensities.count > stabilityWindowSize {
            recentIntensities.removeFirst()
        }
        
        // Calculate dB level (0-100 scale)
        let dbLevel = calculateDecibelLevel(peakLevel: peakLevel, rmsLevel: rmsLevel)
        
        // Calculate signal stability
        let stability = calculateSignalStability()
        
        soundLevel = SoundLevel(
            peakLevel: peakLevel,
            rmsLevel: rmsLevel,
            intensity: intensity,
            decibelLevel: dbLevel,
            stability: stability
        )
        
        // Update previous values
        previousPeak = peakLevel
        previousRMS = rmsLevel
    }
    
    /// Calculate decibel level on 0-100 scale for display
    private func calculateDecibelLevel(peakLevel: Float, rmsLevel: Float) -> Float {
        // Use RMS for more stable dB reading
        let level = max(peakLevel, rmsLevel)
        
        // Avoid log of zero
        guard level > 0.000001 else { return 0 }
        
        // Convert to dB (reference: 1.0 = 0 dB)
        // dB = 20 * log10(level)
        let db = 20.0 * log10(level)
        
        // Map dB range to 0-100 scale
        // Typical range: -60 dB (quiet) to 0 dB (max)
        // Map -60 to 0, and 0 to 100
        let normalizedDB = (db + 60.0) / 60.0 * 100.0
        
        // Clamp to 0-100
        return Float(max(0, min(100, normalizedDB)))
    }
    
    /// Calculate signal stability based on recent intensity variance
    /// Returns value between 0 (unstable) and 1 (very stable)
    private func calculateSignalStability() -> Float {
        guard recentIntensities.count >= 3 else {
            return 0.5  // Not enough data, assume moderate stability
        }
        
        // Calculate mean
        let mean = recentIntensities.reduce(0, +) / Float(recentIntensities.count)
        
        // Calculate variance
        let variance = recentIntensities.map { pow($0 - mean, 2) }.reduce(0, +) / Float(recentIntensities.count)
        
        // Convert variance to stability score (lower variance = higher stability)
        // Use exponential decay to map variance to [0, 1]
        let stability = exp(-variance * 10.0)
        
        return min(1.0, max(0.0, stability))
    }
    
    /// Reset detection state
    func reset() {
        soundLevel = nil
        recentIntensities.removeAll()
        isDetecting = false
        previousPeak = 0
        previousRMS = 0
        frameCounter = 0
    }
}

/// Represents detected sound level and properties
struct SoundLevel {
    /// Peak audio level (0-1)
    let peakLevel: Float
    
    /// RMS audio level (0-1)
    let rmsLevel: Float
    
    /// Sound intensity (0-1, where 1 is loudest)
    let intensity: Float
    
    /// Decibel level (0-100 scale for display)
    let decibelLevel: Float
    
    /// Signal stability (0-1, where 1 is very stable)
    let stability: Float
    
    /// Color for visualization based on dB level
    var levelColor: (red: Double, green: Double, blue: Double) {
        if decibelLevel > 75 {
            // Red for very loud sounds
            return (1.0, 0.2, 0.2)
        } else if decibelLevel > 50 {
            // Orange for loud sounds
            return (1.0, 0.6, 0.2)
        } else if decibelLevel > 25 {
            // Yellow for moderate sounds
            return (1.0, 0.9, 0.2)
        } else {
            // Green for quiet sounds
            return (0.3, 0.9, 0.3)
        }
    }
    
    /// Intensity label for display
    var intensityLabel: String {
        if decibelLevel > 75 {
            return "Very Loud"
        } else if decibelLevel > 50 {
            return "Loud"
        } else if decibelLevel > 25 {
            return "Moderate"
        } else {
            return "Quiet"
        }
    }
}

