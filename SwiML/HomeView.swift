import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .blur(radius: 4)
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    Button {} label: {
                        HStack {
                            Image(systemName: "paperplane")
                            
                            Text("启动游戏")
                            
                        }.background {
                            Rectangle()
                                .fill(Color.blue)
                                .cornerRadius(10)
                                .frame(width: 150, height: 50)
                                .scaledToFit()
                        }
                    }
                    .buttonStyle(.plain) // 移除默认样式
                    
                }.padding(.bottom, 40)
            }.padding(.trailing, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // 确保 ZStack 撑满窗口
        .navigationTitle("SwiML")
    }
}

#Preview {
    HomeView()
}
