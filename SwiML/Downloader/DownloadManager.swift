import AsyncAlgorithms
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - 数据模型
struct VersionManifestList: Decodable {
    let latest: LatestVersion
    let versions: [VersionEntry]

    struct LatestVersion: Decodable {
        let release: String
        let snapshot: String
    }

    struct VersionEntry: Decodable {
        let id: String
        let type: String
        let url: String
        let time: String  // Mojang API 实际返回的是字符串日期
        let releaseTime: String
    }
}

// MARK: - VersionManifest 结构
struct VersionManifest: Decodable {
    let libraries: [Library]

    struct Library: Decodable {
        let downloads: Downloads
        let name: String
        let rules: [Rule]?
        let classifiers: [String: Downloads.Artifact]?

        struct Downloads: Decodable {
            let artifact: Artifact?

            struct Artifact: Decodable {
                let path: String
                let sha1: String
                let size: Int
                let url: String
            }
        }

        struct Rule: Decodable {
            let os: OS?

            struct OS: Decodable {
                let name: String
            }
        }
    }
}

// MARK: - 统一的错误类型
enum DownloadError: Error {
    case invalidURL
    case invalidResponse
    case fileSizeMismatch
    case sha1Mismatch
    case directoryCreationFailed
    case versionNotFound
    case invalidManifest
    case invalidDirectory
    case missingArtifact
    case invalidArchive
    case invalidSHA1(library: String)
    case fileCorrupted(path: String)
    case serverError(code: Int)
    case invalidPath(String)
    case networkError(code: Int)
    case filePermissionDenied(path: String)

    var localizedDescription: String {
        switch self {
        case .networkError(let code):
            return "网络错误（代码: \(code)）"
        // ...其他错误描述...以后再写
        default:
            return "未知错误"
        }
    }

}

// MARK: - 目录配置管理

class DirectoryConfig: ObservableObject {
    enum DirectoryOption: Int, CaseIterable {
        case documents
        case appBundle
        case appParent
        case custom
    }

    @Published var selectedOption: DirectoryOption = .documents {
        didSet {
            saveConfig()
        }
    }

    @Published var customPath: String = "" {
        didSet {
            saveConfig()
        }
    }

    private let defaults = UserDefaults.standard
    private let appBundleURL = Bundle.main.bundleURL

    init() {
        loadConfig()
    }

    var baseURL: URL {
        switch selectedOption {
        case .documents:
            return FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            ).first!
            .appendingPathComponent(".minecraft")

        case .appBundle:
            return
                appBundleURL
                .appendingPathComponent("minecraft")

        case .appParent:
            return
                appBundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(".minecraft")

        case .custom:
            return URL(fileURLWithPath: customPath)
        }
    }

    private func loadConfig() {
        selectedOption =
            DirectoryOption(
                rawValue: defaults.integer(forKey: "directoryOption"))
            ?? .documents
        customPath = defaults.string(forKey: "customPath") ?? ""
    }

    private func saveConfig() {
        defaults.set(selectedOption.rawValue, forKey: "directoryOption")
        defaults.set(customPath, forKey: "customPath")
    }
}

// MARK: - 下载服务

