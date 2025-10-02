enum AudioMode: Int, CaseIterable, Identifiable {
    case creak, theremin
    
    var id: Int {
        rawValue
    }
    
    var title: String {
        switch self {
        case .creak: "Creak"
        case .theremin: "Theremin"
        }
    }
}
