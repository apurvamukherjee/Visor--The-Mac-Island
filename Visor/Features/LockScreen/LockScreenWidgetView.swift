import SwiftUI

/// The card under the notch on a locked screen.
///
/// Calendar and music stay separate here, which is the whole point of the
/// feature: when something is playing the card is the player, and when
/// nothing is it is the clock and the day's agenda. They never share the
/// card, and neither ever collapses into a row of the other.
struct LockScreenWidgetView: View {
    var store: NotchStore

    private var showsNowPlaying: Bool {
        LockScreenSettings.showsNowPlaying && store.nowPlaying != nil
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Motion.flags
                        .reduceTransparency ? AnyShapeStyle(.black.opacity(0.9)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }
            }
            .padding(.horizontal, 10)
            .transition(.island)
            .animation(Motion.resolved(Motion.layout), value: showsNowPlaying)
    }

    @ViewBuilder
    private var content: some View {
        if showsNowPlaying, let info = store.nowPlaying {
            LockScreenNowPlayingView(
                info: info,
                artwork: store.nowPlayingArtwork,
                tint: store.nowPlayingTint,
                progress: store.nowPlayingProgress
            )
        } else {
            LockScreenIdleView(
                showsClock: LockScreenSettings.showsClock,
                events: store.calendarEvents
            )
        }
    }
}

/// Clock over the day's next events. `TimelineView` on the minute, so the
/// clock is correct without anything ticking — the same anchor pattern the
/// countdown and the recording clock use.
private struct LockScreenIdleView: View {
    let showsClock: Bool
    let events: [CalendarEvent]

    private var upcoming: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsClock {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
            }

            if upcoming.isEmpty {
                Text("Nothing left today")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(alignment: .leading, spacing: IslandSpacing.row) {
                    ForEach(upcoming) { event in
                        EventRow(event: event)
                    }
                }
            }
        }
    }
}
