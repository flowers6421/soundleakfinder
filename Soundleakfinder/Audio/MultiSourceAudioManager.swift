import AVFoundation
import Combine

/// Manages audio from multiple sources (local microphones + remote WebRTC)
@MainActor
class MultiSourceAudioManager: ObservableObject {
    
    @Published var audioSources: [AudioSource] = []
    @Published var isProcessing = false
    
    private let audioEngine: AudioEngine
    private let liveKitManager: LiveKitManager
    private let tdoaManager: TDOAManager
    private let processingQueue = DispatchQueue(label: "com.soundleakfinder.multisource")
    
    // Audio source registry
    private var sourceRegistry: [String: AudioSourceInfo] = [:]
    
    init(audioEngine: AudioEngine, liveKitManager: LiveKitManager, tdoaManager: TDOAManager) {
        self.audioEngine = audioEngine
        self.liveKitManager = liveKitManager
        self.tdoaManager = tdoaManager
    }
    
    // MARK: - Source Management
    
    /// Register a local microphone as an audio source
    func registerLocalMicrophone(deviceID: AudioDeviceID, name: String) {
        let sourceID = "local_\(deviceID)"
        let source = AudioSourceInfo(
            id: sourceID,
            name: name,
            type: .localMicrophone,
            deviceID: deviceID,
            position: (0, 0, 0)  // Default position at origin
        )
        sourceRegistry[sourceID] = source
        updateAudioSources()
        print("📍 Registered local microphone: \(name)")
    }
    
    /// Register a remote participant as an audio source
    func registerRemoteParticipant(participantID: String, name: String, position: (Float, Float, Float)) {
        let sourceID = "remote_\(participantID)"
        let source = AudioSourceInfo(
            id: sourceID,
            name: name,
            type: .remoteParticipant,
            participantID: participantID,
            position: position
        )
        sourceRegistry[sourceID] = source
        updateAudioSources()
        print("📍 Registered remote participant: \(name)")
    }
    
    /// Unregister an audio source
    func unregisterSource(sourceID: String) {
        sourceRegistry.removeValue(forKey: sourceID)
        updateAudioSources()
    }
    
    // MARK: - Audio Processing
    
    /// Process audio from all sources for TDOA estimation
    func processMultiSourceAudio() {
        guard !sourceRegistry.isEmpty else { return }
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isProcessing = true
            }
            
            // Get audio frames from all sources
            var audioFrames: [String: [Float]] = [:]
            
            for (sourceID, sourceInfo) in self.sourceRegistry {
                let frameSize = 2048
                var frames: [Float] = []
                
                switch sourceInfo.type {
                case .localMicrophone:
                    // TODO: Get frames from local microphone
                    frames = [Float](repeating: 0, count: frameSize)
                case .remoteParticipant:
                    if let participantID = sourceInfo.participantID {
                        frames = self.liveKitManager.getRemoteAudioFrames(
                            participantID: participantID,
                            count: frameSize
                        )
                    }
                }
                
                audioFrames[sourceID] = frames
            }
            
            // Process TDOA for all source pairs
            self.processTDOAPairs(audioFrames: audioFrames)
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
    
    private func processTDOAPairs(audioFrames: [String: [Float]]) {
        let sourceIDs = Array(audioFrames.keys).sorted()
        
        for i in 0..<sourceIDs.count {
            for j in (i+1)..<sourceIDs.count {
                let sourceID1 = sourceIDs[i]
                let sourceID2 = sourceIDs[j]
                
                guard let frames1 = audioFrames[sourceID1],
                      let frames2 = audioFrames[sourceID2],
                      !frames1.isEmpty && !frames2.isEmpty else {
                    continue
                }
                
                // Estimate TDOA between this pair
                let processor = GCCPHATProcessor(frameSize: 2048)
                let tdoa = processor.estimateTDOA(signal1: frames1, signal2: frames2)
                
                print("📊 TDOA(\(sourceID1), \(sourceID2)): \(tdoa.delaySamples) samples, confidence: \(String(format: "%.2f", tdoa.confidence))")
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func updateAudioSources() {
        let sources = sourceRegistry.values.map { info in
            AudioSource(
                id: info.id,
                name: info.name,
                type: info.type,
                position: info.position
            )
        }
        DispatchQueue.main.async {
            self.audioSources = sources.sorted { $0.name < $1.name }
        }
    }
}

// MARK: - Audio Source Models

struct AudioSource: Identifiable {
    let id: String
    let name: String
    let type: AudioSourceType
    let position: (Float, Float, Float)
}

enum AudioSourceType {
    case localMicrophone
    case remoteParticipant
}

struct AudioSourceInfo {
    let id: String
    let name: String
    let type: AudioSourceType
    var deviceID: AudioDeviceID?
    var participantID: String?
    let position: (Float, Float, Float)
}

