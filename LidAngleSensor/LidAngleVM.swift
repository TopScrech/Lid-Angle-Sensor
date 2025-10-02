import SwiftUI
import Combine
import os.log

final class LidAngleVM: ObservableObject {
    // Display properties
    @Published var angleText: String
    @Published var statusText: String
    @Published var velocityText: String
    @Published var audioStatusText: String
    @Published var audioButtonTitle: String
    @Published var audioControlsEnabled: Bool
    @Published var angleTextColor: Color
    @Published var statusTextColor: Color
    @Published var audioStatusColor: Color
    
    @Published var audioMode: AudioMode {
        didSet {
            guard audioMode != oldValue else {
                return
            }
            
            handleAudioModeSwitch(from: oldValue)
        }
    }
    
    private let sensor: LidAngleSensor?
    private let audioEngines: [AudioMode: any LidAngleAudioEngine]
    private var updateTimer: AnyCancellable?
    private let log = Logger(subsystem: "com.gold.samhenri.LidAngleSensor", category: "ViewModel")
    private let updateInterval: TimeInterval = 0.016
    private var isPreview: Bool
    
    init(sensor: LidAngleSensor? = nil, previewMode: Bool = false) {
        self.isPreview = previewMode
        self.angleText = "Initializing..."
        self.statusText = "Detecting sensor..."
        self.velocityText = "Velocity: 00 deg/s"
        self.audioStatusText = ""
        self.audioButtonTitle = "Start Audio"
        self.audioControlsEnabled = false
        self.angleTextColor = .accentColor
        self.statusTextColor = .secondary
        self.audioStatusColor = .secondary
        self.audioMode = .creak
        
        if previewMode {
            self.sensor = nil
            self.audioEngines = [:]
            configurePreviewState()
            return
        }
        
        let activeSensor: LidAngleSensor?
        
        if let providedSensor = sensor {
            activeSensor = providedSensor
        } else {
            activeSensor = LidAngleSensor()
        }
        
        self.sensor = activeSensor
        
        var engines: [AudioMode: any LidAngleAudioEngine] = [:]
        
        if let creak = CreakAudioEngine() {
            engines[.creak] = creak
        }
        
        if let theremin = ThereminAudioEngine() {
            engines[.theremin] = theremin
        }
        
        self.audioEngines = engines
        self.audioControlsEnabled = engines.count == AudioMode.allCases.count
        
        if !audioControlsEnabled {
            audioStatusText = "Audio initialization failed"
            audioStatusColor = .red
        }
        
        if let sensor = self.sensor, sensor.isAvailable {
            statusText = "Sensor detected - Reading angle..."
            statusTextColor = .green
            startTimer()
        } else {
            statusText = "Lid angle sensor not available on this device"
            statusTextColor = .red
            angleText = "Not Available"
            angleTextColor = .red
        }
    }
    
    deinit {
        updateTimer?.cancel()
        sensor?.stopLidAngleUpdates()
        
        audioEngines.values.forEach { engine in
            if engine.isRunning {
                engine.stop()
            }
        }
    }
    
    func toggleAudio() {
        guard audioControlsEnabled, let engine = currentEngine else {
            return
        }
        
        if engine.isRunning {
            engine.stop()
            audioButtonTitle = "Start Audio"
            audioStatusText = ""
        } else {
            if engine.start() {
                audioButtonTitle = "Stop Audio"
                refreshAudioStatus(using: engine)
            } else {
                audioStatusText = "Failed to start audio engine"
                audioStatusColor = .red
            }
        }
    }
    
    private func startTimer() {
        updateTimer = Timer.publish(every: updateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollSensor()
            }
    }
    
    private func pollSensor() {
        guard !isPreview, let sensor else {
            return
        }
        
        let angle = sensor.lidAngle()
        
        if angle == -2 {
            angleText = "Read Error"
            angleTextColor = .orange
            statusText = "Failed to read sensor data"
            statusTextColor = .orange
            audioStatusText = ""
            return
        }
        
        angleText = String(format: "%.1f°", angle)
        angleTextColor = .blue
        statusText = statusForAngle(angle)
        statusTextColor = .secondary
        
        if let engine = currentEngine {
            engine.update(angle: angle)
            updateVelocityDisplay(with: engine.currentVelocity)
            
            if engine.isRunning {
                refreshAudioStatus(using: engine)
            } else {
                audioStatusText = ""
            }
        } else {
            updateVelocityDisplay(with: 0)
        }
    }
    
    private func updateVelocityDisplay(with velocity: Double) {
        let rounded = Int(round(velocity))
        
        if rounded < 100 {
            velocityText = String(format: "Velocity: %02d deg/s", max(0, rounded))
        } else {
            velocityText = String(format: "Velocity: %d deg/s", max(0, rounded))
        }
    }
    
    private func refreshAudioStatus(using engine: any LidAngleAudioEngine) {
        audioStatusText = engine.statusDescription
        audioStatusColor = .secondary
    }
    
    private func statusForAngle(_ angle: Double) -> String {
        switch angle {
        case ..<5.0:   "Lid is closed"
        case ..<45.0:  "Lid slightly open"
        case ..<90.0:  "Lid partially open"
        case ..<120.0: "Lid mostly open"
        default:       "Lid fully open"
        }
    }
    
    private var currentEngine: (any LidAngleAudioEngine)? {
        audioEngines[audioMode]
    }
    
    private func handleAudioModeSwitch(from oldMode: AudioMode) {
        guard audioControlsEnabled else {
            return
        }
        
        let previousEngine = audioEngines[oldMode]
        let wasRunning = previousEngine?.isRunning == true
        previousEngine?.stop()
        
        audioButtonTitle = wasRunning ? "Stop Audio" : "Start Audio"
        audioStatusText = ""
        
        guard wasRunning, let newEngine = currentEngine else {
            audioButtonTitle = "Start Audio"
            return
        }
        
        if newEngine.start() {
            refreshAudioStatus(using: newEngine)
        } else {
            audioButtonTitle = "Start Audio"
            audioStatusText = "Failed to start audio engine"
            audioStatusColor = .red
        }
    }
    
    private func configurePreviewState() {
        angleText = "093.4°"
        angleTextColor = .blue
        statusText = "Lid mostly open"
        statusTextColor = .secondary
        velocityText = "Velocity: 03 deg/s"
        audioStatusText = "Gain: 0.42, Rate: 0.95"
        audioStatusColor = .secondary
        audioControlsEnabled = true
    }
}
