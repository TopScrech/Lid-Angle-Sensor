import AVFoundation
import QuartzCore
import os.log

final class ThereminAudioEngine: LidAngleAudioEngine {
    private let audioEngine: AVAudioEngine
    private let mixerNode: AVAudioMixerNode
    private let renderFormat: AVAudioFormat
    
    private lazy var sourceNode = {
        AVAudioSourceNode(format: renderFormat) { [weak self] _, _, frameCount, audioBufferList in
            guard let self else {
                return noErr
            }
            
            return self.renderSineWave(frameCount: frameCount, audioBufferList: audioBufferList)
        }
    }()
    
    private var lastLidAngle = 0.0
    private var smoothedLidAngle = 0.0
    private var lastUpdateTime = CACurrentMediaTime()
    private var smoothedVelocity = 0.0
    private var targetFrequency = minFrequency
    private var targetVolume = baseVolume
    private var currentFrequencyValue = minFrequency
    private var currentVolumeValue = baseVolume
    private var isFirstUpdate = true
    private var lastMovementTime = CACurrentMediaTime()
    private var lastRampTime: Double?
    
    private var phase = 0.0
    private var phaseIncrement = 2 * .pi * minFrequency / sampleRate
    private var vibratoPhase = 0.0
    private let log = Logger(subsystem: "com.gold.samhenri.LidAngleSensor", category: "ThereminAudio")
    
    private static let minFrequency = 110.0
    private static let maxFrequency = 440.0
    private static let minAngle = 0.0
    private static let maxAngle = 135.0
    private static let baseVolume = 0.6
    private static let velocityVolumeBoost = 0.4
    private static let velocityFull = 8.0
    private static let velocityQuiet = 80.0
    private static let vibratoFrequency = 5.0
    private static let vibratoDepth = 0.03
    private static let angleSmoothingFactor = 0.1
    private static let velocitySmoothingFactor = 0.3
    private static let frequencyRampTimeMs = 30.0
    private static let volumeRampTimeMs = 50.0
    private static let movementThreshold = 0.3
    private static let movementTimeoutMs = 100.0
    private static let velocityDecayFactor = 0.7
    private static let additionalDecayFactor = 0.85
    private static let sampleRate = 44_100.0
    
    init?() {
        audioEngine = AVAudioEngine()
        mixerNode = audioEngine.mainMixerNode
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false) else {
            log.error("Failed to create theremin audio format")
            return nil
        }
        
        renderFormat = format
        