actor LibraryDownloader {
    private let fileManager = FileManager.default
    private let session: URLSession
    let config: DirectoryConfig

    init(config: DirectoryConfig) {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
        self.config = config
        print("当前下载目录: \(config.baseURL.path)")
    }
    
    private func buildMirrorURL(artifact: VersionManifest.Library.Downloads.Artifact) -> URL? {

        let mirrorPath = artifact.path.replacingOccurrences(
            of: "libraries.minecraft.net",
            with: "maven"
        )
        
        return URL(string: "https://bmclapi2.bangbang93.com/\(mirrorPath)")
    }

    // 获取版本清单
    func getManifest(for version: String) async throws -> VersionManifest {
        let list = try await fetchVersionList()
        guard
            let versionEntry = list.versions.first(where: { $0.id == version })
        else {
            throw DownloadError.versionNotFound
        }
        let (manifest, _) = try await fetchVersionManifest(
            from: versionEntry.url)
        return manifest
    }

    func downloadVersion(version: String) async throws -> (
        total: Int, manifest: VersionManifest, progress: AsyncStream<Int>
    ) {
        let list = try await fetchVersionList()

        guard
            let versionEntry = list.versions.first(where: { $0.id == version })
        else {
            throw DownloadError.versionNotFound
        }

        let (manifest, total) = try await fetchVersionManifest(
            from: versionEntry.url)
        return (total, manifest, downloadLibraries(manifest: manifest))
    }

    // Native 库处理方法
    func processNativeLibraries(for version: String, manifest: VersionManifest)
        async throws
    {
        let nativesDir = config.baseURL
            .appendingPathComponent("versions")
            .appendingPathComponent(version)
            .appendingPathComponent("\(version)-natives")

        try await createDirectoryIfNeeded(at: nativesDir)

        for library in manifest.libraries {
            guard shouldProcessLibrary(library) else { continue }

            let artifactPath = try getArtifactPath(for: library)
            let zipURL = config.baseURL
                .appendingPathComponent("libraries")
                .appendingPathComponent(artifactPath)

            print("正在解压 Native 库: \(zipURL.lastPathComponent)")
            try await extractNativeFiles(from: zipURL, to: nativesDir)
        }
    }

    // Native 库处理辅助方法
    private func shouldProcessLibrary(_ library: VersionManifest.Library)
        -> Bool
    {
        guard library.rules != nil || library.classifiers != nil else {
            return false
        }
        return isCompatibleWithMacOS(library: library)
    }

    private func isCompatibleWithMacOS(library: VersionManifest.Library) -> Bool
    {
        guard let rules = library.rules else { return true }
        return rules.contains { $0.os?.name.lowercased() == "osx" }
    }

    private func getArtifactPath(for library: VersionManifest.Library) throws
        -> String
    {
        if let classifier = library.classifiers?["natives-osx"] {
            return classifier.path
        }
        guard let path = library.downloads.artifact?.path else {
            throw DownloadError.missingArtifact
        }
        return path
    }

    private func extractNativeFiles(from zipURL: URL, to destination: URL)
        async throws
    {
        // 确保目标目录存在
        try await createDirectoryIfNeeded(at: destination)

        // 验证压缩包有效性
        guard let archive = Archive(url: zipURL, accessMode: .read) else {
            throw DownloadError.invalidArchive
        }

        for entry in archive {
            // 过滤非原生库文件
            guard
                entry.path.hasSuffix(".dylib")
                    || entry.path.hasSuffix(".jnilib")
            else {
                continue
            }

            // 解析完整目标路径
            let targetURL = try parseEntryPath(
                entry: entry,
                destination: destination
            )

            // 确保父目录存在
            try await createDirectoryIfNeeded(
                at: targetURL.deletingLastPathComponent())

            // 执行解压操作
            do {
                try archive.extract(entry, to: targetURL)
                print("✅ 解压成功: \(targetURL.lastPathComponent)")
            } catch {
                print(
                    """
                    ⚠️ 解压失败:
                      文件: \(entry.path)
                      目标路径: \(targetURL.path)
                      错误: \(error.localizedDescription)
                    """)
                throw error
            }
        }
    }

    private func parseEntryPath(entry: Entry, destination: URL) throws -> URL {
        // 处理路径中的非法字符
        let sanitizedPath = entry.path
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: "//", with: "/")

        // 构建完整路径
        return
            destination
            .appendingPathComponent(sanitizedPath)
            .standardizedFileURL  // 标准化路径
    }

    private func createDirectoryIfNeeded(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try fileManager.createDirectory(
                    at: url, withIntermediateDirectories: true)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - 私有方法

    private func fetchVersionList() async throws -> VersionManifestList {
        let url = URL(
            string:
                "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
        )!
        let (data, _) = try await session.data(from: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VersionManifestList.self, from: data)
    }

    private func fetchVersionManifest(from url: String) async throws -> (
        VersionManifest, Int
    ) {
        let (data, _) = try await session.data(from: URL(string: url)!)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(VersionManifest.self, from: data)
        return (manifest, manifest.libraries.count)
    }

    private func downloadLibraries(manifest: VersionManifest) -> AsyncStream<
        Int
    > {
        AsyncStream { continuation in
            Task { [weak self] in
                do {
                    try await self?.processLibraries(
                        manifest: manifest, continuation: continuation)
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    private func processLibraries(
        manifest: VersionManifest,
        continuation: AsyncStream<Int>.Continuation
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, library) in manifest.libraries.enumerated() {
                guard let artifact = library.downloads.artifact else {
                    print("跳过无 artifact 的库: \(library.name)")
                    continue
                }

                group.addTask { [weak self] in
                    try await self?.processLibrary(
                        index: index + 1,
                        artifact: artifact
                    )
                    continuation.yield(index + 1)
                }
            }
            try await group.waitForAll()
            continuation.finish()
        }
    }

    private func validateLocalFile(
        fileURL: URL,
        artifact: VersionManifest.Library.Downloads.Artifact
    ) async throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return false
        }

        // 验证文件大小
        let attributes = try FileManager.default.attributesOfItem(
            atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? Int else {
            return false
        }
        guard fileSize == artifact.size else {
            try FileManager.default.removeItem(at: fileURL)
            return false
        }

        // 验证 SHA1（仅在需要时）
        if !artifact.sha1.isEmpty {
            let calculatedSHA1 = try calculateSHA1(fileURL: fileURL)
            guard calculatedSHA1 == artifact.sha1 else {
                try FileManager.default.removeItem(at: fileURL)
                return false
            }
        }

        return true
    }

    private func processLibrary(
        index: Int, artifact: VersionManifest.Library.Downloads.Artifact
    ) async throws {

        let fileURL = config.baseURL  // 使用 config 中的 baseURL
            .appendingPathComponent("libraries")
            .appendingPathComponent(artifact.path)
        do {
            let parentDir = fileURL.deletingLastPathComponent()
            try await createDirectory(at: parentDir)

            if try await validateLocalFile(fileURL: fileURL, artifact: artifact)
            {
                print("[\(index)] 文件已存在: \(fileURL.lastPathComponent)")
                return
            }

            if try shouldSkipDownload(
                fileURL: fileURL, expectedSize: artifact.size)
            {
                print("[\(index)] 已存在: \(fileURL.lastPathComponent)")
                return
            }

            try await createDirectory(at: fileURL.deletingLastPathComponent())

            guard var components = URLComponents(string: artifact.url) else {
                throw DownloadError.invalidURL
            }
            components.host = "bmclapi2.bangbang93.com"
            components.path = "/maven" + components.path

            guard let mirrorURL = components.url else {
                throw DownloadError.invalidURL
            }

            print("[\(index)] 开始下载: \(mirrorURL.absoluteString)")
            let (tempURL, response) = try await session.download(
                from: mirrorURL)
            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                throw DownloadError.invalidResponse
            }

            try fileManager.moveItem(at: tempURL, to: fileURL)
            try validateFile(
                fileURL: fileURL, expectedSize: artifact.size,
                expectedSHA1: artifact.sha1)
            print("[\(index)] 下载完成: \(fileURL.lastPathComponent)")
        } catch {
            print(
                """
                ⚠️ 文件下载失败：
                  名称: \(artifact.path)
                  路径: \(fileURL.path)
                  错误: \(error.localizedDescription)
                """)
            throw error
        }
    }

    private func shouldSkipDownload(fileURL: URL, expectedSize: Int) throws
        -> Bool
    {
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? Int else { return false }
        return size == expectedSize
    }

    private func validateFile(
        fileURL: URL, expectedSize: Int, expectedSHA1: String
    ) throws {
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? Int, size == expectedSize else {
            throw DownloadError.fileSizeMismatch
        }

        guard try calculateSHA1(fileURL: fileURL) == expectedSHA1 else {
            try fileManager.removeItem(at: fileURL)
            throw DownloadError.sha1Mismatch
        }
    }

    private func calculateSHA1(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = Insecure.SHA1()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty
        {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
    }

    private func createDirectory(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                // 分步创建目录（解决路径中的非法字符问题）
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,  // 关键参数
                    attributes: nil
                )
                continuation.resume()
            } catch {
                print("目录创建失败: \(url.path)")
                continuation.resume(throwing: error)
            }
        }
    }
}

