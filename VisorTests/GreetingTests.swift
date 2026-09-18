import Foundation
import Testing
@testable import Visor

struct GreetingTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(hour: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: hour)))
    }

    @Test
    func morningBoundary() throws {
        #expect(try GreetingBuilder.greeting(for: date(hour: 4), name: "A", calendar: calendar)
            .symbolName == "moon.stars.fill")
        #expect(try GreetingBuilder.greeting(for: date(hour: 5), name: "A", calendar: calendar)
            .symbolName == "sun.max.fill")
    }

    @Test
    func afternoonBoundary() throws {
        #expect(try GreetingBuilder.greeting(for: date(hour: 11), name: "A", calendar: calendar)
            .symbolName == "sun.max.fill")
        #expect(try GreetingBuilder.greeting(for: date(hour: 12), name: "A", calendar: calendar)
            .symbolName == "sun.min.fill")
    }

    @Test
    func eveningBoundary() throws {
        #expect(try GreetingBuilder.greeting(for: date(hour: 16), name: "A", calendar: calendar)
            .symbolName == "sun.min.fill")
        #expect(try GreetingBuilder.greeting(for: date(hour: 17), name: "A", calendar: calendar)
            .symbolName == "sunset.fill")
    }

    @Test
    func nightBoundary() throws {
        #expect(try GreetingBuilder.greeting(for: date(hour: 20), name: "A", calendar: calendar)
            .symbolName == "sunset.fill")
        #expect(try GreetingBuilder.greeting(for: date(hour: 21), name: "A", calendar: calendar)
            .symbolName == "moon.stars.fill")
    }

    @Test
    func messageIncludesTheGivenName() throws {
        #expect(try GreetingBuilder.greeting(for: date(hour: 8), name: "Apurva", calendar: calendar)
            .message == "Good morning, Apurva")
    }
}
