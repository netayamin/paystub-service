import SwiftUI

/// Full list for a category (Hot Releases, Hot Right Now, or All Drops).
struct AllDropsListView: View {
    let title: String
    let drops: [Drop]
    let style: Style
    
    enum Style {
        case horizontalCards  // Hot Releases: wide cards
        case grid            // Hot Right Now / All: 2-col grid
    }
    
    var body: some View {
        Group {
            if style == .horizontalCards {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(drops) { drop in
                            TopOpportunityCardView(drop: drop)
                        }
                    }
                    .padding(.horizontal)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(drops) { drop in
                            DropCardView(drop: drop)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.background, for: .navigationBar)
    }
}
