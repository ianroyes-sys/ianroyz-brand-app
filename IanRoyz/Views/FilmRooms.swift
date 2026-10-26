import SwiftUI

// MARK: - MOTION · the film grid
struct MotionView: View {
    @State private var playing: Film?
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 26) {
                RoomHeader(kicker: "The Films", title: "MOTION",
                           subtitle: "moving pictures, not posts.")
                    .padding(.top, 12)

                LazyVGrid(columns: cols, spacing: 18) {
                    ForEach(Archive.films) { film in
                        Button { playing = film } label: {
                            FilmCell(film: film)
                        }
                        .buttonStyle(.plain)
                        .reveal()
                    }
                }

                Kicker(text: "more on instagram · @notsoian", color: .white.opacity(0.4), size: 9)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 18)
        }
        .background(Ink.night)
        .roomBack()
        .filmPlayer($playing)
    }
}

struct FilmCell: View {
    let film: Film
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                Photo(name: film.poster)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.1)))
                    .overlay(
                        Image(systemName: "play.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .padding(13)
                            .background(.black.opacity(0.45), in: Circle())
                    )
                RuntimeChip(seconds: film.seconds)
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(film.title)
                    .font(.display(17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 6) {
                    Text(film.subtitle).font(.displayItal(11)).foregroundStyle(Ink.mist)
                    Spacer()
                    Text(film.date).font(.mono(9)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - SATURDAYS · the season
struct SaturdaysView: View {
    @State private var playing: Film?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    RoomHeader(kicker: "The Series · Season One", title: "SATURDAYS",
                               subtitle: "a show about the day nothing is due.")
                }
                .padding(.top, 12)

                // Trailer
                Button { playing = Film(id: Archive.trailer.id, title: "SATURDAYS · TRAILER", subtitle: "", date: Archive.trailer.date, seconds: Archive.trailer.seconds) } label: {
                    ZStack(alignment: .bottomLeading) {
                        Photo(name: Archive.trailer.poster)
                            .frame(height: 200)
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Kicker(text: "Watch the trailer", color: Ink.gold, size: 9)
                                Text("SATURDAYS — S1")
                                    .font(.display(24)).foregroundStyle(.white)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Ink.gold)
                        }
                        .padding(18)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Ink.gold.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .reveal()

                VStack(spacing: 20) {
                    ForEach(Archive.episodes) { ep in
                        Button { playing = Film(id: ep.id, title: "SATURDAYS · \(ep.code)", subtitle: "", date: ep.date, seconds: ep.seconds) } label: {
                            EpisodeRow(episode: ep)
                        }
                        .buttonStyle(.plain)
                        .reveal()
                    }
                }

                Kicker(text: "new episodes when saturday decides", color: .white.opacity(0.4), size: 9)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 18)
        }
        .background(Ink.night)
        .roomBack()
        .filmPlayer($playing)
    }
}

struct EpisodeRow: View {
    let episode: Episode
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Photo(name: episode.poster).frame(height: 190)
                HStack {
                    Text(episode.code)
                        .font(.mono(11, .heavy)).tracking(2)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(episode.special ? Color.white : Ink.gold)
                        .clipShape(Capsule())
                    Spacer()
                    RuntimeChip(seconds: episode.seconds)
                }
                .padding(12)
            }
            .frame(height: 190)

            HStack(alignment: .firstTextBaseline) {
                Text(episode.title)
                    .font(.display(21))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(episode.date).font(.mono(10)).foregroundStyle(Ink.gold)
            }
            .padding(16)
            .background(Ink.charcoal)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.1)))
    }
}

// MARK: - LOST FILES · the vault
struct LostFilesView: View {
    @State private var playing: Film?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    RoomHeader(kicker: "The Vault · Recovered 05.23.26", title: "LOST FILES",
                               subtitle: "some things aren't unfinished — they're just early.")
                    HStack {
                        Text("VOL.1")
                            .font(.mono(12, .heavy)).tracking(4)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Ink.gold)
                        Rectangle().fill(Ink.gold.opacity(0.35)).frame(height: 1)
                    }
                }
                .padding(.top, 12)

                VStack(spacing: 14) {
                    ForEach(Archive.lostFiles) { file in
                        Button { playing = file } label: {
                            LostFileRow(file: file)
                        }
                        .buttonStyle(.plain)
                        .reveal()
                    }
                }

                Kicker(text: "vol.2 still in the drive", color: .white.opacity(0.4), size: 9)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 18)
        }
        .background(Ink.night)
        .roomBack()
        .filmPlayer($playing)
    }
}

struct LostFileRow: View {
    let file: Film
    var body: some View {
        HStack(spacing: 14) {
            Photo(name: file.poster)
                .frame(width: 118, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)))
            VStack(alignment: .leading, spacing: 4) {
                Kicker(text: file.subtitle, color: Ink.goldDeep, size: 8)
                Text(file.title)
                    .font(.display(17))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(runtimeString(file.seconds))
                    .font(.mono(9)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Image(systemName: "play.fill")
                .font(.system(size: 13))
                .foregroundStyle(Ink.gold)
                .padding(11)
                .background(.white.opacity(0.06), in: Circle())
        }
        .padding(10)
        .background(Ink.charcoal, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.07)))
    }
}

// MARK: - SHOOTS · the photographs
struct ShootsView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 30) {
                RoomHeader(kicker: "The Photographs", title: "SHOOTS",
                           subtitle: "experiments in light · @royzfilmz")
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                ForEach(Archive.shoots) { shoot in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(shoot.name).font(.display(24)).foregroundStyle(Ink.gold)
                            Spacer()
                            Text(shoot.caption).font(.displayItal(12)).foregroundStyle(Ink.mist)
                        }
                        .padding(.horizontal, 18)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(shoot.images, id: \.self) { img in
                                    Photo(name: img)
                                        .frame(width: 240, height: 320)
                                        .clipShape(RoundedRectangle(cornerRadius: 20))
                                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.1)))
                                }
                            }
                            .padding(.horizontal, 18)
                        }
                    }
                    .reveal()
                }

                Kicker(text: "booked & busy · dm for shoots", color: .white.opacity(0.4), size: 9)
                    .padding(.bottom, 40)
            }
        }
        .background(Ink.night)
        .roomBack()
    }
}
