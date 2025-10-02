import SwiftUI

struct ContentView: View {
    @ObservedObject var vm: LidAngleVM
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text(vm.angleText)
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .foregroundColor(vm.angleTextColor)
                    .frame(maxWidth: .infinity)
                
                Text(vm.velocityText)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                
                Text(vm.statusText)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundColor(vm.statusTextColor)
                    .frame(maxWidth: .infinity)
            }
            
            VStack(spacing: 16) {
                Button(action: vm.toggleAudio) {
                    Text(vm.audioButtonTitle)
                        .frame(maxWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.audioControlsEnabled)
                
                if !vm.audioStatusText.isEmpty {
                    Text(vm.audioStatusText)
                        .font(.system(size: 14))
                        .foregroundColor(vm.audioStatusColor)
                        .frame(maxWidth: .infinity)
                }
            }
            
            VStack(spacing: 8) {
                Text("Audio Mode")
                    .font(.system(size: 15, weight: .medium))
                
                Picker("", selection: $vm.audioMode) {
                    ForEach(AudioMode.allCases) {
                        Text($0.title)
                            .tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(!vm.audioControlsEnabled)
            }
            
            Spacer()
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 420)
    }
}
