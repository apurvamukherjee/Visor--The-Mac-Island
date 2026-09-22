import CoreGraphics
import Foundation

struct Greeting: Equatable {
    let message: String
    let symbolName: String
    /// How wide the compact wing has to be for `message` to be readable
    /// rather than half-swallowed by the camera housing. Taken once, here,
    /// because the layout that needs it is read on every animation frame.
    let labelWidth: CGFloat

    init(message: String, symbolName: String) {
        self.message = message
        self.symbolName = symbolName
        labelWidth = CompactLabel.width(message)
    }
}

enum GreetingBuilder {
    /// Boundaries match the Calendar app's own "morning/afternoon/evening"
    /// split (5/12/17), plus a "night" tier below 5am for anyone still up.
    static func greeting(for date: Date, name: String, calendar: Calendar = .current) -> Greeting {
        let hour = calendar.component(.hour, from: date)
        return switch hour {
        case 5 ..< 12: Greeting(message: "Good morning, \(name)", symbolName: "sun.max.fill")
        case 12 ..< 17: Greeting(message: "Good afternoon, \(name)", symbolName: "sun.min.fill")
        case 17 ..< 21: Greeting(message: "Good evening, \(name)", symbolName: "sunset.fill")
        default: Greeting(message: "Still up, \(name)?", symbolName: "moon.stars.fill")
        }
    }
}
