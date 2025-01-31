import SwiftUI

enum AppRoute: Hashable, CaseIterable {
    case home
    case verlist
    case settings
    
    var title: String {
        switch self {
        case .home: return "首页"
        case .settings: return "设置"
        case .verlist: return "版本列表"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .home:
            HomeView()
        case .settings:
            SettingsView()
        case .verlist:
            VerlistView()
        }
    }
}

struct ContentView: View {
    @State private var selectedRoute: AppRoute? = .home
    
    var body: some View {
        NavigationSplitView {
            // 左侧边栏
            List(AppRoute.allCases, id: \.self, selection: $selectedRoute) { route in
                NavigationLink(route.title, value: route)
            }
            .navigationTitle("导航菜单")
            .listStyle(.sidebar)
            
        } detail: {
            NavigationStack {
                if let selectedRoute {
                    selectedRoute.destination
                } else {
                    Text("请选择页面")
                }
            }
        }
        
    }
}

#Preview {
    ContentView()
}