private func createDirectory(at url: URL) async throws {
    try await withCheckedThrowingContinuation { continuation in
        do {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(
                atPath: url.path, isDirectory: &isDir)
            {
                try FileManager.default.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,  // 关键参数
                    attributes: nil
                )
            }
            continuation.resume()
        } catch {
            print("目录创建失败: \(url.path)")
            continuation.resume(throwing: error)
        }
    }
}

// MARK: - 视图模型
@MainActor
final class DownloadManager: ObservableObject {
    // 原有属性
    @Published var isDownloading = false
    @Published var completedCount = 0
    @Published var totalCount = 0
    @Published var error: Error?
    @Published var isProcessingNatives = false

    // 新增资源下载状态
    @Published var assetCompleted = 0
    @Published var assetTotal = 0
    @Published var isDownloadingAssets = false

    private let directoryConfig = DirectoryConfig()
    private var libraryDownloader: LibraryDownloader!
    private var assetDownloader: AssetDownloader!

    private func handleError(_ error: Error) {
        if case .filePermissionDenied(let path) = error as? DownloadError {
                print("‼️ 权限拒绝路径: \(path)")
            }
        print(
            """
            \n⚠️ 错误详情:
            类型: \(type(of: error))
            描述: \(error.localizedDescription)
            堆栈: \(Thread.callStackSymbols.joined(separator: "\n"))
            """)
        self.error = error
        isDownloading = false
        isProcessingNatives = false
        isDownloadingAssets = false
    }

