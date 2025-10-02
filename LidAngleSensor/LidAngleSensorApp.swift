import SwiftUI

@main
struct LidAngleSensorApp: App {
    @StateObject private var vm = LidAngleVM()
    
    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .frame(
                    minWidth: 420, idealWidth: 450, maxWidth: 520,
                    minHeight: 420, idealHeight: 480, maxHeight: 520
                )
        }
    }
}
