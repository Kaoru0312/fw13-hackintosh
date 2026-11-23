import CoreAudio
var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
let want = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
for id in ids {
    var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: Unmanaged<CFString>?; var ns = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioObjectGetPropertyData(id, &na, 0, nil, &ns, &name)
    let n = name?.takeRetainedValue() as String? ?? "?"
    print(id, n)
    if !want.isEmpty && n.contains(want) {
        var dev = id
        for sel in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var da = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let r = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &da, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
            print("  set default (\(sel)) ->", r)
        }
    }
}
