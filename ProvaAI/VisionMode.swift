import SwiftUI

enum VisionMode: String, CaseIterable, Identifiable {
    case deuteranomaly
    case protanomaly
    case tritanomaly
    case normal
    
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .deuteranomaly: return "D"
        case .protanomaly:  return "P"
        case .tritanomaly:  return "T"
        case .normal:       return "NV"
        }
    }
    
    var title: String {
        switch self {
        case .deuteranomaly: return "Deuteranomaly (D)"
        case .protanomaly:  return "Protanomaly (P)"
        case .tritanomaly:  return "Tritanomaly (T)"
        case .normal:       return "Normal vision (NV)"
        }
    }
    
    var description: String {
        switch self {
        case .deuteranomaly:
            return "Reduced sensitivity to green light. Red/green confusion is common."
        case .protanomaly:
            return "Reduced sensitivity to red light. Reds can look darker and less distinct."
        case .tritanomaly:
            return "Reduced sensitivity to blue light. Blue/yellow confusion can happen."
        case .normal:
            return "No color vision deficiency simulation/highlighting."
        }
    }
}
