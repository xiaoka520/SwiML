import SwiftUI

struct GameSettingsView: View {
    @EnvironmentObject var config: DirectoryConfig
    @State private var showFilePicker = false
    @State private var isMacOS: Bool = {
        // 检查是否是 macOS 平台
        if #available(macOS 11.0, *) {
            return true
        } else {
            return false
        }
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("游戏目录位置", selection: $config.selectedOption) {
                Text("用户文档目录").tag(DirectoryConfig.DirectoryOption.documents)
                Text("SwiML内").tag(DirectoryConfig.DirectoryOption.appBundle)
                Text("当前目录").tag(DirectoryConfig.DirectoryOption.appParent)
                Text("自定义").tag(DirectoryConfig.DirectoryOption.custom)
            }
            .pickerStyle(.radioGroup)
            
            if config.selectedOption == .custom {
                HStack {
                    TextField("路径", text: $config.customPath)
                        .disabled(true)
                    
                    // 只有在 macOS 上显示选择目录按钮
                    if isMacOS {
                        Button("选择目录") {
                            showFilePicker.toggle()
                        }
                    }
                }
            }
            
            // 显示当前路径
            Text("当前路径：\(config.baseURL.path.isEmpty ? "无效路径" : config.baseURL.path)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result: result)
        }
        .padding()
    }
    
    private func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            config.customPath = url.path
        case .failure(let error):
            print("目录选择错误: \(error.localizedDescription)")
        }
    }
}

#Preview {
    GameSettingsView()
        .frame(width: 400, height: 300)
        .environmentObject(DirectoryConfig()) // 这里注入 DirectoryConfig
}
