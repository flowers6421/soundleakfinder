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

    // Sensitivity control (0.1 to 2.0, default 1.0 = middle)
    @Published var sensitivity: Float = 1.0 {
        didSet {
            updateSensitivity()
        }
    }

    // Sound level detection
    let levelDetector = SoundLevelDetector()

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

    // MARK: - Sensitivity Enhancement State
    // Pre-amplification (in dB) applied only for metering/detection, not to audio output
    // Base gain at sensitivity = 1.0 (middle)
    private let basePreGainDB: Float = 12.0
    private var preGainDB: Float = 12.0
    private var preGain: Float { pow(10.0, preGainDB / 20.0) }

    // Adaptive noise floor (EMA of quiet frames)
    private var noiseFloorRMS: Float = 0.005
    private var noiseFloorPeak: Float = 0.008
    private let noiseEMAAlphaQuiet: Float = 0.01   // slow rise
    private let noiseEMAAlphaIdle: Float = 0.002   // very slow when signal present

    // Attack/Release smoothing for UI stability
    private let levelAttack: Float = 0.35
    private let levelRelease: Float = 0.08
    private var smoothedRMSLevel: Float = 0.0
    private var smoothedPeakLevel: Float = 0.0

    // SNR-based detection threshold (in dB)
    private var snrThresholdDB: Float = 1.5

    // Extra visual scaling to make low signals visible
    private var levelScale: Float = 4.0

    // MARK: - Sensitivity Control

    private func updateSensitivity() {
        // Map sensitivity (0.1 to 2.0) to gain adjustment
        // sensitivity = 0.1 -> -20 dB (very low)
        // sensitivity = 1.0 -> 0 dB (default, middle)
        // sensitivity = 2.0 -> +12 dB (very high)

        let gainAdjustmentDB: Float
        if sensitivity < 1.0 {
            // Below middle: scale from -20 dB to 0 dB
            gainAdjustmentDB = (sensitivity - 1.0) * 20.0
        } else {
            // Above middle: scale from 0 dB to +12 dB
            gainAdjustmentDB = (sensitivity - 1.0) * 12.0
        }

        preGainDB = basePreGainDB + gainAdjustmentDB
        print("🎚️ Sensitivity: \(Int(sensitivity * 100))% | Gain: \(String(format: "%.1f", preGainDB)) dB")
    }

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
        // On macOS, we need to explicitly request microphone permission using AVCaptureDevice
        // This ensures the permission dialog appears and the TCC database is properly updated
        Task { @MainActor in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                self.permissionGranted = true
                print("✅ Microphone access already authorized")

            case .notDetermined:
                print("🎤 Requesting microphone permission...")
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                self.permissionGranted = granted
                if granted {
                    print("✅ Microphone permission granted")
                } else {
                    print("❌ Microphone permission denied")
                    print("   Please grant microphone access in System Settings > Privacy & Security > Microphone")
                }

            case .denied, .restricted:
                self.permissionGranted = false
                print("⚠️ Microphone access denied or restricted")
                print("   Please grant microphone access in System Settings > Privacy & Security > Microphone")

            @unknown default:
                self.permissionGranted = false
                print("⚠️ Unknown microphone permission status")
            }
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

        // Calculate raw peak and RMS levels using vDSP for efficiency
        var rawPeak: Float = 0.0
        var sumSquares: Float = 0.0

        for channel in 0..<channelCount {
            let channelData = floatChannelData[channel]

            // Calculate peak using vDSP (absolute max)
            var channelPeak: Float = 0.0
            var channelMin: Float = 0.0
            vDSP_maxv(channelData, 1, &channelPeak, vDSP_Length(frameLength))
            vDSP_minv(channelData, 1, &channelMin, vDSP_Length(frameLength))
            let absMax = max(abs(channelPeak), abs(channelMin))
            rawPeak = max(rawPeak, absMax)

            // Calculate RMS using vDSP
            var squaredData = [Float](repeating: 0, count: frameLength)
            vDSP_vsq(channelData, 1, &squaredData, 1, vDSP_Length(frameLength))

            var sum: Float = 0.0
            vDSP_sve(squaredData, 1, &sum, vDSP_Length(frameLength))
            sumSquares += sum
        }

        let rawRMS = sqrt(sumSquares / Float(frameLength * channelCount))

        // Apply pre-gain for detection/metering (not altering audio path)
        let gPeak = min(1.0, rawPeak * preGain)
        let gRMS  = min(1.0, rawRMS  * preGain)

        // Adaptive noise floor update (slowly follows quiet background)
        let snrLinear = max(gRMS / max(noiseFloorRMS, 1e-7), 1e-7)
        let snrDb = 20.0 * Float(log10(Double(snrLinear)))
        let alpha = (snrDb < snrThresholdDB - 0.5) ? noiseEMAAlphaQuiet : noiseEMAAlphaIdle
        noiseFloorRMS  = max(0.0001, (1 - alpha) * noiseFloorRMS  + alpha * gRMS)
        noiseFloorPeak = max(0.0002, (1 - alpha) * noiseFloorPeak + alpha * gPeak)

        // Normalize relative to noise floor to emphasize quiet sounds
        let normRMS  = max(0.0, gRMS  - noiseFloorRMS)  / max(1e-6, 1.0 - noiseFloorRMS)
        let normPeak = max(0.0, gPeak - noiseFloorPeak) / max(1e-6, 1.0 - noiseFloorPeak)

        // Extra scaling so small changes are visible; clamp to [0,1]
        var dispRMS  = min(1.0, normRMS  * levelScale)
        var dispPeak = min(1.0, normPeak * levelScale)

        // Attack/Release smoothing for UI stability
        func smooth(current: inout Float, target: Float) {
            if target > current {
                current += levelAttack * (target - current)
            } else {
                current += levelRelease * (target - current)
            }
        }
        smooth(current: &smoothedRMSLevel, target: dispRMS)
        smooth(current: &smoothedPeakLevel, target: dispPeak)

        // Occasional debug logging
        if bufferCallbackCount <= 10 || (gPeak > noiseFloorPeak * 1.05 && bufferCallbackCount % 50 == 0) {
            print(String(format: "🔊 raw P/R=%.4f/%.4f, g P/R=%.4f/%.4f, NF P/R=%.4f/%.4f, SNR=%.1f dB", rawPeak, rawRMS, gPeak, gRMS, noiseFloorPeak, noiseFloorRMS, snrDb))
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.peakLevel = self.smoothedPeakLevel
            self.rmsLevel = self.smoothedRMSLevel

            // Update sound level detection
            self.levelDetector.detectLevel(
                peakLevel: self.smoothedPeakLevel,
                rmsLevel: self.smoothedRMSLevel
            )
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

