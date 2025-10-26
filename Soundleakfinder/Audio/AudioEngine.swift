import AVFoundation
import Accelerate
import Combine

/// Main audio engine for capturing and processing multi-microphone input
@MainActor
class AudioEngine: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var inputDevices: [AudioDevice] = []
    @Published var selectedDeviceID: AudioDeviceID?
    @Published var peakLevel: Float = 0.0
    @Published var rmsLevel: Float = 0.0
    
    private let audioEngine = AVAudioEngine()
    private var audioBuffer: AVAudioPCMBuffer?
    private var bufferQueue: DispatchQueue = DispatchQueue(label: "com.soundleakfinder.audio.buffer")
    
    // Audio format: 48 kHz, mono, Float32
    private let targetSampleRate: Double = 48000
    private let targetChannels: AVAudioChannelCount = 1
    
    override init() {
        super.init()
        setupAudioEngine()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        // macOS doesn't use AVAudioSession, audio is managed via Core Audio
        print("Audio engine initialized for macOS")
    }
    
    // MARK: - Audio Engine Control
    
    func startAudioEngine() {
        do {
            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            guard format.sampleRate > 0 else {
                print("Failed to get valid input format")
                return
            }
            
            // Create target format: 48 kHz mono Float32
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: targetChannels,
                interleaved: false
            )
            
            guard let targetFormat = targetFormat else {
                print("Failed to create target audio format")
                return
            }
            
            // Attach converter node if needed
            if format.sampleRate != targetSampleRate || format.channelCount != targetChannels {
                guard AVAudioConverter(from: format, to: targetFormat) != nil else {
                    print("Failed to create audio converter")
                    return
                }
            }
            
            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, targetFormat: targetFormat)
            }
            
            try audioEngine.start()
            isRunning = true
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    func stopAudioEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        print("Audio engine stopped")
    }
    
    // MARK: - Audio Processing
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard let floatChannelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        // Calculate peak and RMS levels
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
        
        DispatchQueue.main.async {
            self.peakLevel = peak
            self.rmsLevel = rms
        }
    }
    
    // MARK: - Device Management
    
    func enumerateInputDevices() {
        inputDevices = AudioDeviceManager.shared.getInputDevices()
        if !inputDevices.isEmpty {
            selectedDeviceID = inputDevices[0].id
        }
    }
    
    func selectDevice(_ deviceID: AudioDeviceID) {
        selectedDeviceID = deviceID
        // TODO: Switch audio engine to use this device
    }
}

// MARK: - Audio Device Model

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let name: String
    let manufacturer: String?
    let sampleRates: [Double]
    let channelCount: Int
    let isBuiltIn: Bool
    let isUSB: Bool
    let isBluetooth: Bool
}

// MARK: - Audio Device Manager

class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    func getInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        ) == noErr else {
            print("Failed to get device list size")
            return devices
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            print("Failed to get device list")
            return devices
        }

        for deviceID in deviceIDs {
            if let device = getDeviceInfo(deviceID) {
                devices.append(device)
                print("Found input device: \(device.name) (\(device.channelCount) channels)")
            }
        }

        return devices
    }

    private func getDeviceInfo(_ deviceID: AudioDeviceID) -> AudioDevice? {
        // Check if device has input channels
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr else {
            return nil
        }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferList) == noErr else {
            return nil
        }

        let channelCount = Int(bufferList.pointee.mNumberBuffers)
        guard channelCount > 0 else { return nil }

        // Get device name
        propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
        propertyAddress.mScope = kAudioObjectPropertyScopeGlobal

        var nameRef: CFString? = nil
        dataSize = UInt32(MemoryLayout<CFString>.size)

        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &nameRef) == noErr,
              let name = nameRef as String? else {
            return nil
        }

        // Get manufacturer
        propertyAddress.mSelector = kAudioDevicePropertyDeviceManufacturerCFString
        var manufacturerRef: CFString? = nil
        dataSize = UInt32(MemoryLayout<CFString>.size)

        let manufacturer = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &manufacturerRef) == noErr
            ? (manufacturerRef as String?)
            : nil

        // Get supported sample rates
        let sampleRates = getSupportedSampleRates(deviceID)

        // Determine device type
        let nameLower = name.lowercased()
        let isBuiltIn = nameLower.contains("built-in") || nameLower.contains("internal")
        let isUSB = nameLower.contains("usb")
        let isBluetooth = nameLower.contains("bluetooth") || nameLower.contains("airpods")

        return AudioDevice(
            id: deviceID,
            name: name,
            manufacturer: manufacturer,
            sampleRates: sampleRates,
            channelCount: channelCount,
            isBuiltIn: isBuiltIn,
            isUSB: isUSB,
            isBluetooth: isBluetooth
        )
    }

    private func getSupportedSampleRates(_ deviceID: AudioDeviceID) -> [Double] {
        var sampleRates: [Double] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr else {
            return [48000, 44100] // Default fallback
        }

        let rateCount = Int(dataSize) / MemoryLayout<AudioValueRange>.size
        var rates = [AudioValueRange](repeating: AudioValueRange(), count: rateCount)

        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &rates) == noErr else {
            return [48000, 44100] // Default fallback
        }

        for rate in rates {
            sampleRates.append(rate.mMaximum)
        }

        return sampleRates.sorted(by: >)
    }
}

