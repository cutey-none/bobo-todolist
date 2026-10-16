import Foundation

struct ReleaseAsset: Decodable, Equatable {
    let name: String
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

/// 一次可安装的更新：本机架构的 DMG 与其 SHA-256 校验文件。
struct UpdatePackage: Equatable {
    let version: AppVersion
    let dmgName: String
    let dmgURL: URL
    let checksumURL: URL
}

enum ReleaseLookup: Equatable {
    case upToDate(AppVersion)
    case available(UpdatePackage, notes: String)
    case missingPackage(AppVersion)
}

/// GitHub `releases/latest` 响应中更新所需的字段。
struct ReleaseInfo: Decodable, Equatable {
    let tagName: String
    let body: String?
    let assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case assets
    }

    static func decode(_ data: Data) throws -> ReleaseInfo {
        try JSONDecoder().decode(ReleaseInfo.self, from: data)
    }

    var version: AppVersion? { AppVersion(tagName) }

    /// 资源名与 package-dmg.sh 的产物一致：`QuadrantTodo_<版本>_<arch>.dmg` 及同名 `.sha256`。
    /// tag 无法识别时返回 nil。
    func lookup(current: AppVersion, architecture: String) -> ReleaseLookup? {
        guard let version else { return nil }
        guard current < version else { return .upToDate(version) }
        var versionText = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        if versionText.first == "v" || versionText.first == "V" { versionText.removeFirst() }
        let dmgName = "QuadrantTodo_\(versionText)_\(architecture).dmg"
        guard let dmg = assets.first(where: { $0.name == dmgName }),
              let checksum = assets.first(where: { $0.name == dmgName + ".sha256" }) else {
            return .missingPackage(version)
        }
        let package = UpdatePackage(version: version, dmgName: dmgName, dmgURL: dmg.downloadURL, checksumURL: checksum.downloadURL)
        return .available(package, notes: (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum CPUArchitecture {
    /// 与 package-dmg.sh 中 `uname -m` 的取值一致。
    static var current: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
