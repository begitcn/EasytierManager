import Foundation

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var buildVersion: Int {
        Int(infoDictionary?["CFBundleVersion"] as? String ?? "1") ?? 1
    }

    var versionStr: String {
        "v\(shortVersion)"
    }

    var buildStr: String {
        "\(buildVersion)"
    }
}
