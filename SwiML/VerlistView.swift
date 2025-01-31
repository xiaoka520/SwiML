import SwiftUI

struct VerlistView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var selectedVersion = "1.21" // 默认版本
    
    var body: some View {
        VStack(spacing: 20) {
            // 版本选择器
            Picker("Minecraft 版本", selection: $selectedVersion) {
                Text("1.21").tag("1.21")
                Text("1.20").tag("1.20")
                Text("1.19").tag("1.19")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // 下载按钮
            Button(action: startDownload) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text(downloadManager.isDownloading ? "下载中..." : "开始下载")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(downloadManager.isDownloading)
            .padding(.horizontal)
            
            // 进度条
            if downloadManager.isDownloading {
                VStack {
                    ProgressView(
                        value: Double(downloadManager.completedCount),
                        total: Double(downloadManager.totalCount)
                    )
                    .progressViewStyle(LinearProgressViewStyle())
                    
                    Text("已下载 \(downloadManager.completedCount)/\(downloadManager.totalCount) 个文件")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
            }
            
            // 错误提示
            if let error = downloadManager.error {
                Text("错误: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
        }
        .padding(.top, 20)
        .navigationTitle("Minecraft 依赖库下载")
    }
    
    // 触发下载
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
