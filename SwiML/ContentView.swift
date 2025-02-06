import SwiftUI

/// 统一的路由枚举，包含两种子路由
enum Route: Hashable {
    case app(AppRoute)
    case settings(SettingsRoute)
}

/// App 部分的路由
enum AppRoute: Hashable, CaseIterable {
    case home
    case verlist
    
    var title: String {
        switch self {
        case .home: return "首页"
        case .verlist: return "版本列表"
        }
    }
    
    /// 对应的目标视图
    @ViewBuilder
    var destination: some View {
        switch self {
        case .home:
            HomeView()
        case .verlist:
            VerlistView()
        }
    }
}

/// 设置部分的路由
enum SettingsRoute: Hashable, CaseIterable {
    case gamesettings
    case aboutapp
    
    var title: String {
        switch self {
        case .gamesettings: return "全局游戏设置"
        case .aboutapp: return "关于"
        }
    }
    
    /// 对应的目标视图
    @ViewBuilder
    var destination: some View {
        switch self {
        case .gamesettings:
            GameSettingsView()
        case .aboutapp:
            AboutAppView()
        }
    }
}

struct ContentView: View {
    /// 当前选中的路由
    @State private var selectedRoute: Route? = .app(.home)
    
    var body: some View {
        NavigationSplitView {
            // 根据 selectedRoute 判断显示哪部分侧边栏内容
            if case .settings = selectedRoute {
                // 设置侧边栏：只显示 SettingsRoute 列表，并在顶部提供返回链接
                List(selection: $selectedRoute) {
                    Section {
                        // 返回项：通过 NavigationLink 跳转回 App 部分
                        NavigationLink(value: Route.app(.home)) {
                            Label("返回", systemImage: "chevron.left")
                        }
                    }
                    
                    ForEach(SettingsRoute.allCases, id: \.self) { settingsRoute in
                        NavigationLink(value: Route.settings(settingsRoute)) {
                            Label(settingsRoute.title, systemImage: imageName(for: settingsRoute))
                        }
                    }
                }
                .navigationTitle("设置菜单")
                .listStyle(.sidebar)
            } else {
                // App 侧边栏：显示 AppRoute 列表，并在“通用”区使用 NavigationLink 跳转到设置
                List(selection: $selectedRoute) {
                    Section(header: Text("游戏")) {
                        ForEach(AppRoute.allCases, id: \.self) { appRoute in
                            NavigationLink(value: Route.app(appRoute)) {
                                Label(appRoute.title, systemImage: imageName(for: appRoute))
                            }
                        }
                    }
                    
                    Section(header: Text("通用")) {
                        // 这里使用 NavigationLink 跳转到 SettingsRoute 的第一个作为默认项
                        NavigationLink(value: Route.settings(SettingsRoute.allCases.first!)) {
                            Label("设置", systemImage: "gearshape")
                        }
                    }
                }
                .navigationTitle("导航菜单")
                .listStyle(.sidebar)
            }
        } detail: {
            // detail 区域根据 selectedRoute 显示对应视图
            if let route = selectedRoute {
                switch route {
                case .app(let appRoute):
                    appRoute.destination
                case .settings(let settingsRoute):
                    settingsRoute.destination
                }
            } else {
                Text("请选择页面")
            }
        }
    }
    
    /// 根据 AppRoute 返回对应的系统图标名称
    private func imageName(for route: AppRoute) -> String {
        switch route {
        case .home:
            return "house"
        case .verlist:
            return "list.bullet"
        }
    }
    
    /// 根据 SettingsRoute 返回对应的系统图标名称
    private func imageName(for route: SettingsRoute) -> String {
        switch route {
        case .aboutapp:
            return "exclamationmark.circle"
        case .gamesettings:
            return "gamecontroller"
        }
    }
}



#Preview {
    ContentView()
        .environmentObject(DirectoryConfig())
}
