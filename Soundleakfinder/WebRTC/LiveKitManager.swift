import Foundation
import Combine

/// Manages WebRTC connection and remote audio streaming via LiveKit
class LiveKitManager: NSObject, ObservableObject {
    
    @Published var isConnected = false
    @Published var remoteParticipants: [RemoteParticipant] = []
    @Published var connectionError: String?
    @Published var remoteAudioLevels: [String: Float] = [:]
    
    private let bufferQueue = DispatchQueue(label: "com.soundleakfinder.livekit")
    
    // LiveKit connection parameters
    private var serverUrl: String = ""
    private var token: String = ""
    private var roomName: String = ""
    
    // Audio buffers for remote participants
    private var remoteAudioBuffers: [String: CircularAudioBuffer] = [:]
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - Connection Management
    
    /// Connect to LiveKit server
    /// - Parameters:
    ///   - serverUrl: LiveKit server URL (e.g., "wss://livekit.example.com")
    ///   - token: Access token for authentication
    ///   - roomName: Room name to join
    func connect(serverUrl: String, token: String, roomName: String) {
        self.serverUrl = serverUrl
        self.token = token
        self.roomName = roomName
        
        bufferQueue.async { [weak self] in
            self?.performConnection()
        }
    }
    
    private func performConnection() {
        print("🔗 Connecting to LiveKit: \(serverUrl), Room: \(roomName)")
        
        // TODO: Implement actual LiveKit connection
        // For now, simulate connection
        DispatchQueue.main.async {
            self.isConnected = true
            print("✅ Connected to LiveKit")
        }
    }
    
    /// Disconnect from LiveKit
    func disconnect() {
        bufferQueue.async { [weak self] in
            print("🔌 Disconnecting from LiveKit")
            DispatchQueue.main.async {
                self?.isConnected = false
                self?.remoteParticipants = []
                self?.remoteAudioBuffers.removeAll()
            }
        }
    }
    
    // MARK: - Remote Audio Handling
    
    /// Add remote audio frame from a participant
    func addRemoteAudioFrame(_ frame: [Float], fromParticipantID participantID: String) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create buffer if needed
            if self.remoteAudioBuffers[participantID] == nil {
                self.remoteAudioBuffers[participantID] = CircularAudioBuffer(capacity: 48000 * 2)
            }
            
            self.remoteAudioBuffers[participantID]?.append(contentsOf: frame)
            
            // Calculate level
            var peak: Float = 0.0
            for sample in frame {
                peak = max(peak, abs(sample))
            }
            
            DispatchQueue.main.async {
                self.remoteAudioLevels[participantID] = peak
            }
        }
    }
    
    /// Get remote audio frames for a participant
    func getRemoteAudioFrames(participantID: String, count: Int) -> [Float] {
        guard let buffer = remoteAudioBuffers[participantID] else {
            return []
        }
        return buffer.getLatestFrames(count: count)
    }
    
    // MARK: - Participant Management
    
    /// Add a remote participant
    func addRemoteParticipant(id: String, name: String) {
        let participant = RemoteParticipant(id: id, name: name)
        DispatchQueue.main.async {
            if !self.remoteParticipants.contains(where: { $0.id == id }) {
                self.remoteParticipants.append(participant)
                print("👤 Remote participant added: \(name)")
            }
        }
    }
    
    /// Remove a remote participant
    func removeRemoteParticipant(id: String) {
        DispatchQueue.main.async {
            self.remoteParticipants.removeAll { $0.id == id }
            self.remoteAudioBuffers.removeValue(forKey: id)
            self.remoteAudioLevels.removeValue(forKey: id)
            print("👤 Remote participant removed: \(id)")
        }
    }
}

// MARK: - Remote Participant Model

struct RemoteParticipant: Identifiable {
    let id: String
    let name: String
    var audioLevel: Float = 0.0
    var isAudioEnabled: Bool = true
}

// Note: CircularAudioBuffer is defined in TDOAManager.swift

