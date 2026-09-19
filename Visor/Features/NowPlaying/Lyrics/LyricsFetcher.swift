import Foundation

enum LyricsResult: Equatable, Sendable {
    case synced(TrackLyrics)
    case plain(String)
    case unavailable
}

/// A free, keyless lookup against LRCLIB — no auth, no app-side rate
/// limiting beyond being a polite client. Called only while the lyrics
/// panel is actually open (see `ExpandedMusicView.loadLyricsIfNeeded`), not
/// on every track change, so playing music never phones out on its own.
enum LyricsFetcher {
    static func fetch(title: String, artist: String?) async -> LyricsResult {
        guard let url = requestURL(title: title, artist: artist) else { return .unavailable }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .unavailable }
            let payload = try JSONDecoder().decode(Response.self, from: data)
            if let synced = payload.syncedLyrics, !synced.isEmpty {
                return .synced(TrackLyrics.parseLRC(synced))
            }
            if let plain = payload.plainLyrics, !plain.isEmpty {
                return .plain(plain)
            }
            return .unavailable
        } catch {
            Log.nowPlaying.error("Lyrics fetch failed: \(error.localizedDescription)")
            return .unavailable
        }
    }

    private static func requestURL(title: String, artist: String?) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [URLQueryItem(name: "track_name", value: title)]
        if let artist {
            items.append(URLQueryItem(name: "artist_name", value: artist))
        }
        components?.queryItems = items
        return components?.url
    }

    private struct Response: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }
}
