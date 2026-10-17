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

/// GitHub API 匿名请求每个出口 IP 每小时仅 60 次，代理/VPN 用户常被他人耗尽。
/// 限流时改用 github.com 网页：`releases/latest` 会重定向到 `releases/tag/<tag>`，不占 API 配额，
/// 下载地址按 package-dmg.sh 的固定命名拼出（此时没有 Release 说明）。
extension ReleaseInfo {
    static func webFallbackURL(forAPI url: URL) -> URL? {
        let parts = url.pathComponents
        guard url.host == "api.github.com", parts.count == 6, parts[1] == "repos",
              parts[4] == "releases", parts[5] == "latest" else { return nil }
        return URL(string: "https://github.com/\(parts[2])/\(parts[3])/releases/latest")
    }

    static func fromTagRedirect(_ url: URL, architectures: [String]) -> ReleaseInfo? {
        let parts = url.pathComponents
        guard url.host == "github.com", parts.count == 6, parts[3] == "releases", parts[4] == "tag" else { return nil }
        let tag = parts[5]
        guard AppVersion(tag) != nil else { return nil }
        let versionText = tag.first == "v" || tag.first == "V" ? String(tag.dropFirst()) : tag
        let base = "https://github.com/\(parts[1])/\(parts[2])/releases/download/\(tag)/"
        let assets = architectures.flatMap { arch -> [ReleaseAsset] in
            let dmg = "QuadrantTodo_\(versionText)_\(arch).dmg"
            return [dmg, dmg + ".sha256"].compactMap { name in
                URL(string: base + name).map { ReleaseAsset(name: name, downloadURL: $0) }
            }
        }
        return ReleaseInfo(tagName: tag, body: nil, assets: assets)
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
