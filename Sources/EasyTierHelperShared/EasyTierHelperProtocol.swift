import Foundation

public enum EasyTierHelperConstants {
    public static let machServiceName = "com.easytier.manager.helper"
    public static let daemonPlistName = "com.easytier.manager.helper.plist"
    public static let helperBundleProgram = "Contents/Library/HelperTools/com.easytier.manager.helper"
    public static let allowedClientBundleIdentifier = "com.easytier.manager"
    public static let allowedClientRequirement = "identifier \"\(allowedClientBundleIdentifier)\""
    public static let helperVersion = "1.0.0"
}

@objc(EasyTierHelperProtocol)
public protocol EasyTierHelperProtocol {
    func ping(completion: @escaping (Bool, String?) -> Void)
    func getVersion(completion: @escaping (String?) -> Void)
    func startProcess(executablePath: String, arguments: [String], completion: @escaping (Bool, Int, String?) -> Void)
    func stopProcess(pid: Int, completion: @escaping (Bool, String?) -> Void)
    func isProcessRunning(pid: Int, completion: @escaping (Bool) -> Void)
    func findProcess(pattern: String, completion: @escaping ([String]) -> Void)
}