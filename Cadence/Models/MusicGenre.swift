import Foundation

/// A genre Discover can browse, with Apple's ID for it, which its charts are filtered by.
nonisolated struct MusicGenre: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let systemImage: String

    /// Apple's main genres, each with a chart of its own in most countries.
    static let all: [MusicGenre] = [
        MusicGenre(id: 14, name: String(localized: "Pop"), systemImage: "star.fill"),
        MusicGenre(id: 18, name: String(localized: "Hip-Hop/Rap"), systemImage: "mic.fill"),
        MusicGenre(id: 21, name: String(localized: "Rock"), systemImage: "guitars.fill"),
        MusicGenre(id: 20, name: String(localized: "Alternative"), systemImage: "waveform"),
        MusicGenre(id: 17, name: String(localized: "Dance"), systemImage: "figure.dance"),
        MusicGenre(id: 7, name: String(localized: "Electronic"), systemImage: "headphones"),
        MusicGenre(id: 15, name: String(localized: "R&B/Soul"), systemImage: "heart.fill"),
        MusicGenre(id: 6, name: String(localized: "Country"), systemImage: "sun.horizon.fill"),
        MusicGenre(id: 12, name: String(localized: "Latin"), systemImage: "flame.fill"),
        MusicGenre(id: 51, name: String(localized: "K-Pop"), systemImage: "sparkles"),
        MusicGenre(id: 27, name: String(localized: "J-Pop"), systemImage: "star.circle.fill"),
        MusicGenre(id: 1153, name: String(localized: "Metal"), systemImage: "bolt.fill"),
        MusicGenre(id: 11, name: String(localized: "Jazz"), systemImage: "music.quarternote.3"),
        MusicGenre(id: 5, name: String(localized: "Classical"), systemImage: "pianokeys"),
        MusicGenre(id: 10, name: String(localized: "Singer/Songwriter"), systemImage: "pencil.line"),
        MusicGenre(id: 16, name: String(localized: "Soundtrack"), systemImage: "film.fill"),
        MusicGenre(id: 24, name: String(localized: "Reggae"), systemImage: "leaf.fill"),
        MusicGenre(id: 2, name: String(localized: "Blues"), systemImage: "music.note"),
        MusicGenre(id: 1289, name: String(localized: "Folk"), systemImage: "tree.fill"),
        MusicGenre(id: 19, name: String(localized: "World"), systemImage: "globe.americas.fill"),
        MusicGenre(id: 22, name: String(localized: "Christian & Gospel"), systemImage: "hands.sparkles.fill"),
        MusicGenre(id: 4, name: String(localized: "Children's Music"), systemImage: "teddybear.fill"),
    ]

    /// The browsable genre for one of Apple's more specific genre names, such as "Hard Rock"
    /// (Rock) or "Indie Pop" (Alternative). Nil when none fits.
    static func matching(catalogGenre name: String) -> MusicGenre? {
        let name = name.lowercased()
        guard let id = catalogKeywords.first(where: { _, keywords in
            keywords.contains { name.contains($0) }
        })?.id else { return nil }
        return all.first { $0.id == id }
    }

    /// Words in Apple's genre names, checked in this order so that "K-Pop" isn't taken for Pop
    /// or "Pop/Rock" for Pop.
    private static let catalogKeywords: [(id: Int, keywords: [String])] = [
        (51, ["k-pop"]),
        (27, ["j-pop", "j-rock", "anime"]),
        (18, ["hip-hop", "hip hop", "rap"]),
        (15, ["r&b", "soul", "funk"]),
        (1153, ["metal"]),
        (20, ["alternative", "indie", "punk", "grunge", "emo"]),
        (21, ["rock"]),
        (7, ["electronic", "house", "techno", "trance", "dubstep", "ambient", "drum"]),
        (17, ["dance", "edm"]),
        (6, ["country", "americana", "bluegrass"]),
        (12, ["latin", "reggaeton", "urbano", "salsa", "bachata"]),
        (11, ["jazz"]),
        (5, ["classical", "opera", "orchestral"]),
        (10, ["singer/songwriter"]),
        (16, ["soundtrack", "score", "musical"]),
        (24, ["reggae", "dancehall"]),
        (2, ["blues"]),
        (1289, ["folk"]),
        (22, ["christian", "gospel", "worship"]),
        (4, ["children"]),
        (19, ["world", "afro"]),
        (14, ["pop"]),
    ]
}
