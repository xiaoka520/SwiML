import SwiftUI

struct VerlistView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var selectedVersion = "1.21"
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Minecraft下载")
                .alert("下载错误", isPresented: .constant(downloadManager.error != nil)) {
                    Button("确定") { downloadManager.error = nil }
                } message: {
                    Text(downloadManager.error?.localizedDescription ?? "未知错误")
                }
        }
    }
    
    private var content: some View {
        VStack(spacing: 20) {
            versionPicker
            downloadButton
            progressSection
            Spacer()
        }
        .padding(.top, 20)
        .padding(.horizontal)
    }
    
    private var versionPicker: some View {
        Picker("Minecraft 版本", selection: $selectedVersion) {
            Text("1.21").tag("1.21")
            Text("1.20").tag("1.20")
            Text("1.19").tag("1.19")
        }
        .pickerStyle(.segmented)
    }
    
    private var downloadButton: some View {
        Button(action: startDownload) {
            HStack {
                Image(systemName: "arrow.down.circle")
                statusLabel
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .disabled(isDownloading)
    }
    
    private var statusLabel: some View {
        Group {
            if downloadManager.isProcessingNatives {
                Text("正在解压原生库...")
            } else if downloadManager.isDownloadingAssets {
                Text("正在下载资源...")
            } else if downloadManager.isDownloading {
                Text("正在下载主库...")
            } else {
                Text("开始下载")
            }
        }
    }
    
    private var progressSection: some View {
        Group {
            if downloadManager.isDownloading || downloadManager.isProcessingNatives || downloadManager.isDownloadingAssets {
                VStack(spacing: 12) {
                    if downloadManager.totalCount > 0 {
                        ProgressView(
                            value: Double(downloadManager.completedCount),
                            total: Double(downloadManager.totalCount)
                        )
                        .progressViewStyle(.linear)
                        .animation(.default, value: downloadManager.completedCount)
                    }
                    
                    if downloadManager.assetTotal > 0 {
                        ProgressView(
                            value: Double(downloadManager.assetCompleted),
                            total: Double(downloadManager.assetTotal)
                        )
                        .progressViewStyle(.linear)
                        .animation(.default, value: downloadManager.assetCompleted)
                    }
                    
                    statusDetails
                }
            }
        }
    }
    
    private var statusDetails: some View {
        VStack(alignment: .leading) {
            if downloadManager.totalCount > 0 {
                Text("主库文件: \(downloadManager.completedCount)/\(downloadManager.totalCount)")
                    .font(.caption)
            }
            
            if downloadManager.assetTotal > 0 {
                Text("资源文件: \(downloadManager.assetCompleted)/\(downloadManager.assetTotal)")
                    .font(.caption)
            }
        }
        .foregroundColor(.gray)
    }
    
    private var isDownloading: Bool {
        downloadManager.isDownloading ||
        downloadManager.isProcessingNatives ||
        downloadManager.isDownloadingAssets
    }
    
    private func startDownload() {
        Task {
            await downloadManager.startDownload(version: selectedVersion)
        }
    }
}

// 预览
#Preview {
    VerlistView()
}
