import Foundation
import IOKit.ps

/// Manages and monitors battery status changes on the device
/// - Note: This class uses the IOKit framework to monitor battery status
class BatteryActivityManager {

    static let shared = BatteryActivityManager()

    private var batterySource: CFRunLoopSource?
    private var previousBatteryInfo: BatteryInfo?
    private var notificationQueue: [BatteryEvent] = []
    private var isProcessingNotifications = false

    enum BatteryEvent {
        case powerSourceChanged(isPluggedIn: Bool)
        case batteryLevelChanged(level: Float)
        case lowPowerModeChanged(isEnabled: Bool)
        case isChargingChanged(isCharging: Bool)
        case timeToFullChargeChanged(time: Int)
        case maxCapacityChanged(capacity: Float)
        case error(description: String)
    }

    private let defaultBatteryInfo = BatteryInfo(
        isPluggedIn: false,
        isCharging: false,
        currentCapacity: 0,
        maxCapacity: 0,
        isInLowPowerMode: false,
        timeToFullCharge: 0
    )

    private init() {
        startMonitoring()
        setupLowPowerModeObserver()
    }
    
    /// Setup observer for low power mode changes
    private func setupLowPowerModeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lowPowerModeChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    /// Called when low power mode is enabled or disabled
    @objc private func lowPowerModeChanged() {
        notifyBatteryChanges()
    }
    
    /// Starts monitoring battery changes
    private func startMonitoring() {
        guard let powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let manager = Unmanaged<BatteryActivityManager>.fromOpaque(context).takeUnretainedValue()
            manager.notifyBatteryChanges()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue() else {
            return
        }
        batterySource = powerSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), powerSource, .defaultMode)
    }

    /// Checks for changes in battery status and notifies observers
    private func notifyBatteryChanges() {
        let batteryInfo = getBatteryInfo()
        // Visor: with no previous info every comparison is true, so the first
        // run still sends all six events, in the same order.
        let previous = previousBatteryInfo
        if previous?.isPluggedIn != batteryInfo.isPluggedIn { enqueueNotification(.powerSourceChanged(isPluggedIn: batteryInfo.isPluggedIn)) }
        if previous?.currentCapacity != batteryInfo.currentCapacity { enqueueNotification(.batteryLevelChanged(level: batteryInfo.currentCapacity)) }
        if previous?.isCharging != batteryInfo.isCharging { enqueueNotification(.isChargingChanged(isCharging: batteryInfo.isCharging)) }
        if previous?.isInLowPowerMode != batteryInfo.isInLowPowerMode { enqueueNotification(.lowPowerModeChanged(isEnabled: batteryInfo.isInLowPowerMode)) }
        if previous?.timeToFullCharge != batteryInfo.timeToFullCharge { enqueueNotification(.timeToFullChargeChanged(time: batteryInfo.timeToFullCharge)) }
        if previous?.maxCapacity != batteryInfo.maxCapacity { enqueueNotification(.maxCapacityChanged(capacity: batteryInfo.maxCapacity)) }
        previousBatteryInfo = batteryInfo
    }

    /// Enqueues a notification to be processed
    /// - Parameter event: The battery event
    private func enqueueNotification(_ event: BatteryEvent) {
        notificationQueue.append(event)
        processNextNotification()
    }
    
    /// Processes the next notification in the queue
    /// If there are no more notifications, the queue is cleared
    /// and the processing flag is set to false
    private func processNextNotification() {
        guard !isProcessingNotifications, !notificationQueue.isEmpty else { return }
        isProcessingNotifications = true
        
        let event = notificationQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.notifyObserver(event: event)
            self.isProcessingNotifications = false
            
            // Check if there are more items in the queue
            if !self.notificationQueue.isEmpty {
                self.processNextNotification()
            }
        }
    }
    
    /// Initializes the battery information when the manager starts
    /// - Returns: Current battery information
    func initializeBatteryInfo() -> BatteryInfo {
        let info = getBatteryInfo()
        previousBatteryInfo = info
        return info
    }

    /// Get the current battery information
    /// - Returns: The current battery information
    private func getBatteryInfo() -> BatteryInfo {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let source = (IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef])?.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
              let currentCapacity = description[kIOPSCurrentCapacityKey] as? Float,
              let maxCapacity = description[kIOPSMaxCapacityKey] as? Float,
              let isCharging = description["Is Charging"] as? Bool,
              let powerSource = description[kIOPSPowerSourceStateKey] as? String
        else {
            // Visor: no battery, or one missing a required key. The typed
            // errors thrown and caught here only picked which line to print.
            return defaultBatteryInfo
        }
        return BatteryInfo(
            isPluggedIn: powerSource == kIOPSACPowerValue,
            isCharging: isCharging,
            currentCapacity: currentCapacity,
            maxCapacity: maxCapacity,
            isInLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            timeToFullCharge: description[kIOPSTimeToFullChargeKey] as? Int ?? 0
        )
    }
    
    // Visor: BatteryStatusViewModel is the only observer, and both are
    // singletons, so one callback replaces the add/remove registry.
    var onEvent: ((BatteryEvent) -> Void)?

    private func notifyObserver(event: BatteryEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}

/// Struct to hold battery information
struct BatteryInfo {
    var isPluggedIn: Bool
    var isCharging: Bool
    var currentCapacity: Float
    var maxCapacity: Float
    var isInLowPowerMode: Bool
    var timeToFullCharge: Int
}
