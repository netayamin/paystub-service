import SwiftUI

/// Black canvas + scrolling feature cards that explain Snag (live drops, urgency, predictions).
struct LoginAnimatedSpotsHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tilesLeft: [SpotTile] = [
        SpotTile(id: "l0", name: "Carbone", imageH: 72, u: "https://images.unsplash.com/photo-1544148103-0771bfbc50ab?w=400&q=80&auto=format&fit=crop", kind: .liveDrop, time: "9:15 PM", goneMins: 6, prediction: "Open seats now", badge: "LIVE"),
        SpotTile(id: "l1", name: "Don Angie", imageH: 86, u: "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=400&q=80&auto=format&fit=crop", kind: .likelyOpen, time: "Tonight", goneMins: 14, prediction: "87% likely", badge: "HINT"),
        SpotTile(id: "l2", name: "Lilia", imageH: 68, u: "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=400&q=80&auto=format&fit=crop", kind: .liveDrop, time: "8:30 PM", goneMins: 9, prediction: "Table spotted", badge: "NEW"),
        SpotTile(id: "l3", name: "Via Carota", imageH: 80, u: "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400&q=80&auto=format&fit=crop", kind: .ranked, time: "Peak hype", goneMins: 11, prediction: "Top of feed", badge: "HYPE"),
    ]
    private static let tilesMid: [SpotTile] = [
        SpotTile(id: "m0", name: "Atomix", imageH: 82, u: "https://images.unsplash.com/photo-1559339352-11d0350bfa78?w=400&q=80&auto=format&fit=crop", kind: .liveDrop, time: "10:00 PM", goneMins: 5, prediction: "Rare 2-top", badge: "LIVE"),
        SpotTile(id: "m1", name: "Tatiana", imageH: 74, u: "https://images.unsplash.com/photo-1600891964092-4313c288038e?w=400&q=80&auto=format&fit=crop", kind: .likelyOpen, time: "Tomorrow", goneMins: 18, prediction: "91% pattern", badge: "AI"),
        SpotTile(id: "m2", name: "4 Charles", imageH: 88, u: "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400&q=80&auto=format&fit=crop", kind: .liveDrop, time: "7:45 PM", goneMins: 7, prediction: "Gone fast", badge: "HOT"),
        SpotTile(id: "m3", name: "I Sodi", imageH: 70, u: "https://images.unsplash.com/photo-1590846406792-0adc7f938f1d?w=400&q=80&auto=format&fit=crop", kind: .alert, time: "Push on", goneMins: 12, prediction: "We’ll ping you", badge: "ALERT"),
    ]
    private static let tilesRight: [SpotTile] = [
        SpotTile(id: "r0", name: "Minetta", imageH: 76, u: "https://images.unsplash.com/photo-1498654896293-37aacfe11379?w=400&q=80&auto=format&fit=crop", kind: .liveDrop, time: "6:00 PM", goneMins: 8, prediction: "Classic room", badge: "LIVE"),
        SpotTile(id: "r1", name: "Monkey Bar", imageH: 90, u: "https://images.unsplash.com/photo-1552566626-52f8b828add9?w=400&q=80&auto=format&fit=crop", kind: .ranked, time: "Late night", goneMins: 15, prediction: "Ranked feed", badge: "TOP"),
        SpotTile(id: "r2", name: "Raoul’s", imageH: 72, u: "https://images.unsplash.com/photo-1550966873-1d4e9d24b65a?w=400&q=80&auto=format&fit=crop", kind: .likelyOpen, time: "Fri dinner", goneMins: 22, prediction: "76% open", badge: "PREDICT"),
        SpotTile(id: "r3", name: "Berenjak", imageH: 84, u: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=80&auto=format&fit=crop", kind: .liveDrop, time: "8:00 PM", goneMins: 4, prediction: "Just scanned", badge: "NOW"),
    ]

    var body: some View {
        GeometryReader { geo in
            let gutter: CGFloat = 7
            let sidePad: CGFloat = 12
            let colW = max(92, (geo.size.width - sidePad * 2 - gutter * 2) / 3)
            let colH = max(200, geo.size.height - 56)

            ZStack(alignment: .top) {
                Color.black

                HStack(alignment: .top, spacing: gutter) {
                    spotColumn(tiles: Self.tilesLeft, width: colW, columnHeight: colH, speed: 24, up: true)
                    spotColumn(tiles: Self.tilesMid, width: colW, columnHeight: colH, speed: 32, up: false)
                    spotColumn(tiles: Self.tilesRight, width: colW, columnHeight: colH, speed: 27, up: true)
                }
                .padding(.horizontal, sidePad)
                .padding(.top, 50)

                VStack(spacing: 0) {
                    brandRow
                        .padding(.top, 12)
                    Spacer()
                    fadeToSheet
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)
            }
        }
    }

    private var brandRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(SnagDesignSystem.exploreCoralSolid)
            Text("SNAG")
                .font(.system(size: 13, weight: .black))
                .tracking(1.2)
                .foregroundColor(.white)
            Text("·")
                .foregroundColor(.white.opacity(0.35))
            Text("LIVE DROPS")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(.white.opacity(0.85))
                .tracking(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: 6, height: 6)
                Text("SCANNING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .tracking(0.5)
            }
        }
        .padding(.horizontal, 16)
    }

    private var fadeToSheet: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color.black.opacity(0.5),
                Color.black.opacity(0.85),
                Color.white.opacity(0.08),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 88)
    }

    private func spotColumn(tiles: [SpotTile], width: CGFloat, columnHeight: CGFloat, speed: CGFloat, up: Bool) -> some View {
        let cycle = SpotColumnCycleHeight.compute(tiles: tiles, spacing: 9)
        return SpotScrollingColumn(
            tiles: tiles,
            width: width,
            columnHeight: columnHeight,
            cycleHeight: cycle,
            pixelsPerSecond: speed,
            upward: up,
            paused: reduceMotion
        )
    }
}

