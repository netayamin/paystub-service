import SwiftUI

// MARK: - Live stream (Quiet Curator) — same card as Latest drops / Explore

/// Editorial reservation tile for the live list; layout matches `EditorialReservationCard`.
struct LiveStreamEventCard: View {
    let drop: Drop
    let preferredParty: Int
    var onTap: () -> Void

    var body: some View {
        EditorialReservationCard(
            drop: drop,
            partyPeopleText: "\(preferredParty) PEOPLE",
            onHeroTap: onTap
        )
    }
}
