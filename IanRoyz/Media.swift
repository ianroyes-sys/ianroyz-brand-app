import Foundation

// MARK: - Models

struct Film: Identifiable, Hashable {
    let id: String          // bundle video name, no extension
    let title: String
    let subtitle: String
    let date: String        // display date
    let seconds: Int
    var poster: String { "poster_\(id)" }
}

struct Episode: Identifiable, Hashable {
    let id: String
    let code: String        // "EP.01"
    let title: String
    let date: String
    let seconds: Int
    var special: Bool = false
    var poster: String { "poster_\(id)" }
}

struct Influence: Identifiable, Hashable {
    let id = UUID()
    let kind: String        // "A FILM"
    let name: String
    let detail: String
    let note: String
    let image: String?      // bundle image, or nil for the color card
}

struct Shoot: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let caption: String
    let images: [String]
}

// MARK: - Archive (all content)

enum Archive {

    // MOTION — the film grid
    static let films: [Film] = [
        Film(id: "motion_avengers", title: "THE AVENGERS", subtitle: "wild sh*t", date: "12.04.25", seconds: 70),
        Film(id: "landing_bored",   title: "BORED",        subtitle: "a short about nothing", date: "05.15.24", seconds: 35),
        Film(id: "motion_mani",     title: "MANIFESTO",    subtitle: "usm campaign", date: "03.14.26", seconds: 92),
        Film(id: "motion_illybw",   title: "ONE LAST TIME", subtitle: "illy · b&w", date: "05.05.26", seconds: 18),
        Film(id: "motion_hhn",      title: "HHN",          subtitle: "big night energy", date: "04.03.26", seconds: 37),
    ]

    // SATURDAYS — the series
    static let trailer = Episode(id: "sat_trailer", code: "TRAILER", title: "SATURDAYS", date: "01.19.26", seconds: 18)
    static let episodes: [Episode] = [
        Episode(id: "sat_ep1", code: "EP.01", title: "THE PILOT", date: "02.17.25", seconds: 64),
        Episode(id: "sat_ep4", code: "EP.04", title: "SATURDAYS", date: "03.29.26", seconds: 76),
        Episode(id: "lost_seniors", code: "EP.05", title: "SENIORS", date: "05.24.26", seconds: 32),
        Episode(id: "sat_dirtysouth", code: "SPECIAL", title: "CAN'T KILL THE SOUTH", date: "04.20.26", seconds: 65, special: true),
    ]

    // LOST FILES VOL.1 — recovered 05.23.26
    static let lostFiles: [Film] = [
        Film(id: "lost_big21",   title: "BIG 21",           subtitle: "file 001", date: "05.23.26", seconds: 25),
        Film(id: "lost_power",   title: "I GOT THAT POWER", subtitle: "file 002", date: "05.23.26", seconds: 15),
        Film(id: "lost_lebrons", title: "LEBRON'S HOUSE",   subtitle: "file 003", date: "05.23.26", seconds: 31),
        Film(id: "lost_outside", title: "OUTSIDE",          subtitle: "file 004", date: "05.23.26", seconds: 35),
        Film(id: "lost_iron",    title: "IRON OUTSIDE",     subtitle: "file 005", date: "09.19.25", seconds: 9),
        Film(id: "lost_vp",      title: "VP CANDIDATE",     subtitle: "file 006", date: "05.23.26", seconds: 23),
    ]

    static let spotifyURL = "https://open.spotify.com/user/vvtvi6uxuckphvir480n8ndao"

    // IN ROTATION — the headspace, refresh monthly
    static let influences: [Influence] = [
        Influence(kind: "A FILM", name: "Moonlight", detail: "dir. Barry Jenkins · 2016",
                  note: "Blue light on brown skin. Every frame is a painting I keep stealing from.",
                  image: "still_motion_illybw_1"),
        Influence(kind: "A RECORD", name: "channel ORANGE", detail: "Frank Ocean · 2012",
                  note: "The record that made me want to make things that feel like memory.",
                  image: "still_landing_bored_1"),
        Influence(kind: "A BOOK", name: "The Creative Act", detail: "Rick Rubin · 2023",
                  note: "\"The work reveals itself as you go.\" Reading it slow on purpose.",
                  image: "still_sat_ep4_0"),
        Influence(kind: "A COLOR", name: "Butter Gold", detail: "#EDDE8C",
                  note: "The color of 6:40pm in the South. It's in everything I'm cutting right now.",
                  image: nil),
    ]
    static let letterboxdURL = "https://letterboxd.com/Ianroyes1/"

    // SHOOTS — experimental photo work
    static let shoots: [Shoot] = [
        Shoot(name: "SOFT GIRL", caption: "cherry blossoms · spring '25",
              images: ["shoot_soft_DSC04978", "shoot_soft_DSC04980", "shoot_soft_DSC04984"]),
        Shoot(name: "JOSH CAR", caption: "chrome & horsepower · mar '26",
              images: ["shoot_joshcar_DSC07933", "shoot_joshcar_DSC07949", "shoot_joshcar_DSC07955"]),
        Shoot(name: "USM MEDIA DAY", caption: "game faces · oct '25",
              images: ["shoot_mediaday_DSC04882", "shoot_mediaday_DSC04895", "shoot_mediaday_DSC04899"]),
        Shoot(name: "MONELE", caption: "portrait study · oct '25",
              images: ["shoot_monele_DSC02553", "shoot_monele_DSC02564", "shoot_monele_DSC02598"]),
        Shoot(name: "BIRTHDAY SHOOT", caption: "another year · mar '25",
              images: ["shoot_bday_DSC02849", "shoot_bday_DSC02870", "shoot_bday_DSC02901"]),
        Shoot(name: "CAR WASH", caption: "suds & sun · mar '25",
              images: ["shoot_carwash_DSC02485", "shoot_carwash_DSC02528", "shoot_carwash_DSC02536"]),
        Shoot(name: "CONSTRUCTION", caption: "hard hat season · mar '25",
              images: ["shoot_constr_DSC02102", "shoot_constr_DSC02110", "shoot_constr_DSC02123"]),
        Shoot(name: "DORMUS FOR PRES", caption: "the campaign · apr '25",
              images: ["shoot_dormus_DSC03972", "shoot_dormus_DSC03975", "shoot_dormus_DSC03981"]),
        Shoot(name: "AIRPORT", caption: "departures · aug '25",
              images: ["shoot_airport_DSC00062", "shoot_airport_DSC00082", "shoot_airport_DSC00084"]),
    ]

    // Portraits used around the app. Only the two that a room actually renders
    // are still here — the other four were constants nobody read, holding 2MB of
    // JPEG in the bundle (the originals are in `_unused-images/`).
    static let darkPhoto = "me_DSC06281-2"       // chiaroscuro
    static let goldenPhoto = "me__DSC8464"       // golden hour concrete

    // THE INDEX — links
    static let links: [(String, String, String)] = [
        ("INSTAGRAM", "@notsoian", "https://www.instagram.com/notsoian/"),
        ("PHOTOGRAPHY", "@royzfilmz", "https://www.instagram.com/royzfilmz/"),
        ("SPOTIFY", "what i'm hearing", spotifyURL),
        ("LETTERBOXD", "what i'm watching", letterboxdURL),
    ]
}
