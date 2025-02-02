import SwiftUI

struct VerlistView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var selectedVersion = "1.21"
    
    var body: some View {
        VStack(spacing: 20) {
            Picker("Minecraft 版本", selection: $selectedVersion) {
                Text("1.21").tag("1.21")
                Text("1.20").tag("1.20")
                Text("1.19").tag("1.19")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            Button(action: startDownload) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Group {
                        if downloadManager.isProcessingNatives {
                            Text("正在解压原生库...")
                        } else {
                            Text(downloadManager.isDownloading ? "下载中..." : "开始下载")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(downloadManager.isDownloading || downloadManager.isProcessingNatives)
            .padding(.horizontal)
            
            if downloadManager.isDownloading || downloadManager.isProcessingNatives {
                VStack {
                    ProgressView(
                        value: Double(downloadManager.completedCount),
                        total: Double(downloadManager.totalCount)
                    )
                    .progressViewStyle(LinearProgressViewStyle())
                    
                    Text(
                        downloadManager.isProcessingNatives ?
                        "正在处理原生库..." :
                        "已下载 \(downloadManager.completedCount)/\(downloadManager.totalCount) 个文件"
                    )
                    .font(.caption)
                    .foregroundColor(.gray)
                }
                .padding(.horizontal)
            }
            
            if let error = downloadManager.error {
                Text("错误: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            Spacer()
        }
        .padding(.top, 20)
        .navigationTitle("Minecraft下载")
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
