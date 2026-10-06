import FanKit

try SMC.open()
let keys = SMC.allKeys()
print("keys:", keys.count)
for k in keys where k.hasPrefix("T") || k.hasPrefix("F") || k == "FS! " {
    if let v = try? SMC.read(k) {
        print(k, v.type, v.bytes.map { String(format: "%02x", $0) }.joined(), v.double.map { String(format: "%.2f", $0) } ?? "-")
    }
}
