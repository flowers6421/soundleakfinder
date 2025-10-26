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
    @Published var permissionGranted = false

    // Sound direction detection
    let directionDetector = SoundDirectionDetector()

    private let audioEngine = AVAudioEngine()
    private var audioBuffer: AVAudioPCMBuffer?
    private var bufferQueue: DispatchQueue = DispatchQueue(label: "com.soundleakfinder.audio.buffer")
    private var mixer: AVAudioMixerNode?

    // Audio format: 48 kHz, mono, Float32
    private let targetSampleRate: Double = 48000
    private let targetChannels: AVAudioChannelCount = 1

    // Debug counters (accessed from audio thread, use atomic operations)
    private let bufferCallbackCount = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    private var lastLogTime: Date = Date()

    // Pre-allocated buffers to avoid allocations in audio callback
    private var squaredDataBuffer: [Float] = []
    private let maxFrameSize = 4096

    override init() {
        super.init()
        bufferCallbackCount.initialize(to: 0)
        squaredDataBuffer = [Float](repeating: 0, count: maxFrameSize)
        setupAudioEngine()
        requestMicrophonePermission()
    }

    deinit {
        bufferCallbackCount.deallocate()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        // macOS doesn't use AVAudioSession, audio is managed via Core Audio
        print("Audio engine initialized for macOS")
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() {
        // On macOS, microphone access is controlled by System Preferences
        // We check if we have access to the default input device
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        if format.sampleRate > 0 {
            permissionGranted = true
            print("✅ Microphone access available")
        } else {
            print("⚠️ Microphone access may be restricted. Check System Preferences > Security & Privacy > Microphone")
            permissionGranted = false
        }
    }
    
    // MARK: - Audio Engine Control

    func startAudioEngine() {
        do {
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                print("❌ Failed to get valid input format")
                return
            }

            print("📊 Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

            // Create and attach a mixer node
            let mixerNode = AVAudioMixerNode()
            audioEngine.attach(mixerNode)
            self.mixer = mixerNode

            // Connect input to mixer (this enables audio flow without feedback)
            audioEngine.connect(inputNode, to: mixerNode, format: inputFormat)

            // Connect mixer to output with very low volume to prevent feedback
            let outputNode = audioEngine.outputNode
            audioEngine.connect(mixerNode, to: outputNode, format: inputFormat)
            mixerNode.outputVolume = 0.0  // Mute output to prevent feedback

            // Install tap on input node BEFORE starting the engine
            // Use smaller buffer size for more responsive level updates
            print("📍 Installing tap on input node...")
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, time: time)
            }

            // Prepare and start the audio engine
            audioEngine.prepare()
            try audioEngine.start()

            isRunning = true
            bufferCallbackCount.pointee = 0
            lastLogTime = Date()
            print("✅ Audio engine started successfully")
            print("🎤 Listening for audio input...")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }
    }
    
    func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        isRunning = false
        print("🛑 Audio engine stopped")
        print("📊 Total buffer callbacks received: \(bufferCallbackCount.pointee)")
    }
    
    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Atomic increment
        let currentCount = OSAtomicIncrement32Barrier(bufferCallbackCount)

        guard let floatChannelData = buffer.floatChannelData else {
            return  // Don't print in audio callback - too expensive
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameLength > 0 && channelCount > 0 && frameLength <= maxFrameSize else {
            return
        }

        // Calculate peak and RMS levels using vDSP for efficiency
        var peak: Float = 0.0
        var sumSquares: Float = 0.0

        for channel in 0..<channelCount {
            let channelData = floatChannelData[channel]

            // Calculate peak using vDSP (absolute max)
            var channelPeak: Float = 0.0
            var channelMin: Float = 0.0
            vDSP_maxv(channelData, 1, &channelPeak, vDSP_Length(frameLength))
            vDSP_minv(channelData, 1, &channelMin, vDSP_Length(frameLength))
            let absMax = max(abs(channelPeak), abs(channelMin))
            peak = max(peak, absMax)

            // Calculate RMS using vDSP - reuse pre-allocated buffer
            vDSP_vsq(channelData, 1, &squaredDataBuffer, 1, vDSP_Length(frameLength))

            var sum: Float = 0.0
            vDSP_sve(squaredDataBuffer, 1, &sum, vDSP_Length(frameLength))
            sumSquares += sum
        }

        let rms = sqrt(sumSquares / Float(frameLength * channelCount))

        // Update UI on main thread (async to avoid blocking audio thread)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.peakLevel = peak
            self.rmsLevel = rms

            // Update sound direction detection
            self.directionDetector.detectDirection(peakLevel: peak, rmsLevel: rms)

            // Log periodically (only on main thread)
            let count = self.bufferCallbackCount.pointee
            if count % 100 == 0 {
                let elapsed = Date().timeIntervalSince(self.lastLogTime)
                print("🎵 Buffer callback #\(count) - \(frameLength) frames, \(channelCount) channels, \(String(format: "%.1f", elapsed))s elapsed")
                self.lastLogTime = Date()
            }

            // Log if we detect significant audio
            if count <= 10 || (peak > 0.01 && count % 50 == 0) {
                print("🔊 Audio levels - Peak: \(String(format: "%.4f", peak)), RMS: \(String(format: "%.4f", rms))")
                if let direction = self.directionDetector.soundDirection {
                    print("   📍 Direction: \(String(format: "%.0f", direction.angle))°, Intensity: \(String(format: "%.2f", direction.intensity)), Distance: \(direction.distanceString)")
                }
            }
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

