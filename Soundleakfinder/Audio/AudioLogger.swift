import AVFoundation
import os.log

/// Centralized logging for audio operations
class AudioLogger {
    static let shared = AudioLogger()
    
    private let logger = os.Logger(subsystem: "com.soundleakfinder.audio", category: "AudioEngine")
    private var logBuffer: [String] = []
    private let maxLogEntries = 1000
    
    // MARK: - Device Logging
    
    func logDeviceEnumeration(_ devices: [AudioDevice]) {
        logger.info("Enumerated \(devices.count) input devices")
        for device in devices {
            let typeInfo = "\(device.isBuiltIn ? "Built-in" : "")\(device.isUSB ? "USB" : "")\(device.isBluetooth ? "Bluetooth" : "")".trimmingCharacters(in: .whitespaces)
            logger.info("  - \(device.name) (\(device.channelCount)ch, \(typeInfo))")
        }
    }
    
    func logDeviceSelected(_ device: AudioDevice) {
        logger.info("Selected device: \(device.name) (\(device.channelCount) channels)")
        addToBuffer("✓ Device: \(device.name)")
    }
    
    func logAggregateDeviceCreated(_ name: String, deviceCount: Int) {
        logger.info("Created aggregate device: \(name) with \(deviceCount) sub-devices")
        addToBuffer("✓ Aggregate device created: \(name)")
    }
    
    // MARK: - Audio Format Logging
    
    func logAudioFormat(_ format: AVAudioFormat) {
        let formatString = "\(format.sampleRate)Hz, \(format.channelCount)ch, \(format.commonFormat)"
        logger.info("Audio format: \(formatString)")
        addToBuffer("Format: \(formatString)")
    }
    
    func logBufferConversion(from: AVAudioFormat, to: AVAudioFormat) {
        logger.info("Converting buffer: \(from.sampleRate)Hz → \(to.sampleRate)Hz, \(from.channelCount)ch → \(to.channelCount)ch")
    }
    
    // MARK: - Audio Level Logging
    
    func logAudioLevels(peak: Float, rms: Float, deviceName: String? = nil) {
        let peakDb = 20 * log10(max(peak, 0.00001))
        let rmsDb = 20 * log10(max(rms, 0.00001))
        
        let device = deviceName.map { " [\($0)]" } ?? ""
        logger.debug("Levels\(device): Peak=\(String(format: "%.1f", peakDb))dB, RMS=\(String(format: "%.1f", rmsDb))dB")
    }
    
    func logPeakLevel(_ peak: Float) {
        let peakDb = 20 * log10(max(peak, 0.00001))
        if peakDb > -20 {
            logger.warning("High peak level: \(String(format: "%.1f", peakDb))dB")
        }
    }
    
    // MARK: - Engine State Logging
    
    func logEngineStarted() {
        logger.info("Audio engine started")
        addToBuffer("▶ Audio engine started")
    }
    
    func logEngineStopped() {
        logger.info("Audio engine stopped")
        addToBuffer("⏹ Audio engine stopped")
    }
    
    func logEngineError(_ error: Error) {
        logger.error("Audio engine error: \(error.localizedDescription)")
        addToBuffer("✗ Error: \(error.localizedDescription)")
    }
    
    // MARK: - Buffer Statistics
    
    func logBufferStatistics(frameCount: Int, sampleRate: Double, channelCount: Int) {
        let duration = Double(frameCount) / sampleRate
        logger.debug("Buffer: \(frameCount) frames, \(channelCount)ch, duration=\(String(format: "%.2f", duration))ms")
    }
    
    // MARK: - Permission Logging
    
    func logMicrophonePermissionRequested() {
        logger.info("Requesting microphone permission")
        addToBuffer("🎤 Requesting microphone permission...")
    }
    
    func logMicrophonePermissionGranted() {
        logger.info("Microphone permission granted")
        addToBuffer("✓ Microphone permission granted")
    }
    
    func logMicrophonePermissionDenied() {
        logger.error("Microphone permission denied")
        addToBuffer("✗ Microphone permission denied")
    }
    
    // MARK: - Log Buffer Management
    
    private func addToBuffer(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        
        logBuffer.append(entry)
        if logBuffer.count > maxLogEntries {
            logBuffer.removeFirst()
        }
    }
    
    func getLogBuffer() -> [String] {
        return logBuffer
    }
    
    func clearLogBuffer() {
        logBuffer.removeAll()
    }
    
    func exportLogs() -> String {
        return logBuffer.joined(separator: "\n")
    }
    
    // MARK: - Convenience Methods
    
    func logInfo(_ message: String) {
        logger.info("\(message)")
        addToBuffer("ℹ \(message)")
    }
    
    func logWarning(_ message: String) {
        logger.warning("\(message)")
        addToBuffer("⚠ \(message)")
    }
    
    func logError(_ message: String) {
        logger.error("\(message)")
        addToBuffer("✗ \(message)")
    }
}

