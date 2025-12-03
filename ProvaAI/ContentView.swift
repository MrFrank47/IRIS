import SwiftUI

struct ContentView: View {
    @StateObject private var model = ColorDetectorModel()
    
    var body: some View {
        ZStack {
            // Processed camera frame (blurred background + highlighted colors)
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
            
            VStack {
                Spacer()
                
                // Circle with center color
                Circle()
                    .fill(model.detectedColor)
                    .frame(width: 70, height: 70)
                    .shadow(radius: model.detectedColor == .clear ? 0 : 10)
                    .padding(.bottom, 24)
                
                colorSelectionBar
            }
        }
    }
    
    private var colorSelectionBar: some View {
        HStack(spacing: 12) {
            ForEach(TrackedColor.allCases) { tracked in
                let isSelected = model.selectedColors.contains(tracked)
                
                Button {
                    model.toggleColor(tracked)
                } label: {
                    Text(tracked.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? tracked.color : Color.black.opacity(0.6))
                        )
                        .foregroundColor(.white)
                        .overlay(
                            Capsule()
                                .stroke(tracked.color, lineWidth: isSelected ? 2 : 1)
                        )
                        .scaleEffect(isSelected ? 1.1 : 1.0)
                        .animation(.spring(response: 0.25,
                                           dampingFraction: 0.7),
                                   value: isSelected)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 30)
    }
}

#Preview {
    ContentView()
}