        audioEngine.attach(sourceNode)
        audioEngine.connect(sourceNode, to: mixerNode, format: renderFormat)
    }
    
    var isRunning: Bool {
        audioEngine.isRunning
    }
    
    var currentVelocity: Double {
        smoothedVelocity
    }
    
    var statusDescription: String {
        guard isRunning else {
            return ""
        }
        
        return String(format: "Freq: %.1f Hz, Vol: %.2f", currentFrequencyValue, currentVolumeValue)
    }
    
    @discardableResult
    func start() -> Bool {
        guard !audioEngine.isRunning else {
            return true
        }
        
        do {
            try audioEngine.start()
            return true
        } catch {
            log.error("Failed to start theremin engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    func stop() {
        guard audioEngine.isRunning else {
            return
        }
        
        audioEngine.stop()
        lastRampTime = nil
    }
    
    func update(angle: Double) {
        let currentTime = CACurrentMediaTime()
        
        if isFirstUpdate {
            lastLidAngle = angle
            smoothedLidAngle = angle
            lastUpdateTime = currentTime
            lastMovementTime = currentTime
            isFirstUpdate = false
            updateTargets(angle: angle, velocity: 0)
            return
        }
        
        let deltaTime = currentTime - lastUpdateTime
        
        guard deltaTime > 0, deltaTime <= 1 else {
            lastUpdateTime = currentTime
            return
        }
        
        smoothedLidAngle = Self.angleSmoothingFactor * angle + (1 - Self.angleSmoothingFactor) * smoothedLidAngle
        
        let deltaAngle = smoothedLidAngle - lastLidAngle
        let instantVelocity: Double
        
        if abs(deltaAngle) < Self.movementThreshold {
            instantVelocity = 0
        } else {
            instantVelocity = abs(deltaAngle / deltaTime)
            lastLidAngle = smoothedLidAngle
        }
        
        if instantVelocity > 0 {
            smoothedVelocity = Self.velocitySmoothingFactor * instantVelocity + (1 - Self.velocitySmoothingFactor) * smoothedVelocity
            lastMovementTime = currentTime
        } else {
            smoothedVelocity *= Self.velocityDecayFactor
        }
        
        let timeSinceMovement = currentTime - lastMovementTime
        
        if timeSinceMovement > (Self.movementTimeoutMs / 1000) {
            smoothedVelocity *= Self.additionalDecayFactor
        }
        
        lastUpdateTime = currentTime
        updateTargets(angle: smoothedLidAngle, velocity: smoothedVelocity)
        rampToTargets()
    }
    
    private func updateTargets(angle: Double, velocity: Double) {
        let clampedAngle = min(max(angle, Self.minAngle), Self.maxAngle)
        let normalizedAngle = (clampedAngle - Self.minAngle) / (Self.maxAngle - Self.minAngle)
        let frequencyRatio = pow(normalizedAngle, 0.7)
        targetFrequency = Self.minFrequency + frequencyRatio * (Self.maxFrequency - Self.minFrequency)
        
        var velocityBoost = 0.0
        
        if velocity > 0 {
            let e0 = 0.0
            let e1 = Self.velocityQuiet
            let t = min(1, max(0, (velocity - e0) / (e1 - e0)))
            let smooth = t * t * (3 - 2 * t)
            velocityBoost = (1 - smooth) * Self.velocityVolumeBoost
        }
        
        targetVolume = min(1, max(0, Self.baseVolume + velocityBoost))
    }
    
    private func rampToTargets() {
        let currentTime = CACurrentMediaTime()
        let deltaTime: Double
        
        if let lastRampTime {
            deltaTime = currentTime - lastRampTime
        } else {
            deltaTime = 0
        }
        
        lastRampTime = currentTime
        
        currentFrequencyValue = ramp(currentFrequencyValue, toward: targetFrequency, dt: deltaTime, timeConstantMs: Self.frequencyRampTimeMs)
        currentVolumeValue = ramp(currentVolumeValue, toward: targetVolume, dt: deltaTime, timeConstantMs: Self.volumeRampTimeMs)
    }
    
    private func ramp(_ current: Double, toward target: Double, dt: Double, timeConstantMs: Double) -> Double {
        guard timeConstantMs > 0 else {
            return target
        }
        
        let alpha = min(1, dt / (timeConstantMs / 1000))
        return current + (target - current) * alpha
    }
    
    private func renderSineWave(frameCount: AVAudioFrameCount, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        
        guard
            let buffer = buffers.first,
            let pointer = buffer.mData?.bindMemory(to: Float.self, capacity: Int(frameCount))
        else {
            return noErr
        }
        
        let vibratoIncrement = 2 * .pi * Self.vibratoFrequency / Self.sampleRate
        
        for frame in 0..<Int(frameCount) {
            let vibratoModulation = sin(vibratoPhase) * Self.vibratoDepth
            let modulatedFrequency = currentFrequencyValue * (1 + vibratoModulation)
            
            phaseIncrement = 2 * .pi * modulatedFrequency / Self.sampleRate
            pointer[frame] = Float(sin(phase) * currentVolumeValue * 0.25)
            phase += phaseIncrement
            vibratoPhase += vibratoIncrement
            
            if phase >= 2 * .pi {
                phase -= 2 * .pi
            }
            if vibratoPhase >= 2 * .pi {
                vibratoPhase -= 2 * .pi
            }
        }
        
        return noErr
    }
}
