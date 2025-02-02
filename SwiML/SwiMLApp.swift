import SwiftUI

@main
struct SwiMLApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(DirectoryConfig())
        }
    }
}
