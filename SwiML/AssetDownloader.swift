import Foundation

// MARK: - 数据模型
struct AssetIndex: Decodable {
    let objects: [String: AssetObject]
}

struct AssetObject: Decodable {
    let hash: String
    let size: Int
}

// MARK: - 下载管理器
actor AssetDownloader {
    private let config: DirectoryConfig
    private let session: URLSession
    
    init(config: DirectoryConfig) {
        self.config = config
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 10
        self.session = URLSession(configuration: config)
    }
    
    // 主下载入口
    func downloadAssets(for version: String) async throws {
        let (indexURL, assetsDir) = try await prepareEnvironment(version: version)
        let assets = try await parseAssetIndex(from: indexURL)
        try await downloadAllAssets(assets, to: assetsDir)
    }
    
    // MARK: - 私有方法
    private func prepareEnvironment(version: String) async throws -> (URL, URL) {
        // 创建基础目录
        let baseURL = config.baseURL
        let indexesDir = baseURL
            .appendingPathComponent("assets")
            .appendingPathComponent("indexes")
        
        let objectsDir = baseURL
            .appendingPathComponent("assets")
            .appendingPathComponent("objects")
        
        try await createDirectory(at: indexesDir)
        try await createDirectory(at: objectsDir)
        
        // 下载资源索引文件
        let versionManifestList = try await fetchVersionManifest(version: version)
            let indexURL = try await downloadAssetIndex(
                version: version,
                manifest: versionManifestList, // 确保传递 VersionManifestList
                saveTo: indexesDir
            )
            
            return (indexURL, objectsDir)
    }
    
    private func fetchVersionManifest(version: String) async throws -> VersionManifestList {
        let url = URL(string: "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json")!
        let (data, _) = try await session.data(from: url)
        
        // 添加调试输出验证数据结构
        print(String(data: data, encoding: .utf8) ?? "Invalid JSON")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VersionManifestList.self, from: data) // 确保此处严格返回 VersionManifestList
    }
    
    private func downloadAssetIndex(
        version: String,
        manifest: VersionManifestList, // 使用正确的清单类型
        saveTo directory: URL
    ) async throws -> URL {
        guard let versionEntry = manifest.versions.first(where: { $0.id == version }) else {
            throw DownloadError.versionNotFound
        }
        
        guard var urlComponents = URLComponents(string: versionEntry.url) else {
            throw DownloadError.invalidURL
        }
        urlComponents.host = "bmclapi2.bangbang93.com"
        guard let indexURL = urlComponents.url else {
            throw DownloadError.invalidURL
        }
        
        let (data, _) = try await session.data(from: indexURL)
        let savePath = directory.appendingPathComponent("\(version).json")
        try data.write(to: savePath)
        
        return savePath
    }
    
    private func parseAssetIndex(from fileURL: URL) async throws -> [(URL, URL)] {
        let data = try Data(contentsOf: fileURL)
        let index = try JSONDecoder().decode(AssetIndex.self, from: data)
        
        return index.objects.compactMap { _, object in
            guard object.hash.count >= 2 else { return nil }
            
            let prefix = String(object.hash.prefix(2))
            let fileName = object.hash
            
            // 构造下载 URL
            let downloadURL = URL(string: "https://bmclapi2.bangbang93.com/assets/\(prefix)/\(fileName)")!
            
            // 构造存储路径
            let savePath = config.baseURL
                .appendingPathComponent("assets/objects/\(prefix)")
                .appendingPathComponent(fileName)
            
            return (downloadURL, savePath)
        }
    }
    
    private func downloadAllAssets(_ assets: [(URL, URL)], to baseDir: URL) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (url, path) in assets {
                group.addTask {
                    try await self.downloadAsset(from: url, to: path)
                }
            }
            try await group.waitForAll()
        }
    }
    
    private func downloadAsset(from url: URL, to path: URL) async throws {
        let retryCount = 3
        var currentAttempt = 0
        
        repeat {
            do {
                let (data, _) = try await session.data(from: url)
                try await createDirectory(at: path.deletingLastPathComponent())
                try data.write(to: path)
                print("下载成功: \(url.lastPathComponent)")
                return
            } catch {
                currentAttempt += 1
                if currentAttempt >= retryCount {
                    print("资源下载失败: \(url) 错误: \(error)")
                    throw error
                }
                print("重试下载 (\(currentAttempt)/\(retryCount)): \(url)")
                try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(currentAttempt))
            }
        } while currentAttempt < retryCount
    }
    
    private func createDirectory(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true
                )
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - 使用示例
@MainActor
final class AssetViewModel: ObservableObject {
    @Published var isDownloading = false
    @Published var progress = 0.0
    @Published var error: Error?
    
    private let downloader: AssetDownloader
    
    init(config: DirectoryConfig) {
        self.downloader = AssetDownloader(config: config)
    }
    
    func downloadAssets(version: String) async {
        isDownloading = true
        error = nil
        
        do {
            try await downloader.downloadAssets(for: version)
        } catch {
            self.error = error
        }
        
        isDownloading = false
    }
}

extension AssetDownloader {
    // 准备资源列表
    func prepareAssetList(version: String) async throws -> [(URL, URL)] {
        let (indexURL, objectsDir) = try await prepareEnvironment(version: version)
        return try await parseAssetIndex(from: indexURL)
    }
    
    // 获取索引文件路径方法
    private func getIndexesDirectory() -> URL {
        config.baseURL
            .appendingPathComponent("assets")
            .appendingPathComponent("indexes")
    }
    
    // 下载单个资源
    func downloadSingleAsset(_ asset: (URL, URL)) async throws {
        let (downloadURL, savePath) = asset
        
        // 确保目录存在
        let directory = savePath.deletingLastPathComponent()
        try await createDirectory(at: directory)
        
        // 增加文件存在性检查
        if FileManager.default.fileExists(atPath: savePath.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: savePath.path)
            guard let size = attributes[.size] as? Int else { return }
            if size > 0 {
                print("文件已存在，跳过下载: \(savePath.lastPathComponent)")
                return
            }
        }
        
        // 下载并写入文件
        let (data, _) = try await session.data(from: downloadURL)
        try data.write(to: savePath)
        
        // 验证文件完整性
        guard FileManager.default.fileExists(atPath: savePath.path) else {
            throw DownloadError.fileSizeMismatch
        }
    }
    
    private func fetchAssetIndexURL(version: String) async throws -> URL {
        let versionManifestList = try await fetchVersionManifest(version: version)
        return try await downloadAssetIndex(
            version: version,
            manifest: versionManifestList,
            saveTo: config.baseURL  // 改为使用初始化时注入的 config 属性
                .appendingPathComponent("assets")
                .appendingPathComponent("indexes")
        )
    }
}
