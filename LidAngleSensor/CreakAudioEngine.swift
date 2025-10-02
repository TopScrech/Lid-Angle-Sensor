import AVFoundation
import QuartzCore
import os.log

final class CreakAudioEngine: LidAngleAudioEngine {
    private let audioEngine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let varispeedUnit: AVAudioUnitVarispeed
    private let mixerNode: AVAudioMixerNode
    private var creakFile: AVAudioFile?
    private var preparedBuffer: AVAudioPCMBuffer?
    
    private var lastLidAngle = 0.0
    private var smoothedLidAngle = 0.0
    private var lastUpdateTime = CACurrentMediaTime()
    private var smoothedVelocity = 0.0
    private var targetGain = 0.0
    private var targetRate = 1.0
    private var currentGainValue = 0.0
    private var currentRateValue = 1.0
    private var isFirstUpdate = true
    private var lastMovementTime = CACurrentMediaTime()
    private var lastRampTime: Double?
    private let log = Logger(subsystem: "com.gold.samhenri.LidAngleSensor", category: "CreakAudio")
    
    private static let deadzone = 1.0
    private static let velocityFull = 10.0
    private static let velocityQuiet = 100.0
    private static let minRate = 0.8
    private static let maxRate = 1.1
    private static let angleSmoothingFactor = 0.05
    private static let velocitySmoothingFactor = 0.3
    private static let movementThreshold = 0.5
    private static let gainRampTimeMs = 50.0
    private static let rateRampTimeMs = 80.0
    private static let movementTimeoutMs = 50.0
    private static let velocityDecayFactor = 0.5
    private static let additionalDecayFactor = 0.8
    
    init?() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        varispeedUnit = AVAudioUnitVarispeed()
        mixerNode = audioEngine.mainMixerNode
        
        audioEngine.attach(playerNode)
        audioEngine.attach(varispeedUnit)
        
        guard loadAudioFile() else {
            log.error("Failed to load creak audio file")
            return nil
        }
        
        guard connectGraph() else {
            log.error("Failed to connect audio graph")
            return nil
        }
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
        
        return String(format: "Gain: %.2f, Rate: %.2f", currentGainValue, currentRateValue)
    }
    
    @discardableResult
    func start() -> Bool {
        guard !audioEngine.isRunning else {
            return true
        }
        
        do {
            try audioEngine.start()
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription, privacy: .public)")
            return false
        }
        
        startLoop()
        return true
    }
    
    func stop() {
        guard audioEngine.isRunning else {
            return
        }
        
        playerNode.stop()
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
        updateParameters(with: smoothedVelocity)
    }
    
    private func updateParameters(with velocity: Double) {
        let speed = velocity
        let gain: Double
        
        if speed < Self.deadzone {
            gain = 0
        } else {
            let e0 = max(0, Self.velocityFull - 0.5)
            let e1 = Self.velocityQuiet + 0.5
            let t = min(1, max(0, (speed - e0) / (e1 - e0)))
            let smooth = t * t * (3 - 2 * t)
            gain = max(0, min(1, 1 - smooth))
        }
        
        let normalized = min(1, max(0, speed / Self.velocityQuiet))
        let rate = max(Self.minRate, min(Self.maxRate, Self.minRate + normalized * (Self.maxRate - Self.minRate)))
        
        targetGain = gain
        targetRate = rate
        
        rampToTargets()
    }
    
    private func startLoop() {
        guard let creakFile else {
            return
        }
        
        playerNode.stop()
        
        if preparedBuffer == nil {
            let frameCount = AVAudioFrameCount(creakFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: creakFile.processingFormat, frameCapacity: frameCount) else {
                log.error("Failed to allocate PCM buffer")
                return
            }
            
            do {
                try creakFile.read(into: buffer)
            } catch {
                log.error("Failed to read creak loop: \(error.localizedDescription, privacy: .public)")
                return
            }
            
            preparedBuffer = buffer
        }
        
        guard let buffer = preparedBuffer else {
            return
        }
        
        creakFile.framePosition = 0
        playerNode.scheduleBuffer(buffer, at: nil, options: [.loops])
        playerNode.play()
        playerNode.volume = 0
    }
    
    private func rampToTargets() {
        guard audioEngine.isRunning else {
            return
        }
        
        let currentTime = CACurrentMediaTime()
        let deltaTime: Double
        
        if let lastRampTime {
            deltaTime = currentTime - lastRampTime
        } else {
            deltaTime = 0
        }
        
        lastRampTime = currentTime
        
        currentGainValue = ramp(currentGainValue, toward: targetGain, dt: deltaTime, timeConstantMs: Self.gainRampTimeMs)
        currentRateValue = ramp(currentRateValue, toward: targetRate, dt: deltaTime, timeConstantMs: Self.rateRampTimeMs)
        
        playerNode.volume = Float(currentGainValue * 2)
        varispeedUnit.rate = Float(currentRateValue)
    }
    
    private func ramp(_ current: Double, toward target: Double, dt: Double, timeConstantMs: Double) -> Double {
        guard timeConstantMs > 0 else {
            return target
        }
        
        let alpha = min(1, dt / (timeConstantMs / 1000))
        
        return current + (target - current) * alpha
    }
    
    private func loadAudioFile() -> Bool {
        guard let url = Bundle.main.url(forResource: "CREAK_LOOP", withExtension: "wav") else {
            log.error("Missing CREAK_LOOP.wav in bundle")
            return false
        }
        
        do {
            creakFile = try AVAudioFile(forReading: url)
            return true
        } catch {
            log.error("Failed to load CREAK_LOOP.wav: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    private func connectGraph() -> Bool {
        guard let creakFile else {
            return false
        }
        
        let format = creakFile.processingFormat
        audioEngine.connect(playerNode, to: varispeedUnit, format: format)
        audioEngine.connect(varispeedUnit, to: mixerNode, format: format)
        
        return true
    }
}
