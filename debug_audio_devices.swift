
import AVFoundation

print("--- Testing DiscoverySession with [.microphone, .external] (Current Code) ---")
#if os(macOS)
if #available(macOS 14.0, *) {
    let types: [AVCaptureDevice.DeviceType] = [.microphone, .external]
    let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified)
    print("@@@DEBUG: Found \(discoverySession.devices.count) devices:")
    for device in discoverySession.devices {
        print("@@@DEBUG: - [\(device.localizedName)] Type: \(device.deviceType.rawValue)")
    }
} else {
    print("@@@DEBUG: Skipping macOS 14+ check (running on older OS)")
    // Fallback to old types for check if running on old OS
    let types: [AVCaptureDevice.DeviceType] = [.builtInMicrophone, .externalUnknown]
    let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified)
    print("@@@DEBUG: Found \(discoverySession.devices.count) devices (using deprecated types):")
    for device in discoverySession.devices {
        print("@@@DEBUG: - [\(device.localizedName)] Type: \(device.deviceType.rawValue)")
    }
}

print("\n@@@DEBUG: --- Legacy Implementation (devices(for: .audio)) ---")
let allDevices = AVCaptureDevice.devices(for: .audio)
print("@@@DEBUG: Found \(allDevices.count) devices:")
for device in allDevices {
    print("@@@DEBUG: - [\(device.localizedName)] Type: \(device.deviceType.rawValue)")
}

if #available(macOS 14.0, *) {
    let legacyCount = allDevices.count
    let types: [AVCaptureDevice.DeviceType] = [.microphone, .external]
    let dsCount = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified).devices.count
    if legacyCount > dsCount {
        print("\n@@@DEBUG: !!! MISMATCH DETECTED: Legacy found more devices than DiscoverySession !!!")
    } else {
        print("\n@@@DEBUG: Counts match.")
    }
}
#endif
