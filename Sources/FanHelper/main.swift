// fanhelper — installed setuid root so the app can change fan modes.
// Accepts a deliberately tiny command set; every speed is clamped to the fan's own min/max.
//
//   fanhelper version
//   fanhelper set <fan|all> <rpm>
//   fanhelper auto <fan|all>

import Foundation
import FanKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func fanIndices(_ arg: String, count: Int) -> [Int] {
    if arg == "all" { return Array(0..<count) }
    guard let i = Int(arg), i >= 0, i < count else { fail("invalid fan '\(arg)' (have \(count))") }
    return [i]
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("usage: fanhelper version | set <fan|all> <rpm> | auto <fan|all>") }

if command == "version" {
    print(HelperInfo.version)
    exit(0)
}

// Become fully root (real uid too) so the SMC accepts writes.
if geteuid() == 0 { setuid(0) }

do {
    try SMC.open()
    let count = Fans.count()
    guard count > 0 else { fail("no fans found") }

    switch command {
    case "set":
        guard args.count == 3, let rpm = Double(args[2]), rpm.isFinite else { fail("usage: fanhelper set <fan|all> <rpm>") }
        for i in fanIndices(args[1], count: count) {
            let applied = try Fans.setSpeed(i, rpm: rpm)
            print("fan \(i): forced \(Int(applied)) rpm")
        }
    case "auto":
        guard args.count == 2 else { fail("usage: fanhelper auto <fan|all>") }
        for i in fanIndices(args[1], count: count) {
            try Fans.setAuto(i)
            print("fan \(i): auto")
        }
    default:
        fail("unknown command '\(command)'")
    }
} catch {
    fail("\(error)")
}
