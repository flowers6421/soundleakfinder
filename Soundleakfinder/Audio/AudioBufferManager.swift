import AVFoundation
import Accelerate

/// Manages audio buffer conversion and format standardization
class AudioBufferManager {
    static let shared = AudioBufferManager()
    
    // Target format: 48 kHz, mono, Float32
    let targetSampleRate: Double = 48000
    let targetChannels: AVAudioChannelCount = 1
    let targetFormat: AVAudioFormat
    
    private var converters: [Int: AVAudioConverter] = [:]
    
    init() {
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) ?? AVAudioFormat()
    }
    
    /// Convert an audio buffer to the target format (48 kHz mono Float32)
    /// - Parameter buffer: Input audio buffer
    /// - Returns: Converted buffer in target format, or nil if conversion failed
    func convertToTargetFormat(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let sourceFormat = buffer.format
        
        // If already in target format, return as-is
        if sourceFormat.sampleRate == targetSampleRate &&
           sourceFormat.channelCount == targetChannels &&
           sourceFormat.commonFormat == .pcmFormatFloat32 {
            return buffer
        }
        
        // Get or create converter
        let converterKey = Int(sourceFormat.sampleRate) * 1000 + Int(sourceFormat.channelCount)
        
        if converters[converterKey] == nil {
            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                print("Failed to create audio converter from \(sourceFormat) to \(targetFormat)")
                return nil
            }
            converters[converterKey] = converter
        }
        
        guard let converter = converters[converterKey] else {
            return nil
        }
        
        // Calculate output frame capacity
        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            print("Failed to allocate output buffer")
            return nil
        }
        
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error {
            print("Audio conversion error: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        return outputBuffer
    }
    
    /// Downmix multi-channel audio to mono
    /// - Parameter buffer: Input audio buffer (may be multi-channel)
    /// - Returns: Mono audio buffer
    func downmixToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // If already mono, return as-is
        if channelCount == 1 {
            return buffer
        }
        
        // Create mono output buffer
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("Failed to create mono format")
            return nil
        }

        guard let monoBuffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: AVAudioFrameCount(frameLength)
        ) else {
            print("Failed to allocate mono buffer")
            return nil
        }
        
        monoBuffer.frameLength = AVAudioFrameCount(frameLength)
        
        guard let monoChannelData = monoBuffer.floatChannelData else {
            return nil
        }
        
        // Average all channels into mono
        let monoData = monoChannelData[0]
        
        for frame in 0..<frameLength {
            var sum: Float = 0.0
            for channel in 0..<channelCount {
                sum += floatChannelData[channel][frame]
            }
            monoData[frame] = sum / Float(channelCount)
        }
        
        return monoBuffer
    }
    
    /// Resample audio buffer to target sample rate using linear interpolation
    /// - Parameter buffer: Input audio buffer
    /// - Returns: Resampled buffer at target sample rate
    func resampleToTargetRate(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }
        
        let sourceRate = buffer.format.sampleRate
        let sourceFrameLength = Int(buffer.frameLength)
        
        if sourceRate == targetSampleRate {
            return buffer
        }
        
        let ratio = targetSampleRate / sourceRate
        let outputFrameLength = Int(Double(sourceFrameLength) * ratio)

        guard let resampleFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: buffer.format.channelCount,
            interleaved: false
        ) else {
            print("Failed to create resample format")
            return nil
        }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: resampleFormat,
            frameCapacity: AVAudioFrameCount(outputFrameLength)
        ) else {
            print("Failed to allocate resampled buffer")
            return nil
        }
        
        outputBuffer.frameLength = AVAudioFrameCount(outputFrameLength)
        
        guard let outputChannelData = outputBuffer.floatChannelData else {
            return nil
        }
        
        // Linear interpolation resampling for each channel
        for channel in 0..<Int(buffer.format.channelCount) {
            let inputData = floatChannelData[channel]
            let outputData = outputChannelData[channel]
            
            for outFrame in 0..<outputFrameLength {
                let sourceFrame = Double(outFrame) / ratio
                let frameIndex = Int(sourceFrame)
                let fraction = Float(sourceFrame - Double(frameIndex))
                
                if frameIndex + 1 < sourceFrameLength {
                    let sample1 = inputData[frameIndex]
                    let sample2 = inputData[frameIndex + 1]
                    outputData[outFrame] = sample1 * (1.0 - fraction) + sample2 * fraction
                } else if frameIndex < sourceFrameLength {
                    outputData[outFrame] = inputData[frameIndex]
                } else {
                    outputData[outFrame] = 0.0
                }
            }
        }
        
        return outputBuffer
    }
    
    /// Calculate peak and RMS levels for a buffer
    /// - Parameter buffer: Input audio buffer
    /// - Returns: Tuple of (peak, rms) levels
    func calculateLevels(_ buffer: AVAudioPCMBuffer) -> (peak: Float, rms: Float) {
        guard let floatChannelData = buffer.floatChannelData else {
            return (0.0, 0.0)
        }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var peak: Float = 0.0
        var sumSquares: Float = 0.0
        
        for channel in 0..<channelCount {
            let channelData = floatChannelData[channel]
            for frame in 0..<frameLength {
                let sample = abs(channelData[frame])
                peak = max(peak, sample)
                sumSquares += sample * sample
            }
        }
        
        let rms = sqrt(sumSquares / Float(frameLength * channelCount))
        
        return (peak, rms)
    }
}

