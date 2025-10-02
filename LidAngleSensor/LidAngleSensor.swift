import Foundation
import os.log

final class LidAngleSensor {
    private var hidDevice: IOHIDDevice?
    private let log = Logger(subsystem: "com.gold.samhenri.LidAngleSensor", category: "Sensor")
    
    var isAvailable: Bool {
        hidDevice != nil
    }
    
    init?() {
        guard let device = Self.findLidAngleSensor() else {
            return nil
        }
        
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard openResult == kIOReturnSuccess else {
            LogHelper.logOpenFailure(openResult, logger: log)
            return nil
        }
        
        hidDevice = device
        log.debug("Successfully initialized lid angle sensor")
    }
    
    deinit {
        stopLidAngleUpdates()
    }
    
    func lidAngle() -> Double {
        guard let device = hidDevice else {
            return -2
        }
        
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        
        let result = report.withUnsafeMutableBytes { buffer -> IOReturn in
            guard let baseAddress = buffer.baseAddress else {
                return kIOReturnError
            }
            
            let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(1), pointer, &length)
        }
        
        guard result == kIOReturnSuccess, length >= 3 else {
            log.error("Failed to read lid angle report: \(result)")
            return -2
        }
        
        let rawLow = UInt16(report[1])
        let rawHigh = UInt16(report[2]) << 8
        let rawValue = rawHigh | rawLow
        
        return Double(rawValue)
    }
    
    func startLidAngleUpdates() {
        guard hidDevice == nil else {
            return
        }
        
        guard let device = Self.findLidAngleSensor() else {
            log.error("Lid angle sensor unavailable when attempting to start updates")
            return
        }
        
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        
        if openResult != kIOReturnSuccess {
            LogHelper.logOpenFailure(openResult, logger: log)
            return
        }
        
        hidDevice = device
    }
    
    func stopLidAngleUpdates() {
        guard let device = hidDevice else {
            return
        }
        
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        hidDevice = nil
    }
    
    private static func findLidAngleSensor() -> IOHIDDevice? {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDProductIDKey as String: 0x8104,
            kIOHIDDeviceUsagePageKey as String: 0x0020,
            kIOHIDDeviceUsageKey as String: 0x008A,
        ]
        
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        
        guard openResult == kIOReturnSuccess else {
            return nil
        }
        
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        
        guard
            let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
            !deviceSet.isEmpty
        else {
            return nil
        }
        
        for device in deviceSet {
            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            
            guard openResult == kIOReturnSuccess else {
                continue
            }
            
            var report = [UInt8](repeating: 0, count: 8)
            var length = CFIndex(report.count)
            
            let result = report.withUnsafeMutableBytes { buffer -> IOReturn in
                guard let baseAddress = buffer.baseAddress else {
                    return kIOReturnError
                }
                
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(1), pointer, &length)
            }
            
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            
            if result == kIOReturnSuccess, length >= 3 {
                return device
            }
        }
        
        return nil
    }
    
    private enum LogHelper {
        static func logOpenFailure(_ code: IOReturn, logger: Logger) {
            logger.error("Failed to open lid angle sensor device: \(code)")
        }
    }
}
