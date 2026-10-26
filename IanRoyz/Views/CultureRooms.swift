import SwiftUI

// MARK: - IN ROTATION · the head
struct RotationView: View {
    @ObservedObject private var live = Live.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                RoomHeader(kicker: "The Head · July '26", title: "IN ROTATION",
                           subtitle: "what's steering the eye this month.")
                    .padding(.top, 12)

                ForEach(Archive.influences) { inf in
                    InfluenceCard(influence: inf).reveal()
                }

                Button {
                    if let url = URL(string: Archive.letterboxdURL) { openURL(url) }
                } label: {
                    HStack {
                        Text("FULL WATCHLIST ON LETTERBOXD").font(.mono(10, .bold)).tracking(2)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Ink.gold, in: Capsule())
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 18)
        }
        .background(Ink.night)
        .roomBack()
    }
}

struct InfluenceCard: View {
    let influence: Influence
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = influence.image {
                Photo(name: img).frame(height: 250)
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                // the color card
                Ink.gold.frame(height: 250)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(influence.kind)
                    .font(.mono(10, .heavy)).tracking(3)
                    .foregroundStyle(influence.image == nil ? .black : Ink.gold)
                Text(influence.name)
                    .font(.display(32))
                    .foregroundStyle(influence.image == nil ? .black : .white)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(influence.detail)
                    .font(.mono(10)).tracking(1)
                    .foregroundStyle(influence.image == nil ? .black.opacity(0.6) : .white.opacity(0.65))
                Text(influence.note)
                    .font(.displayItal(13))
                    .foregroundStyle(influence.image == nil ? .black.opacity(0.8) : Ink.mist)
                    .padding(.top, 3)
            }
            .padding(20)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.1)))
    }
}
