import SwiftUI

/// Infinite vertical columns of “popular spot” tiles — login screen backdrop above the form.
struct LoginAnimatedSpotsHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tilesLeft: [SpotTile] = [
        SpotTile(id: "l0", name: "Carbone", rating: 4.9, h: 78, u: "https://images.unsplash.com/photo-1544148103-0771bfbc50ab?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "l1", name: "Don Angie", rating: 4.8, h: 92, u: "https://images.unsplash.com/photo-1414235077428-338989a2e8c0?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "l2", name: "Lilia", rating: 4.8, h: 70, u: "https://images.unsplash.com/photo-1555396273-367ea4eb4db5?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "l3", name: "Via Carota", rating: 4.7, h: 86, u: "https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?w=400&q=80&auto=format&fit=crop"),
    ]
    private static let tilesMid: [SpotTile] = [
        SpotTile(id: "m0", name: "Atomix", rating: 4.9, h: 88, u: "https://images.unsplash.com/photo-1559339352-11d0350bfa78?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "m1", name: "Tatiana", rating: 4.8, h: 74, u: "https://images.unsplash.com/photo-1600891964092-4313c288038e?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "m2", name: "4 Charles", rating: 4.7, h: 90, u: "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "m3", name: "I Sodi", rating: 4.7, h: 72, u: "https://images.unsplash.com/photo-1590846406792-0adc7f938f1d?w=400&q=80&auto=format&fit=crop"),
    ]
    private static let tilesRight: [SpotTile] = [
        SpotTile(id: "r0", name: "Minetta Tavern", rating: 4.7, h: 80, u: "https://images.unsplash.com/photo-1498654896293-37aacfe11379?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "r1", name: "Monkey Bar", rating: 4.6, h: 94, u: "https://images.unsplash.com/photo-1552566626-52f8b828add9?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "r2", name: "Raoul’s", rating: 4.7, h: 76, u: "https://images.unsplash.com/photo-1550966873-1d4e9d24b65a?w=400&q=80&auto=format&fit=crop"),
        SpotTile(id: "r3", name: "Berenjak", rating: 4.8, h: 84, u: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=80&auto=format&fit=crop"),
    ]

    var body: some View {
        GeometryReader { geo in
            let gutter: CGFloat = 8
            let sidePad: CGFloat = 14
            let colW = max(96, (geo.size.width - sidePad * 2 - gutter * 2) / 3)
            let colH = max(220, geo.size.height - 58)

            ZStack(alignment: .top) {
                HStack(alignment: .top, spacing: gutter) {
                    spotColumn(tiles: Self.tilesLeft, width: colW, columnHeight: colH, speed: 26, up: true)
                    spotColumn(tiles: Self.tilesMid, width: colW, columnHeight: colH, speed: 34, up: false)
                    spotColumn(tiles: Self.tilesRight, width: colW, columnHeight: colH, speed: 29, up: true)
                }
                .padding(.horizontal, sidePad)
                .padding(.top, 44)

                VStack(spacing: 0) {
                    livePill
                        .padding(.top, 10)
                    Spacer()
                    bottomFade
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(height: 360)
        .frame(maxWidth: .infinity)
    }

    private var livePill: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [Color.orange, Color.red.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                )
            Text("JUST OPENED")
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.9)
            Text("·")
                .foregroundColor(.white.opacity(0.45))
            Text("POPULAR NOW")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.42))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
        )
    }

    private var bottomFade: some View {
        LinearGradient(
            colors: [
                Color.clear,
                Color(red: 0.24, green: 0.15, blue: 0.11).opacity(0.5),
                Color(red: 0.20, green: 0.12, blue: 0.09).opacity(0.92),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 100)
        .allowsHitTesting(false)
    }

    private func spotColumn(tiles: [SpotTile], width: CGFloat, columnHeight: CGFloat, speed: CGFloat, up: Bool) -> some View {
        let cycle = SpotColumnCycleHeight.compute(tiles: tiles, spacing: 10)
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

// MARK: - Tile model

private struct SpotTile: Identifiable {
    let id: String
    let name: String
    let rating: Double
    let imageHeight: CGFloat
    let imageURL: URL?

    init(id: String, name: String, rating: Double, h: CGFloat, u: String) {
        self.id = id
        self.name = name
        self.rating = rating
        self.imageHeight = h
        self.imageURL = URL(string: u)
    }

    var textBlockHeight: CGFloat { 52 }
    var totalCardHeight: CGFloat { imageHeight + textBlockHeight }
}

private enum SpotColumnCycleHeight {
    static func compute(tiles: [SpotTile], spacing: CGFloat) -> CGFloat {
        guard !tiles.isEmpty else { return 1 }
        let sum = tiles.reduce(0) { $0 + $1.totalCardHeight }
        return sum + CGFloat(max(0, tiles.count - 1)) * spacing
    }
}

// MARK: - Scrolling column

private struct SpotScrollingColumn: View {
    let tiles: [SpotTile]
    let width: CGFloat
    let columnHeight: CGFloat
    let cycleHeight: CGFloat
    let pixelsPerSecond: CGFloat
    let upward: Bool
    let paused: Bool

    private let spacing: CGFloat = 10

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: paused)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let raw = CGFloat(t) * pixelsPerSecond
            let mod = raw.truncatingRemainder(dividingBy: max(cycleHeight, 1))
            let offset: CGFloat = upward ? -mod : mod

            VStack(spacing: spacing) {
                ForEach(0..<2, id: \.self) { copy in
                    ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                        LoginSpotMiniCard(tile: tile, width: width)
                            .id("\(copy)-\(index)-\(tile.id)")
                    }
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
                    .init(color: .black.opacity(0.2), location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .black.opacity(0.15), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Card chrome

private struct LoginSpotMiniCard: View {
    let tile: SpotTile
    let width: CGFloat

    private let starGold = Color(red: 1, green: 0.82, blue: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardAsyncImage(url: tile.imageURL, contentMode: .fill, skeletonTone: .warmPlaceholder) {
                LinearGradient(
                    colors: [Color(red: 0.42, green: 0.28, blue: 0.22), Color(red: 0.22, green: 0.14, blue: 0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: width, height: tile.imageHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 5) {
                Text(tile.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundColor(starGold)
                    }
                    Text(String(format: "%.1f", tile.rating))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.16, green: 0.15, blue: 0.14))
        }
        .frame(width: width)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [
                Color(red: 0.26, green: 0.16, blue: 0.11),
                Color(red: 0.34, green: 0.21, blue: 0.15),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        LoginAnimatedSpotsHero()
    }
}
