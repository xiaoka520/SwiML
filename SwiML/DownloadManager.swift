import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

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
        let time: Date
        let releaseTime: Date
    }
}

struct VersionManifest: Decodable {
    let libraries: [Library]
    
    struct Library: Decodable {
        let downloads: Downloads
        let name: String
        
        struct Downloads: Decodable {
            let artifact: Artifact?
            
            struct Artifact: Decodable {
                let path: String
                let sha1: String
                let size: Int
                let url: String
            }
        }
    }
}

// MARK: - 错误类型

enum DownloadError: Error {
    case invalidURL
    case invalidResponse
    case fileSizeMismatch
    case sha1Mismatch
    case directoryCreationFailed
    case versionNotFound
    case invalidManifest
    case invalidDirectory
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
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent(".minecraft")
            
        case .appBundle:
            return appBundleURL
                .appendingPathComponent("Minecraft")
            
        case .appParent:
            return appBundleURL
                .deletingLastPathComponent()
                .appendingPathComponent(".minecraft")
            
        case .custom:
            return URL(fileURLWithPath: customPath)
        }
    }
    
    private func loadConfig() {
        selectedOption = DirectoryOption(
            rawValue: defaults.integer(forKey: "directoryOption")) ?? .documents
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
    
    func downloadVersion(version: String) async throws -> (total: Int, progress: AsyncStream<Int>) {
        let list = try await fetchVersionList()
        
        guard let versionEntry = list.versions.first(where: { $0.id == version }) else {
            throw DownloadError.versionNotFound
        }
        
        let (manifest, total) = try await fetchVersionManifest(from: versionEntry.url)
        return (total, downloadLibraries(manifest: manifest))
    }
    
    // MARK: - 私有方法

    private func fetchVersionList() async throws -> VersionManifestList {
        let url = URL(string: "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json")!
        let (data, _) = try await session.data(from: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VersionManifestList.self, from: data)
    }
    
    private func fetchVersionManifest(from url: String) async throws -> (VersionManifest, Int) {
        let (data, _) = try await session.data(from: URL(string: url)!)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(VersionManifest.self, from: data)
        return (manifest, manifest.libraries.count)
    }
    
    private func downloadLibraries(manifest: VersionManifest) -> AsyncStream<Int> {
        AsyncStream { continuation in
            Task { [weak self] in
                do {
                    try await self?.processLibraries(manifest: manifest, continuation: continuation)
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
    
    private func processLibrary(index: Int, artifact: VersionManifest.Library.Downloads.Artifact) async throws {
            let fileURL = config.baseURL  // 使用 config 中的 baseURL
                .appendingPathComponent("libraries")
                .appendingPathComponent(artifact.path)
        
        if try shouldSkipDownload(fileURL: fileURL, expectedSize: artifact.size) {
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
        let (tempURL, response) = try await session.download(from: mirrorURL)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DownloadError.invalidResponse
        }
        
        try fileManager.moveItem(at: tempURL, to: fileURL)
        try validateFile(fileURL: fileURL, expectedSize: artifact.size, expectedSHA1: artifact.sha1)
        print("[\(index)] 下载完成: \(fileURL.lastPathComponent)")
    }
    
    private func shouldSkipDownload(fileURL: URL, expectedSize: Int) throws -> Bool {
        guard fileManager.fileExists(atPath: fileURL.path) else { return false }
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? Int else { return false }
        return size == expectedSize
    }
    
    private func validateFile(fileURL: URL, expectedSize: Int, expectedSHA1: String) throws {
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
        while let data = try? handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        
        return hasher.finalize().map { String(format: "%02hhx", $0) }.joined()
    }
    
    private func createDirectory(at url: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                continuation.resume()
            } catch {
                continuation.resume(throwing: DownloadError.directoryCreationFailed)
            }
        }
    }
}

// MARK: - 视图模型（修复初始化逻辑）
@MainActor
final class DownloadManager: ObservableObject {
    @Published var isDownloading = false
    @Published var completedCount = 0
    @Published var totalCount = 0
    @Published var error: Error?
    
    private let directoryConfig = DirectoryConfig()  // 统一配置管理
    private var downloader: LibraryDownloader!
    
    func startDownload(version: String) async {
        isDownloading = true
        error = nil
        completedCount = 0
        totalCount = 0
        
        do {
            // 每次创建新的下载器以获取最新配置
            downloader = LibraryDownloader(config: directoryConfig)
            
            // 开始下载
            let (total, progressStream) = try await downloader.downloadVersion(version: version)
            totalCount = total
            
            for await progress in progressStream {
                completedCount = progress
            }
        } catch {
            self.error = error
        }
        
        isDownloading = false
    }
}
