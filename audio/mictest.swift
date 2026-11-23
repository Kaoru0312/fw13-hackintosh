// 麥克風測試：從預設輸入錄 N 秒存成 .caf，每 0.5 秒印出峰值與 RMS（dBFS），最後印整段統計。
// 編譯：swiftc -O audio/mictest.swift -o /tmp/mictest
// 用法：/tmp/mictest <秒數> <輸出.caf>
// 注意：第一次執行時 macOS 可能會跳出「允許使用麥克風」的視窗；沒允許的話錄到的會全是 0（-inf dB）。
import AVFoundation
import Foundation

let secs = Double(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "6") ?? 6
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/mictest.caf"

let engine = AVAudioEngine()
let input = engine.inputNode
let fmt = input.outputFormat(forBus: 0)
print("輸入格式：\(fmt.sampleRate) Hz，\(fmt.channelCount) 聲道")
guard fmt.channelCount > 0, fmt.sampleRate > 0 else { print("沒有可用的輸入裝置"); exit(1) }

let file = try AVAudioFile(forWriting: URL(fileURLWithPath: out), settings: fmt.settings)
var winPeak: Float = 0, winSq: Double = 0, winN = 0
var allPeak: Float = 0, allSq: Double = 0, allN = 0
let lock = NSLock()

func db(_ x: Double) -> String { x <= 0 ? "-inf" : String(format: "%.1f", 20 * log10(x)) }

input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, _ in
    try? file.write(from: buf)
    guard let ch = buf.floatChannelData else { return }
    lock.lock()
    for c in 0..<Int(buf.format.channelCount) {
        for i in 0..<Int(buf.frameLength) {
            let v = abs(ch[c][i])
            if v > winPeak { winPeak = v }
            winSq += Double(v * v); winN += 1
        }
    }
    lock.unlock()
}

try engine.start()
let start = Date()
while Date().timeIntervalSince(start) < secs {
    Thread.sleep(forTimeInterval: 0.5)
    lock.lock()
    let rms = winN > 0 ? sqrt(winSq / Double(winN)) : 0
    print(String(format: "%5.1fs  峰值 %@ dB  RMS %@ dB", Date().timeIntervalSince(start), db(Double(winPeak)), db(rms)))
    if winPeak > allPeak { allPeak = winPeak }
    allSq += winSq; allN += winN
    winPeak = 0; winSq = 0; winN = 0
    lock.unlock()
}
engine.stop()
input.removeTap(onBus: 0)
print("整段：峰值 \(db(Double(allPeak))) dB，RMS \(db(allN > 0 ? sqrt(allSq / Double(allN)) : 0)) dB，存在 \(out)")