    func startDownload(version: String) async {
        isDownloading = true
        error = nil
        resetProgress()

        do {
            // 初始化下载器
            libraryDownloader = LibraryDownloader(config: directoryConfig)
            assetDownloader = AssetDownloader(config: directoryConfig)

            // 第一阶段：下载主库
            let (total, manifest, progressStream) =
                try await libraryDownloader.downloadVersion(version: version)
            totalCount = total
            await processLibraryProgress(stream: progressStream)

            // 第二阶段：处理原生库
            try await processNativeLibraries(
                version: version, manifest: manifest)

            // 第三阶段：下载资源
            try await downloadAssets(version: version)

        } catch {
            handleError(error)
        }

        isDownloading = false
    }

    private func resetProgress() {
        completedCount = 0
        totalCount = 0
        assetCompleted = 0
        assetTotal = 0
    }

    private func processLibraryProgress(stream: AsyncStream<Int>) async {
        // 遍历进度流，每次更新 completedCount 增加 1
        for await _ in stream {
            //            for await count in stream {
            completedCount += 1
        }
    }

    private func processNativeLibraries(
        version: String, manifest: VersionManifest
    ) async throws {
        isProcessingNatives = true
        try await libraryDownloader.processNativeLibraries(
            for: version, manifest: manifest)
        isProcessingNatives = false
    }

    private func downloadAssets(version: String) async throws {
        isDownloadingAssets = true
        assetCompleted = 0

        let assets = try await assetDownloader.prepareAssetList(
            version: version)
        assetTotal = assets.count

        // 使用分组并发控制（每组 10 个任务）
        for chunk in assets.chunked(into: 10) {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for asset in chunk {
                    group.addTask {
                        try await self.assetDownloader.downloadSingleAsset(
                            asset)
                        await MainActor.run {
                            self.assetCompleted += 1  // 主线程安全更新
                        }
                    }
                }
                try await group.waitForAll()
            }
        }

        isDownloadingAssets = false
    }
    private func retryDownload(asset: (URL, URL), maxAttempts: Int = 3)
        async throws
    {
        var attempts = 0
        repeat {
            do {
                try await self.assetDownloader.downloadSingleAsset(asset)
                await MainActor.run {
                    self.assetCompleted += 1
                }
                return
            } catch {
                attempts += 1
                if attempts >= maxAttempts { throw error }
                await Task.sleep(1_000_000_000 * UInt64(attempts))  // 指数退避
            }
        } while attempts < maxAttempts
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
