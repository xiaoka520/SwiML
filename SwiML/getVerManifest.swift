import Foundation

// MARK: - 异步获取版本清单
func fetchVersionManifest() async throws -> String {
    let url = URL(string: "https://bmclapi2.bangbang93.com/mc/game/version_manifest.json")!
    let (data, response) = try await URLSession.shared.data(from: url)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    
    guard let jsonString = String(data: data, encoding: .utf8) else {
        throw URLError(.cannotDecodeContentData)
    }
    
    return jsonString
}

// MARK: - JSON路径解析工具
func getValueFromJson(jsonString: String, path: String) -> String? {
    let components = path.components(separatedBy: ".")
    guard let jsonData = jsonString.data(using: .utf8),
          let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) else {
        return nil
    }
    
    var current: Any = jsonObject
    for component in components {
        if let dict = current as? [String: Any], let val = dict[component] {
            current = val
        } else if let array = current as? [Any], let index = Int(component), array.indices.contains(index) {
            current = array[index]
        } else {
            return nil
        }
    }
    
    // 处理基本类型返回值
    switch current {
    case let string as String: return string
    case let number as NSNumber: return number.stringValue
    case let bool as Bool: return bool ? "true" : "false"
    default:
        if let data = try? JSONSerialization.data(withJSONObject: current, options: .fragmentsAllowed) {
            return String(data: data, encoding: .utf8)?
                .replacingOccurrences(of: "^\"|\"$", with: "", options: .regularExpression)
        }
        return nil
    }
}

// MARK: - 解析版本信息
func parseVersionManifest() async {
    do {
        let jsonString = try await fetchVersionManifest()
        
        // 解析最新版本
        guard let latestRelease = getValueFromJson(jsonString: jsonString, path: "latest.release"),
              let latestSnapshot = getValueFromJson(jsonString: jsonString, path: "latest.snapshot") else {
            print("Failed to parse latest versions")
            return
        }
        
        // 输出最新版本（直接打印版本号）
        print(latestRelease)
        print(latestSnapshot)
        
        // 解析版本列表
        guard let versionsStr = getValueFromJson(jsonString: jsonString, path: "versions"),
              let versionsData = versionsStr.data(using: .utf8),
              let versions = try? JSONSerialization.jsonObject(with: versionsData) as? [[String: Any]] else {
            print("Failed to parse versions list")
            return
        }
        
        for version in versions {
            guard let versionData = try? JSONSerialization.data(withJSONObject: version, options: .fragmentsAllowed),
                  let versionJson = String(data: versionData, encoding: .utf8) else {
                continue
            }
            
            let id = getValueFromJson(jsonString: versionJson, path: "id") ?? "unknown"
            let type = getValueFromJson(jsonString: versionJson, path: "type") ?? "unknown"
            let url = getValueFromJson(jsonString: versionJson, path: "url") ?? "unknown"
            
            // 使用分号分隔的格式
            print("Version:\(id);\(type);\(url)")
        }
    } catch {
        print("Error: \(error.localizedDescription)")
    }
}

