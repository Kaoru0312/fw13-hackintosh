// 列出主螢幕所有模式（含 HiDPI），以及 CoreGraphics 看到的 vendor/model/實體尺寸。
// swiftc -O display/modes.swift -o /tmp/modes && /tmp/modes
import CoreGraphics
let d = CGMainDisplayID()
let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
let cur = CGDisplayCopyDisplayMode(d)!
print("current: \(cur.width)x\(cur.height) pixels \(cur.pixelWidth)x\(cur.pixelHeight) @\(cur.refreshRate)")
print("vendor \(String(CGDisplayVendorNumber(d), radix:16)) model \(String(CGDisplayModelNumber(d), radix:16)) size_mm \(CGDisplayScreenSize(d)) builtin \(CGDisplayIsBuiltin(d) != 0)")
for m in (CGDisplayCopyAllDisplayModes(d, opts) as! [CGDisplayMode]) {
  print("\(m.width)x\(m.height)  px \(m.pixelWidth)x\(m.pixelHeight)\(m.pixelWidth > m.width ? "  HiDPI" : "")  usable=\(m.isUsableForDesktopGUI())")
}
