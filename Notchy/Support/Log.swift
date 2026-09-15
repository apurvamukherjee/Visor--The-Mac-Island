import os

enum Log {
    private static let subsystem = "com.apurvamukherjee.notchy"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let window = Logger(subsystem: subsystem, category: "window")
}
