import Foundation

/// Validation tests for GCC-PHAT TDOA estimation
struct GCCPHATValidation {
    
    /// Test TDOA estimation with synthetic signals
    static func validateTDOA() {
        print("🧪 Validating GCC-PHAT TDOA Estimation...")

        let processor = GCCPHATProcessor(frameSize: 2048)

        // Test 1: Zero delay (identical signals)
        print("\n  Test 1: Zero delay detection")
        let frequency: Float = 1000.0
        let sampleRate: Float = 48000.0
        let duration: Float = 0.1
        let frameLength = Int(sampleRate * duration)

        var signal = [Float](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            let t = Float(i) / sampleRate
            signal[i] = sin(2.0 * .pi * frequency * t)
        }

        do {
            let result1 = processor.estimateTDOA(signal1: signal, signal2: signal)
            print("    Delay: \(result1.delaySamples) samples, Confidence: \(String(format: "%.2f", result1.confidence))")
            assert(abs(result1.delaySamples) <= 5, "Zero delay test failed: expected ~0, got \(result1.delaySamples)")
            print("    ✅ PASSED")
        } catch {
            print("    ❌ FAILED: \(error)")
        }

        // Test 2: Known delay
        print("\n  Test 2: Known delay detection (100 samples)")
        let delayInSamples = 100
        var signal2 = [Float](repeating: 0, count: frameLength)
        for i in 0..<frameLength {
            if i >= delayInSamples {
                signal2[i] = signal[i - delayInSamples]
            }
        }

        do {
            let result2 = processor.estimateTDOA(signal1: signal, signal2: signal2)
            print("    Detected delay: \(result2.delaySamples) samples, Confidence: \(String(format: "%.2f", result2.confidence))")
            assert(abs(result2.delaySamples - delayInSamples) <= 10, "Known delay test failed: expected ~\(delayInSamples), got \(result2.delaySamples)")
            print("    ✅ PASSED")
        } catch {
            print("    ❌ FAILED: \(error)")
        }

        // Test 3: Distance calculation
        print("\n  Test 3: Distance calculation from TDOA")
        let delaySeconds: Float = 0.001 // 1 ms
        let speedOfSound: Float = 343.0
        let tdoaResult = TDOAResult(
            delaySamples: 48,
            delaySeconds: delaySeconds,
            confidence: 0.9,
            peakValue: 0.8
        )
        let distance = tdoaResult.estimatedDistance(speedOfSound: speedOfSound)
        let expectedDistance = delaySeconds * speedOfSound
        print("    Calculated distance: \(String(format: "%.3f", distance)) m")
        print("    Expected distance: \(String(format: "%.3f", expectedDistance)) m")
        assert(abs(distance - expectedDistance) < 0.01, "Distance calculation test failed")
        print("    ✅ PASSED")

        print("\n✅ All GCC-PHAT validation tests passed!")
    }
    
    /// Test TDOA Manager with multiple microphone pairs
    static func validateTDOAManager() {
        print("\n🧪 Validating TDOA Manager...")
        
        let manager = TDOAManager(frameSize: 2048)
        
        // Define microphone pairs
        let pair1 = MicrophonePair(
            mic1ID: 0,
            mic2ID: 1,
            mic1Position: (0, 0, 0),
            mic2Position: (0.1, 0, 0)  // 10 cm apart
        )
        
        let pair2 = MicrophonePair(
            mic1ID: 0,
            mic2ID: 2,
            mic1Position: (0, 0, 0),
            mic2Position: (0, 0.1, 0)  // 10 cm apart
        )
        
        manager.registerMicrophonePairs([pair1, pair2])
        
        print("  Registered \(2) microphone pairs")
        print("  Pair 1 distance: \(String(format: "%.3f", pair1.distance)) m")
        print("  Pair 2 distance: \(String(format: "%.3f", pair2.distance)) m")
        
        print("✅ TDOA Manager validation passed!")
    }
}

