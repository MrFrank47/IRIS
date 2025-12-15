import SwiftUI

struct ContentView: View {
    @StateObject private var model = ColorDetectorModel()
    @State private var showInfo = false
    
    var body: some View {
        ZStack {
            if let frame = model.processedFrame {
                GeometryReader { geo in
                    Image(decorative: frame, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // Top info bulb
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "lightbulb")
                            .font(.title2)
                            .padding(10)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                            .foregroundColor(.white)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 12)
                }
                Spacer()
            }
            
            // Bottom controls
            VStack {
                Spacer()
                bottomBar
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet()
        }
    }
    
    private var bottomBar: some View {
        HStack(spacing: 14) {
            // D / P / T / 4 buttons
            ForEach(VisionMode.allCases) { mode in
                let isSelected = model.selectedMode == mode
                
                Button {
                    model.selectMode(mode)
                } label: {
                    Text(mode.symbol)
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(isSelected ? Color.white : Color.black.opacity(0.6))
                        )
                        .foregroundColor(isSelected ? .black : .white)
                }
            }
            
            // Black & White toggle next to buttons
            Toggle(isOn: $model.isGrayscaleEnabled) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundColor(.white)
            }
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: .white))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }
}

private struct InfoSheet: View {
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(VisionMode.allCases) { mode in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(mode.symbol) — \(mode.title)")
                            .font(.headline)
                        Text(mode.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Vision modes")
        }
    }
}

#Preview {
    ContentView()
}
