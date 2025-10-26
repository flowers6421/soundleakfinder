import AVFoundation
import Combine

/// Manages TDOA estimation for multiple microphone pairs
@MainActor
class TDOAManager: ObservableObject {

    @Published var tdoaResults: [MicrophonePair: TDOAResult] = [:]
    @Published var isProcessing = false
    
    private let gccPhatProcessor: GCCPHATProcessor
    private let bufferQueue = DispatchQueue(label: "com.soundleakfinder.tdoa")

    // Audio buffers for each microphone
    private var audioBuffers: [Int: CircularAudioBuffer] = [:]

    // Microphone pair definitions
    private var microphonePairs: [MicrophonePair] = []

    init(frameSize: Int = 2048) {
        self.gccPhatProcessor = GCCPHATProcessor(frameSize: frameSize)
    }
    
    // MARK: - Configuration
    
    /// Register microphone pairs for TDOA estimation
    func registerMicrophonePairs(_ pairs: [MicrophonePair]) {
        self.microphonePairs = pairs
        
        // Initialize buffers for each microphone
        for pair in pairs {
            if audioBuffers[pair.mic1ID] == nil {
                audioBuffers[pair.mic1ID] = CircularAudioBuffer(capacity: 48000 * 2) // 2 seconds
            }
            if audioBuffers[pair.mic2ID] == nil {
                audioBuffers[pair.mic2ID] = CircularAudioBuffer(capacity: 48000 * 2)
            }
        }
    }
    
    // MARK: - Audio Processing
    
    /// Add audio frame from a microphone
    func addAudioFrame(_ frame: [Float], fromMicrophoneID micID: Int) {
        bufferQueue.async { [weak self] in
            self?.audioBuffers[micID]?.append(contentsOf: frame)
        }
    }
    
    /// Process TDOA for all registered microphone pairs
    func processTDOA() {
        guard !microphonePairs.isEmpty else { return }
        
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = true
            }
            
            var results: [MicrophonePair: TDOAResult] = [:]
            
            for pair in self.microphonePairs {
                guard let buffer1 = self.audioBuffers[pair.mic1ID],
                      let buffer2 = self.audioBuffers[pair.mic2ID] else {
                    continue
                }
                
                // Get latest frames from buffers
                let frameSize = 2048
                let signal1 = buffer1.getLatestFrames(count: frameSize)
                let signal2 = buffer2.getLatestFrames(count: frameSize)
                
                guard signal1.count == frameSize && signal2.count == frameSize else {
                    continue
                }
                
                // Estimate TDOA
                let tdoa = self.gccPhatProcessor.estimateTDOA(signal1: signal1, signal2: signal2)
                results[pair] = tdoa
            }
            
            DispatchQueue.main.async {
                self.tdoaResults = results
                self.isProcessing = false
            }
        }
    }
    
    /// Get TDOA result for a specific microphone pair
    func getTDOA(for pair: MicrophonePair) -> TDOAResult? {
        return tdoaResults[pair]
    }
}

// MARK: - Microphone Pair Definition

struct MicrophonePair: Hashable, Identifiable {
    let mic1ID: Int
    let mic2ID: Int
    
    /// Position of microphone 1 (x, y, z in meters)
    let mic1Position: (Float, Float, Float)
    
    /// Position of microphone 2 (x, y, z in meters)
    let mic2Position: (Float, Float, Float)
    
    var id: String {
        "\(mic1ID)-\(mic2ID)"
    }
    
    /// Distance between microphones in meters
    var distance: Float {
        let dx = mic2Position.0 - mic1Position.0
        let dy = mic2Position.1 - mic1Position.1
        let dz = mic2Position.2 - mic1Position.2
        return sqrt(dx * dx + dy * dy + dz * dz)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(mic1ID)
        hasher.combine(mic2ID)
    }
    
    static func == (lhs: MicrophonePair, rhs: MicrophonePair) -> Bool {
        return lhs.mic1ID == rhs.mic1ID && lhs.mic2ID == rhs.mic2ID
    }
}

// MARK: - Circular Audio Buffer

/// Circular buffer for storing audio frames
class CircularAudioBuffer {
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private let capacity: Int
    private let lock = NSLock()
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }
    
    /// Append audio samples to buffer
    func append(contentsOf samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        
        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
    }
    
    /// Get latest N frames from buffer
    func getLatestFrames(count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        guard count <= capacity else { return [] }
        
        var result = [Float](repeating: 0, count: count)
        let startIndex = (writeIndex - count + capacity) % capacity
        
        if startIndex + count <= capacity {
            // No wrap-around
            result = Array(buffer[startIndex..<(startIndex + count)])
        } else {
            // Wrap-around case
            let firstPart = capacity - startIndex
            result[0..<firstPart] = buffer[startIndex..<capacity][0..<firstPart]
            result[firstPart..<count] = buffer[0..<(count - firstPart)][0..<(count - firstPart)]
        }
        
        return result
    }
    
    /// Clear buffer
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        
        buffer = [Float](repeating: 0, count: capacity)
        writeIndex = 0
    }
}

