import os

enum Log {
    private static let subsystem = "com.apurvamukherjee.visor"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let battery = Logger(subsystem: subsystem, category: "battery")
    static let nowPlaying = Logger(subsystem: subsystem, category: "nowPlaying")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let screenshot = Logger(subsystem: subsystem, category: "screenshot")
    static let greeting = Logger(subsystem: subsystem, category: "greeting")
    static let volume = Logger(subsystem: subsystem, category: "volume")
    static let deviceBattery = Logger(subsystem: subsystem, category: "deviceBattery")
    static let download = Logger(subsystem: subsystem, category: "download")
    static let airDrop = Logger(subsystem: subsystem, category: "airDrop")
    static let lockScreen = Logger(subsystem: subsystem, category: "lockScreen")
    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    static let focus = Logger(subsystem: subsystem, category: "focus")
    static let screenRecording = Logger(subsystem: subsystem, category: "screenRecording")
    static let aiUsage = Logger(subsystem: subsystem, category: "aiUsage")
}
