import SwiftUI

struct SettingsView: View {
    var body: some View {
        ZStack{
            Button {
                
            } label: {
                Text("TEST")
                
            }
        }
        .navigationTitle("设置")
    }
}

#Preview {
    SettingsView()
        .frame(width: 800.0, height: 600.0)
}
