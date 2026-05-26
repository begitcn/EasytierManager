import Foundation

public enum EasyTierHelperConstants {
    public static let machServiceName = "EasyTierHelper"
    public static let daemonPlistName = "EasyTierHelper.plist"
    public static let helperBundleProgram = "Contents/Library/HelperTools/EasyTierHelper"
    public static let allowedClientBundleIdentifier = "com.easytier.manager"
    public static let allowedClientRequirement = "identifier \"\(allowedClientBundleIdentifier)\""
    public static let helperVersion = AppVersion.current
}

@objc(EasyTierHelperProtocol)
public protocol EasyTierHelperProtocol {
    func ping(completion: @escaping (Bool, String?) -> Void)
    func getVersion(completion: @escaping (String?) -> Void)
    func startProcess(executablePath: String, arguments: [String], completion: @escaping (Bool, Int, String?) -> Void)
    func stopProcess(pid: Int, completion: @escaping (Bool, String?) -> Void)
    func isProcessRunning(pid: Int, completion: @escaping (Bool) -> Void)
    func findProcess(pattern: String, completion: @escaping ([String]) -> Void)
    func forceStopProcess(pid: Int, completion: @escaping (Bool, String?) -> Void)
    func stopAllProcesses(completion: @escaping (Bool, String?) -> Void)
}