import Foundation
import EasyTierHelperShared
import Security

private final class EasyTierHelperService: NSObject, EasyTierHelperProtocol {
    func ping(completion: @escaping (Bool, String?) -> Void) {
        completion(true, nil)
    }

    func getVersion(completion: @escaping (String?) -> Void) {
        completion(EasyTierHelperConstants.helperVersion)
    }

    func startProcess(executablePath: String, arguments: [String], completion: @escaping (Bool, Int, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            let pid = process.processIdentifier

            if process.isRunning {
                completion(true, Int(pid), nil)
            } else {
                let exitCode = process.terminationStatus
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorStr = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completion(false, Int(exitCode), errorStr)
            }
        } catch {
            completion(false, -1, error.localizedDescription)
        }
    }

    func stopProcess(pid: Int, completion: @escaping (Bool, String?) -> Void) {
        let result = kill(pid_t(pid), SIGTERM)
        if result == 0 {
            completion(true, nil)
        } else {
            let errorStr = String(cString: strerror(errno))
            completion(false, errorStr)
        }
    }

    func isProcessRunning(pid: Int, completion: @escaping (Bool) -> Void) {
        let result = kill(pid_t(pid), 0)
        completion(result == 0)
    }

    func forceStopProcess(pid: Int, completion: @escaping (Bool, String?) -> Void) {
        let result = kill(pid_t(pid), SIGKILL)
        if result == 0 {
            completion(true, nil)
        } else {
            let errorStr = String(cString: strerror(errno))
            completion(false, errorStr)
        }
    }

    func findProcess(pattern: String, completion: @escaping ([String]) -> Void) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-af", pattern]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if task.terminationStatus == 0 {
                let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                completion(lines)
            } else {
                completion([])
            }
        } catch {
            completion([])
        }
    }
}

private final class EasyTierHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = EasyTierHelperService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: EasyTierHelperProtocol.self)
        newConnection.exportedObject = self.service
        newConnection.resume()
        return true
    }
}

@main
struct EasyTierHelperMain {
    static func main() {
        let delegate = EasyTierHelperListenerDelegate()
        let listener = NSXPCListener(machServiceName: EasyTierHelperConstants.machServiceName)
        listener.delegate = delegate
        listener.setConnectionCodeSigningRequirement(buildClientRequirement())
        listener.resume()
        dispatchMain()
    }

    private static func buildClientRequirement() -> String {
        let base = EasyTierHelperConstants.allowedClientRequirement
        guard let teamID = selfTeamIdentifier(), !teamID.isEmpty else {
            return base
        }
        return "\(base) and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    private static func selfTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info) == errSecSuccess,
            let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}