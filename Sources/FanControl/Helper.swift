import AppKit
import FanKit

enum HelperStatus: Equatable {
    case notInstalled
    case outdated
    case ready
}

/// Talks to the setuid helper that performs privileged SMC writes.
enum HelperClient {
    private static let queue = DispatchQueue(label: "fancontrol.helper")

    static var bundledHelperURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "fanhelper")
    }

    static func status() -> HelperStatus {
        var st = stat()
        guard stat(HelperInfo.installPath, &st) == 0 else { return .notInstalled }
        guard st.st_uid == 0, st.st_mode & S_ISUID != 0 else { return .notInstalled }
        let installed = (try? runSync(["version"]))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return installed == HelperInfo.version ? .ready : .outdated
    }

    @discardableResult
    static func runSync(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: HelperInfo.installPath)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw HelperError(message: stderr.isEmpty ? "Helper failed (\(process.terminationStatus))" : stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return stdout
    }

    /// Runs helper commands in order, off the main thread.
    static func run(_ commands: [[String]]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    for args in commands { try runSync(args) }
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Installs the bundled helper as setuid root. Shows the standard administrator prompt.
    static func install() throws {
        guard let src = bundledHelperURL?.path else {
            throw HelperError(message: "The helper is missing from the app bundle. Rebuild with ./build.sh.")
        }
        let dst = HelperInfo.installPath
        let shell = "/bin/mkdir -p /Library/PrivilegedHelperTools && /usr/bin/install -o root -g wheel -m 4755 \(quoted(src)) \(quoted(dst))"
        try runAsAdmin(shell, prompt: "Fan Control wants to install a small helper so it can change fan speeds.")
    }

    static func uninstall() throws {
        _ = try? runSync(["auto", "all"])
        try runAsAdmin("/bin/rm -f \(quoted(HelperInfo.installPath))", prompt: "Fan Control wants to remove its fan helper.")
    }

    private static func runAsAdmin(_ shell: String, prompt: String) throws {
        let source = "do shell script \(appleScriptString(shell)) with prompt \(appleScriptString(prompt)) with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 { throw HelperError(message: "Cancelled.") }
            throw HelperError(message: errorInfo[NSAppleScript.errorMessage] as? String ?? "Installation failed.")
        }
    }

    private static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

struct HelperError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
