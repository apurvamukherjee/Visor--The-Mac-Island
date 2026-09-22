import Foundation

extension Duration {
    /// `mm:ss`, widening to `h:mm:ss` once past the hour.
    ///
    /// The island's only clock format. Three features drew it by hand — the
    /// scrub bar, the countdown and the recording's elapsed time — which is
    /// three copies of the same `%02d:%02d` and three chances for one of
    /// them to pad differently from the others.
    ///
    /// Rounding stays with the caller, because each one rounds for its own
    /// reason: a countdown rounds *up* so a 5m timer opens on "05:00", a
    /// scrub bar rounds to nearest, elapsed time truncates. This is handed
    /// whole seconds and rounds no further.
    var clockText: String {
        self >= .seconds(3600)
            ? formatted(.time(pattern: .hourMinuteSecond(padHourToLength: 1, roundFractionalSeconds: .towardZero)))
            : formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2, roundFractionalSeconds: .towardZero)))
    }
}
