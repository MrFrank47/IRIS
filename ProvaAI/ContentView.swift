import SwiftUI

struct ContentView: View {
    @StateObject private var model = ColorDetectorModel()
    
    var body: some View {
        ZStack {
            CameraPreview(session: model.session)
                .ignoresSafeArea()
            
            VStack {
               // Spacer()
                
                VStack(spacing: 20) {
                    Circle()
                        .fill(model.detectedColor)
                        .frame(width: 50, height: 50)
                        //.overlay(Circle().stroke(Color.white, lineWidth: 2))
                    
                    Text(model.rgbString)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding()
                        .background(.black)
                        .cornerRadius(10)
                }
                .padding(.bottom, 50)
            }
            
//            Image(systemName: "plus")
//                .font(.system(size: 30, weight: .thin))
//                .foregroundColor(.white.opacity(0.5))
        }
    }
}

#Preview{
    ContentView()
}
