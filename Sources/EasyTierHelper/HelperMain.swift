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

    private var runningProcesses: [Int: Process] = [:]
    private let processLock = NSLock()

    func startProcess(executablePath: String, arguments: [String], completion: @escaping (Bool, Int, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let devNull = FileHandle(fileDescriptor: open("/dev/null", O_WRONLY), closeOnDealloc: true)
        process.standardOutput = devNull
        process.standardError = devNull

        process.terminationHandler = { [weak self] p in
            guard let self else { return }
            self.processLock.lock()
            self.runningProcesses.removeValue(forKey: Int(p.processIdentifier))
            self.processLock.unlock()
        }

        do {
            try process.run()

            let pid = process.processIdentifier

            if process.isRunning {
                processLock.lock()
                runningProcesses[Int(pid)] = process
                processLock.unlock()
                completion(true, Int(pid), nil)
            } else {
                completion(false, Int(process.terminationStatus), nil)
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

    func stopAllProcesses(completion: @escaping (Bool, String?) -> Void) {
        processLock.lock()
        let pids = Array(runningProcesses.keys)
        processLock.unlock()

        guard !pids.isEmpty else {
            completion(true, nil)
            return
        }

        for pid in pids {
            kill(pid_t(pid), SIGTERM)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            self.processLock.lock()
            for pid in pids {
                if kill(pid_t(pid), 0) == 0 {
                    kill(pid_t(pid), SIGKILL)
                }
                self.runningProcesses.removeValue(forKey: pid)
            }
            self.processLock.unlock()
            completion(true, nil)
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
    private var activeConnections = NSMutableSet()
    private let connectionLock = NSLock()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: EasyTierHelperProtocol.self)
        newConnection.exportedObject = self.service

        connectionLock.lock()
        activeConnections.add(newConnection)
        connectionLock.unlock()

        newConnection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.connectionLock.lock()
            self.activeConnections.remove(newConnection)
            let remaining = self.activeConnections.count
            self.connectionLock.unlock()
            if remaining == 0 {
                self.service.stopAllProcesses { _, _ in }
            }
        }

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