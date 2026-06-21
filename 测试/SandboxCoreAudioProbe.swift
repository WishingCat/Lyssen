import CoreAudio
import Foundation

func deviceName(_ id: AudioDeviceID) -> String {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
    if status == noErr, let cf = name?.takeRetainedValue() {
        return cf as String
    }
    return "Unknown(\(status))"
}

func transportType(_ id: AudioDeviceID) -> UInt32 {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &transport)
    return transport
}

func hasInputChannels(_ id: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
        return false
    }
    let raw = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size),
        alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else {
        return false
    }
    let abl = raw.assumingMemoryBound(to: AudioBufferList.self)
    var channels = 0
    for buf in UnsafeMutableAudioBufferListPointer(abl) {
        channels += Int(buf.mNumberChannels)
    }
    return channels > 0
}

func allDevices() -> [AudioDeviceID] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let sys = AudioObjectID(kAudioObjectSystemObject)
    let sizeStatus = AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size)
    print("devices.sizeStatus=\(sizeStatus) size=\(size)")
    guard sizeStatus == noErr else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: count)
    let status = AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &devices)
    print("devices.dataStatus=\(status) count=\(devices.count)")
    return status == noErr ? devices : []
}

func defaultInputDevice() -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
    print("defaultInput.status=\(status)")
    return dev
}

func defaultOutputDevice() -> AudioDeviceID {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
    print("defaultOutput.status=\(status)")
    return dev
}

func setDefaultInput(_ id: AudioDeviceID) -> OSStatus {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var dev = id
    return AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
        UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
}

let devices = allDevices()
for device in devices {
    print("device id=\(device) name=\(deviceName(device)) transport=\(transportType(device)) input=\(hasInputChannels(device))")
}

let input = defaultInputDevice()
let output = defaultOutputDevice()
print("currentInput=\(input) \(deviceName(input))")
print("currentOutput=\(output) \(deviceName(output))")

let setSameStatus = setDefaultInput(input)
print("setSameDefaultInput.status=\(setSameStatus)")

if let builtin = devices.first(where: { transportType($0) == kAudioDeviceTransportTypeBuiltIn && hasInputChannels($0) }) {
    let setBuiltinStatus = setDefaultInput(builtin)
    print("setBuiltinInput.status=\(setBuiltinStatus) builtin=\(deviceName(builtin))")
} else {
    print("builtinInput=missing")
}
