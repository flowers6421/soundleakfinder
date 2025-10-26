import CoreAudio
import Foundation

/// Manages creation and configuration of Core Audio Aggregate Devices
class AggregateDeviceManager {
    static let shared = AggregateDeviceManager()
    
    /// Create an aggregate device from multiple input devices
    /// - Parameters:
    ///   - name: Name for the aggregate device
    ///   - deviceIDs: Array of AudioDeviceIDs to aggregate
    /// - Returns: The ID of the created aggregate device, or nil if creation failed
    func createAggregateDevice(name: String, from deviceIDs: [AudioDeviceID]) -> AudioDeviceID? {
        guard !deviceIDs.isEmpty else {
            print("Cannot create aggregate device: no devices provided")
            return nil
        }
        
        // Create the aggregate device dictionary
        var aggregateDeviceDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: deviceIDs[0],
            kAudioAggregateDeviceSubDeviceListKey: deviceIDs
        ]
        
        // Enable drift correction
        aggregateDeviceDict[kAudioAggregateDeviceMasterSubDeviceKey] = deviceIDs[0]
        
        var aggregateDeviceID: AudioDeviceID = 0
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Create the aggregate device
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &aggregateDeviceID
        )
        
        if status == noErr {
            print("Successfully created aggregate device: \(name) (ID: \(aggregateDeviceID))")
            
            // Enable drift correction
            enableDriftCorrection(for: aggregateDeviceID)
            
            return aggregateDeviceID
        } else {
            print("Failed to create aggregate device: OSStatus \(status)")
            return nil
        }
    }
    
    /// Enable drift correction for an aggregate device
    /// - Parameter deviceID: The aggregate device ID
    func enableDriftCorrection(for deviceID: AudioDeviceID) {
        // Note: Drift correction is typically enabled via Audio MIDI Setup UI
        // or by setting the master device. This is a placeholder for future enhancement.
        print("Drift correction configuration for aggregate device (ID: \(deviceID))")
    }
    
    /// List all existing aggregate devices
    /// - Returns: Array of aggregate device IDs
    func listAggregateDevices() -> [AudioDeviceID] {
        var aggregateDevices: [AudioDeviceID] = []
        
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
            return aggregateDevices
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
            return aggregateDevices
        }
        
        for deviceID in deviceIDs {
            if isAggregateDevice(deviceID) {
                aggregateDevices.append(deviceID)
            }
        }
        
        return aggregateDevices
    }
    
    /// Check if a device is an aggregate device
    /// - Parameter deviceID: The device ID to check
    /// - Returns: True if the device is an aggregate device
    private func isAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var uid: CFString? = nil
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid) == noErr,
              let uidString = uid as String? else {
            return false
        }
        
        return uidString.contains("AggregateDevice")
    }
    
    /// Delete an aggregate device
    /// - Parameter deviceID: The aggregate device ID to delete
    /// - Returns: True if deletion was successful
    func deleteAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceIDToDelete = deviceID
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceIDToDelete
        )
        
        if status == noErr {
            print("Successfully deleted aggregate device")
            return true
        } else {
            print("Failed to delete aggregate device: OSStatus \(status)")
            return false
        }
    }
    
    /// Get the name of an aggregate device
    /// - Parameter deviceID: The device ID
    /// - Returns: The device name, or nil if not found
    func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var nameRef: CFString? = nil
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &nameRef) == noErr,
              let name = nameRef as String? else {
            return nil
        }
        
        return name
    }
}