// MARK: - Tile

private enum SpotKind {
    case liveDrop, likelyOpen, ranked, alert
}

private struct SpotTile: Identifiable {
    let id: String
    let name: String
    let imageHeight: CGFloat
    let imageURL: URL?
    let kind: SpotKind
    let time: String
    let goneMins: Int
    let prediction: String
    let badge: String

    init(id: String, name: String, imageH: CGFloat, u: String, kind: SpotKind, time: String, goneMins: Int, prediction: String, badge: String) {
        self.id = id
        self.name = name
        self.imageHeight = imageH
        self.imageURL = URL(string: u)
        self.kind = kind
        self.time = time
        self.goneMins = goneMins
        self.prediction = prediction
        self.badge = badge
    }

    var bodyHeight: CGFloat { 78 }
    var totalCardHeight: CGFloat { imageHeight + bodyHeight }
}

private enum SpotColumnCycleHeight {
    static func compute(tiles: [SpotTile], spacing: CGFloat) -> CGFloat {
        guard !tiles.isEmpty else { return 1 }
        let sum = tiles.reduce(0) { $0 + $1.totalCardHeight }
        return sum + CGFloat(max(0, tiles.count - 1)) * spacing
    }
}

// MARK: - Column

private struct SpotScrollingColumn: View {
    let tiles: [SpotTile]
    let width: CGFloat
    let columnHeight: CGFloat
    let cycleHeight: CGFloat
    let pixelsPerSecond: CGFloat
    let upward: Bool
    let paused: Bool

    private let spacing: CGFloat = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let raw = CGFloat(t) * pixelsPerSecond
            let mod = raw.truncatingRemainder(dividingBy: max(cycleHeight, 1))
            let offset: CGFloat = upward ? -mod : mod

            VStack(spacing: spacing) {
                // One ForEach with flat indices so identities are never duplicated across the two
                // duplicated strips (nested ForEach + id: \.offset reused 0..<n twice → reuse bugs).
                ForEach(0..<(2 * tiles.count), id: \.self) { i in
                    let tile = tiles[i % tiles.count]
                    LoginSpotFeatureCard(tile: tile, width: width, tick: context.date)
                }
            }
            .offset(y: offset)
            .frame(width: width, alignment: .top)
        }
        .frame(width: width, height: columnHeight)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.15), location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .black.opacity(0.12), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Card

private struct LoginSpotFeatureCard: View {
    let tile: SpotTile
    let width: CGFloat
    let tick: Date

    private var countdownMins: Int {
        let base = tile.goneMins
        let pulse = Int(tick.timeIntervalSinceReferenceDate) % 4
        return max(2, base - 1 + pulse % 3)
    }

    private var badgeColor: Color {
        switch tile.kind {
        case .liveDrop: return SnagDesignSystem.exploreCoralSolid
        case .likelyOpen: return Color(red: 0.45, green: 0.78, blue: 0.95)
        case .ranked: return Color(red: 0.85, green: 0.65, blue: 0.2)
        case .alert: return Color(red: 0.6, green: 0.5, blue: 1)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                CardAsyncImage(url: tile.imageURL, contentMode: .fill, skeletonTone: .darkCard) {
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .frame(width: width, height: tile.imageHeight)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(width: width, height: tile.imageHeight)
                .allowsHitTesting(false)

                Text(tile.badge)
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.6)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(badgeColor.opacity(0.92)))
                    .padding(7)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tile.name.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.45))
                    Text(tile.time)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                }

                HStack(spacing: 5) {
                    Image(systemName: "timer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                    Text("Often gone in ~\(countdownMins)m")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(SnagDesignSystem.exploreCoralSolid)
                }

                Text(tile.prediction.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.4)
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.07, green: 0.07, blue: 0.07))
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: SnagDesignSystem.exploreCoralSolid.opacity(0.12), radius: 8, x: 0, y: 4)
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LoginAnimatedSpotsHero()
            .frame(height: 420)
    }
}
