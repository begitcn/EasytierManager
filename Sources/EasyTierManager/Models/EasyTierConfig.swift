import Foundation

struct EasyTierConfig {
    var hostname: String = ""
    var instanceName: String = ""
    var ipv4: String = ""
    var dhcp: Bool = false
    var listeners: [String] = []
    var networkName: String = ""
    var networkSecret: String = ""
    var peers: [String] = []
    var acceptDns: Bool = true
    var latencyFirst: Bool = true
    var privateMode: Bool = true

    func toTomlString() -> String {
        var lines: [String] = []

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }

        lines.append("hostname = \"\(esc(hostname))\"")
        lines.append("instance_name = \"\(esc(instanceName))\"")
        lines.append("ipv4 = \"\(esc(ipv4))\"")
        lines.append("dhcp = \(dhcp)")
        lines.append("")

        if !listeners.isEmpty {
            lines.append("listeners = [")
            for l in listeners {
                lines.append("    \"\(esc(l))\",")
            }
            lines.append("]")
            lines.append("")
        }

        lines.append("[network_identity]")
        lines.append("network_name = \"\(esc(networkName))\"")
        lines.append("network_secret = \"\(esc(networkSecret))\"")
        lines.append("")

        for p in peers {
            lines.append("[[peer]]")
            lines.append("uri = \"\(esc(p))\"")
            lines.append("")
        }

        lines.append("[flags]")
        lines.append("accept_dns = \(acceptDns)")
        lines.append("latency_first = \(latencyFirst)")
        lines.append("private_mode = \(privateMode)")

        return lines.joined(separator: "\n")
    }

    func save(to url: URL) throws {
        try toTomlString().write(to: url, atomically: true, encoding: .utf8)
    }

    static func configsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EasyTierManager/configs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: UUID) -> URL {
        configsDirectory().appendingPathComponent("config_\(id.uuidString).toml")
    }

    static func generateURL() -> URL {
        url(for: UUID())
    }

    static func parse(from url: URL) throws -> EasyTierConfig {
        let content = try String(contentsOf: url, encoding: .utf8)
        var config = EasyTierConfig()
        var currentSection = ""
        var inListeners = false

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line == "[[peer]]" {
                currentSection = "peer"
                continue
            }

            if line.hasPrefix("[") && !line.hasPrefix("[[") {
                currentSection = String(line.dropFirst().dropLast())
                continue
            }

            if line == "listeners = [" {
                inListeners = true
                continue
            }

            if inListeners {
                if line == "]" { inListeners = false; continue }
                let item = line.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                if !item.isEmpty { config.listeners.append(item) }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let str = val.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
            let isTrue = val == "true"
            let isFalse = val == "false"

            if currentSection == "peer" {
                if key == "uri" { config.peers.append(str) }
                continue
            }

            if currentSection.isEmpty && key == "listeners" && val.hasPrefix("[") && val.hasSuffix("]") {
                let inner = val.dropFirst().dropLast()
                for item in inner.split(separator: ",") {
                    let s = String(item).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                    if !s.isEmpty { config.listeners.append(s) }
                }
                continue
            }

            switch currentSection {
            case "":
                switch key {
                case "hostname": config.hostname = str
                case "instance_name": config.instanceName = str
                case "ipv4": config.ipv4 = str
                case "dhcp": if isTrue || isFalse { config.dhcp = isTrue }
                default: break
                }
            case "network_identity":
                switch key {
                case "network_name": config.networkName = str
                case "network_secret": config.networkSecret = str
                default: break
                }
            case "flags":
                switch key {
                case "accept_dns": if isTrue || isFalse { config.acceptDns = isTrue }
                case "latency_first": if isTrue || isFalse { config.latencyFirst = isTrue }
                case "private_mode": if isTrue || isFalse { config.privateMode = isTrue }
                default: break
                }
            default: break
            }
        }

        return config
    }
}
