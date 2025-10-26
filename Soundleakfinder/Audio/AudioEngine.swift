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

    // Debug counters
    private var bufferCallbackCount: Int = 0
    private var lastLogTime: Date = Date()

    override init() {
        super.init()
        setupAudioEngine()
        requestMicrophonePermission()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        // macOS doesn't use AVAudioSession, audio is managed via Core Audio
        print("Audio engine initialized for macOS")
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() {
        // On macOS, AVAudioEngine handles microphone permission automatically
        // when you try to access the input node. The Info.plist NSMicrophoneUsageDescription
        // is what triggers the system permission dialog.
        // We just check if we can access the input format as a basic check.
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        if format.sampleRate > 0 {
            permissionGranted = true
            print("✅ Microphone access available")
        } else {
            permissionGranted = false
            print("⚠️ Microphone access may be restricted. Check System Settings > Privacy & Security > Microphone")
        }
    }
    
    // MARK: - Audio Engine Control

    func startAudioEngine() {
        do {
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            guard inputFormat.sampleRate > 0 else {
                print("❌ Failed to get valid input format")
                print("   This usually means microphone permission was denied")
                print("   Please grant microphone access in System Settings > Privacy & Security > Microphone")
                return
            }

            // Update permission status
            permissionGranted = true

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
            bufferCallbackCount = 0
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
        print("📊 Total buffer callbacks received: \(bufferCallbackCount)")
    }
    
    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        bufferCallbackCount += 1

        guard let floatChannelData = buffer.floatChannelData else {
            print("⚠️ No float channel data in buffer")
            return
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameLength > 0 && channelCount > 0 else {
            print("⚠️ Invalid buffer: frameLength=\(frameLength), channels=\(channelCount)")
            return
        }

        // Log every 100 callbacks (approximately every 4-5 seconds at 2048 buffer size)
        if bufferCallbackCount % 100 == 0 {
            let elapsed = Date().timeIntervalSince(lastLogTime)
            print("🎵 Buffer callback #\(bufferCallbackCount) - \(frameLength) frames, \(channelCount) channels, \(String(format: "%.1f", elapsed))s elapsed")
            lastLogTime = Date()
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

            // Calculate RMS using vDSP
            var squaredData = [Float](repeating: 0, count: frameLength)
            vDSP_vsq(channelData, 1, &squaredData, 1, vDSP_Length(frameLength))

            var sum: Float = 0.0
            vDSP_sve(squaredData, 1, &sum, vDSP_Length(frameLength))
            sumSquares += sum
        }

        let rms = sqrt(sumSquares / Float(frameLength * channelCount))

        // Log if we detect significant audio
        if bufferCallbackCount <= 10 || (peak > 0.01 && bufferCallbackCount % 50 == 0) {
            print("🔊 Audio levels - Peak: \(String(format: "%.4f", peak)), RMS: \(String(format: "%.4f", rms))")
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.peakLevel = peak
            self.rmsLevel = rms

            // Update sound direction detection
            self.directionDetector.detectDirection(peakLevel: peak, rmsLevel: rms)
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

