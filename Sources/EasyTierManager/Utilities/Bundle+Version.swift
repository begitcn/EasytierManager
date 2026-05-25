import Foundation

extension Bundle {
    var shortVersion: String {
        if let v = infoDictionary?["CFBundleShortVersionString"] as? String,
           !v.isEmpty, v != "$(MARKETING_VERSION)" {
            return v
        }
        if let url = Bundle.main.url(forResource: "VERSION", withExtension: nil),
           let v = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !v.isEmpty {
            return v
        }
        return "1.0.5"
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
