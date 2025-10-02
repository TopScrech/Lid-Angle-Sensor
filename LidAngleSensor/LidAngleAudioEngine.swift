protocol LidAngleAudioEngine: AnyObject {
    var isRunning: Bool { get }
    var currentVelocity: Double { get }
    var statusDescription: String { get }
    
    @discardableResult
    func start() -> Bool
    func stop()
    func update(angle: Double)
}
