import Foundation
import EasyTierHelperShared

extension Bundle {
    var shortVersion: String {
        AppVersion.current
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
