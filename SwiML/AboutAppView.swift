import SwiftUI

struct AboutAppView: View {
    var body: some View {
        ZStack {
//            Image("background")
//                .resizable()
//                .scaledToFill()
//                .ignoresSafeArea(.all)
//                .frame(
//                    maxWidth: .infinity,
//                    maxHeight: .infinity
//                )
//                .blur(radius: 4)
            
            VStack {
                Image("icon-128x128")
                                .resizable()
                                .frame(width: 100, height: 100)
                                .cornerRadius(20)
                                .shadow(radius: 10)
                Text("SwiML")
                Text("1.0.0")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 确保 ZStack 撑满窗口
        
    }
}

#Preview {
    AboutAppView()
        .frame(width: 400.0, height: 300.0)
}
