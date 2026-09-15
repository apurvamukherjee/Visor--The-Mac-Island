import os

enum Log {
    private static let subsystem = "com.apurvamukherjee.notchy"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let battery = Logger(subsystem: subsystem, category: "battery")
    static let nowPlaying = Logger(subsystem: subsystem, category: "nowPlaying")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
}
