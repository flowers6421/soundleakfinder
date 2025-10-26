import AVFoundation
import Accelerate

/// GCC-PHAT (Generalized Cross-Correlation with Phase Transform) processor
/// Implements TDOA (Time Difference of Arrival) estimation for acoustic source localization
class GCCPHATProcessor {

    // MARK: - Configuration

    /// Sample rate (48 kHz)
    let sampleRate: Float = 48000.0

    /// Speed of sound in m/s (at ~20°C)
    let speedOfSound: Float = 343.0

    /// Frame size for processing
    let frameSize: Int

    /// Hann window for windowing (DISABLED for maximum sensitivity)
    private var hannWindow: [Float]

    /// Maximum sensitivity mode - detect ALL sounds including very quiet ones
    var maximumSensitivity: Bool = true

    /// Minimum threshold for detection (ultra-low to catch even quieter sounds)
    var minimumDetectionThreshold: Float = 1e-15  // Ultra-low threshold for maximum sensitivity

    // MARK: - Initialization

    init(frameSize: Int = 2048) {
        self.frameSize = frameSize
        self.hannWindow = [Float](repeating: 0, count: frameSize)

        // Create Hann window
        var window = [Float](repeating: 0, count: frameSize)
        vDSP_hann_window(&window, vDSP_Length(frameSize), Int32(vDSP_HANN_NORM))
        self.hannWindow = window
    }
    
    // MARK: - TDOA Estimation

    /// Estimate Time Difference of Arrival (TDOA) between two audio signals
    /// - Parameters:
    ///   - signal1: First audio signal (Float array)
    ///   - signal2: Second audio signal (Float array)
    ///   - maxLag: Maximum lag to search (in samples)
    /// - Returns: TDOA result containing delay in samples and confidence
    func estimateTDOA(signal1: [Float], signal2: [Float], maxLag: Int? = nil) -> TDOAResult {
        guard signal1.count == signal2.count else {
            return TDOAResult(delaySamples: 0, delaySeconds: 0, confidence: 0, peakValue: 0)
        }

        let frameLength = signal1.count
        let searchLag = maxLag ?? frameLength / 2

        // For MAXIMUM SENSITIVITY: Skip windowing to preserve all signal energy
        // Windowing reduces edge effects but also reduces sensitivity to quiet sounds
        var processedSignal1 = signal1
        var processedSignal2 = signal2

        if !maximumSensitivity {
            // Only apply window if not in maximum sensitivity mode
            vDSP_vmul(processedSignal1, 1, hannWindow, 1, &processedSignal1, 1, vDSP_Length(min(frameLength, frameSize)))
            vDSP_vmul(processedSignal2, 1, hannWindow, 1, &processedSignal2, 1, vDSP_Length(min(frameLength, frameSize)))
        }

        // Compute cross-correlation with PHAT weighting
        let crossCorrelation = computeCrossCorrelationWithPHAT(processedSignal1, processedSignal2)

        // Find peak in cross-correlation
        let (peakIndex, peakValue) = findPeak(in: crossCorrelation, maxLag: searchLag)

        // Convert peak index to delay in samples
        let centerIdx = crossCorrelation.count / 2
        let delaySamples = peakIndex - centerIdx
        let delaySeconds = Float(delaySamples) / sampleRate

        // Calculate confidence based on peak prominence
        let confidence = calculateConfidence(crossCorrelation, peakIndex: peakIndex, peakValue: peakValue)

        return TDOAResult(
            delaySamples: delaySamples,
            delaySeconds: delaySeconds,
            confidence: confidence,
            peakValue: peakValue
        )
    }
    
    // MARK: - Private DSP Methods

    /// Compute cross-correlation with PHAT weighting
    /// Cross-correlation: R[lag] = sum(signal1[i] * signal2[i - lag])
    /// Positive lag means signal2 is delayed relative to signal1
    private func computeCrossCorrelationWithPHAT(_ signal1: [Float], _ signal2: [Float]) -> [Float] {
        let n = signal1.count
        var crossCorrelation = [Float](repeating: 0, count: 2 * n - 1)

        // Compute cross-correlation for all lags
        // Output index ranges from 0 to (2*n-2)
        // Corresponding to lags from -(n-1) to (n-1)
        for outputIdx in 0..<(2 * n - 1) {
            let lag = outputIdx - (n - 1)  // Convert to signed lag: -(n-1) to (n-1)
            var sum: Float = 0.0
            var sumSquares1: Float = 0.0
            var sumSquares2: Float = 0.0
            var count = 0

            // For each sample in signal1
            for i in 0..<n {
                // Corresponding index in signal2 is i - lag
                let j = i - lag
                if j >= 0 && j < n {
                    let s1 = signal1[i]
                    let s2 = signal2[j]

                    sum += s1 * s2
                    sumSquares1 += s1 * s1
                    sumSquares2 += s2 * s2
                    count += 1
                }
            }

            // PHAT weighting: normalize by magnitude
            // Use VERY LOW threshold for maximum sensitivity to detect quiet sounds
            let threshold = maximumSensitivity ? minimumDetectionThreshold : 1e-10
            if count > 0 && sumSquares1 > threshold && sumSquares2 > threshold {
                let magnitude = sqrt(sumSquares1 * sumSquares2)
                crossCorrelation[outputIdx] = sum / magnitude
            } else if count > 0 {
                // Even for very quiet signals, preserve the correlation value
                crossCorrelation[outputIdx] = sum
            }
        }

        return crossCorrelation
    }
    
    /// Find peak in cross-correlation
    private func findPeak(in correlation: [Float], maxLag: Int) -> (index: Int, value: Float) {
        let centerIdx = correlation.count / 2
        let searchStart = max(0, centerIdx - maxLag)
        let searchEnd = min(correlation.count, centerIdx + maxLag)
        
        var maxValue: Float = -Float.infinity
        var maxIndex = centerIdx
        
        for i in searchStart..<searchEnd {
            if correlation[i] > maxValue {
                maxValue = correlation[i]
                maxIndex = i
            }
        }
        
        return (maxIndex, maxValue)
    }
    
    /// Calculate confidence metric based on peak prominence
    private func calculateConfidence(_ correlation: [Float], peakIndex: Int, peakValue: Float) -> Float {
        guard peakValue > 0 else { return 0 }
        
        // Find second highest peak
        var secondPeak: Float = 0
        let searchRadius = 100
        
        for i in max(0, peakIndex - searchRadius)..<min(correlation.count, peakIndex + searchRadius) {
            if i != peakIndex && correlation[i] > secondPeak {
                secondPeak = correlation[i]
            }
        }
        
        // Confidence is ratio of main peak to second peak
        if secondPeak > 0 {
            return min(1.0, peakValue / (secondPeak + 1e-10))
        }
        
        return min(1.0, peakValue)
    }
}

// MARK: - TDOA Result

struct TDOAResult {
    /// Delay in samples (positive = signal2 leads signal1)
    let delaySamples: Int
    
    /// Delay in seconds
    let delaySeconds: Float
    
    /// Confidence metric (0-1)
    let confidence: Float
    
    /// Peak value of cross-correlation
    let peakValue: Float
    
    /// Estimated distance between microphones (in meters)
    /// Requires knowledge of microphone positions
    func estimatedDistance(speedOfSound: Float = 343.0) -> Float {
        return abs(delaySeconds) * speedOfSound
    }
}

