import CoreGraphics
import Foundation

/// Column and card sizing for the main preview grid.
struct PreviewGridLayout {
    let columnCount: Int
    let rowCount: Int
    let cardWidth: CGFloat
    let contentWidth: CGFloat
    let gap: CGFloat
}

/// Pure solver for the main grid: picks the largest cards that fit EVERY
/// discovered client inside the visible workspace.
///
/// Fewer columns means wider cards and taller rows, so the solver scans
/// upward from one column and keeps the first arrangement whose estimated
/// total height fits. The estimate uses the TALLEST aspect among the windows
/// (smallest ratio), so the fit guarantee holds for every row no matter how
/// the list packs, not just on average. Cards never exceed `maxCardWidth` (a
/// single oversized thumbnail identifies no better), and when even
/// minimum-width cards cannot fit the window height it falls back to
/// preferred-width columns and lets the scroll view handle the overflow.
enum PreviewGridSolver {
    static let preferredCardWidth: CGFloat = 250
    static let maxCardWidth: CGFloat = 420
    static let minCardWidth: CGFloat = 180
    static let footerHeight: CGFloat = 45
    static let gap: CGFloat = 12
    static let padding: CGFloat = 14

    /// Exact rendered height of one card: preview area at the window's
    /// quantized aspect plus the metadata footer. MainView pins card frames
    /// to this so lazy containers measure tight rows instead of falling back
    /// to the preview image's natural pixel height (which inflated rows by
    /// hundreds of points and scattered the grid with gaps).
    static func cardHeight(cardWidth: CGFloat, aspect: CGFloat) -> CGFloat {
        cardWidth / max(aspect, 1) + footerHeight
    }

    static func solve(
        width: CGFloat,
        height: CGFloat,
        count: Int,
        minAspect: CGFloat
    ) -> PreviewGridLayout {
        let availableWidth = max(1, width - padding * 2)
        let availableHeight = max(1, height - padding * 2)

        func columnsFitting(_ cardWidth: CGFloat) -> Int {
            max(1, Int((availableWidth + gap) / (cardWidth + gap)))
        }
        func rowHeight(_ cardWidth: CGFloat) -> CGFloat {
            cardHeight(cardWidth: cardWidth, aspect: minAspect)
        }

        guard count > 0 else {
            return PreviewGridLayout(
                columnCount: 1,
                rowCount: 0,
                cardWidth: preferredCardWidth,
                contentWidth: preferredCardWidth,
                gap: gap
            )
        }

        var columns = min(count, columnsFitting(preferredCardWidth))
        var cardWidth = min(
            preferredCardWidth,
            floor((availableWidth - CGFloat(columns - 1) * gap) / CGFloat(columns))
        )

        for candidate in 1...count {
            let candidateWidth = min(
                maxCardWidth,
                floor((availableWidth - CGFloat(candidate - 1) * gap) / CGFloat(candidate))
            )
            guard candidateWidth >= minCardWidth || candidate == 1 else { break }
            let rows = Int(ceil(Double(count) / Double(candidate)))
            let contentHeight = CGFloat(rows) * rowHeight(candidateWidth) + CGFloat(rows - 1) * gap
            if contentHeight <= availableHeight {
                columns = candidate
                cardWidth = candidateWidth
                break
            }
        }

        let rowCount = Int(ceil(Double(count) / Double(columns)))
        let contentWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * gap
        return PreviewGridLayout(
            columnCount: columns,
            rowCount: rowCount,
            cardWidth: cardWidth,
            contentWidth: contentWidth,
            gap: gap
        )
    }
}
