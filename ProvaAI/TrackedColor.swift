import SwiftUI

enum TrackedColor: String, CaseIterable, Identifiable {
    case red
    case green
    case blue
    case yellow
    
    var id: String { rawValue }
    
    var hueRangeDegrees: (min: Double, max: Double) {
        switch self {
        case .red:    return (min: 330, max: 30)   // wrap-around
        case .yellow: return (min: 40,  max: 80)
        case .green:  return (min: 80,  max: 160)
        case .blue:   return (min: 180, max: 260)  // includes cyan-ish to deep blue/navy
        }
    }
    
    var minSaturation: Double {
        switch self {
        case .red:    return 0.20
        case .yellow: return 0.20
        case .green:  return 0.18
        case .blue:   return 0.18
        }
    }
    
    var minValue: Double {
        switch self {
        case .red:    return 0.15
        case .yellow: return 0.20
        case .green:  return 0.12
        case .blue:   return 0.08
        }
    }
}
