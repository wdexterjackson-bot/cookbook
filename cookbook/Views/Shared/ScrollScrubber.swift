//
//  ScrollScrubber.swift
//  cookbook
//
//  iOS/iPadOS only: the system List scroll indicator is a few points wide
//  and effectively impossible to grab precisely with a finger on a long
//  list (reported directly against the recipe lists). There's no public
//  API to widen or restyle it, so this is a standalone, much wider drag
//  handle overlaid on the trailing edge that maps a vertical drag
//  fraction (0...1) onto `itemIDs` and scrolls the nearest one into view
//  via a ScrollViewReader proxy. Only appears once a list is long enough
//  to need it. tvOS has no touch/DragGesture concept and macOS has no
//  equivalent complaint (a real mouse-draggable scrollbar already exists
//  there), so the whole type is iOS-only — call sites gate their own use
//  of it with the same #if.
//

#if os(iOS)
import SwiftUI

struct ScrollScrubber<ID: Hashable>: View {
    let itemIDs: [ID]
    let proxy: ScrollViewProxy

    @State private var isDragging = false
    @State private var dragFraction: CGFloat = 0

    /// Below this count the native indicator is perfectly usable — no
    /// point cluttering the edge of a short list.
    private static var minimumItemCount: Int { 12 }

    var body: some View {
        GeometryReader { geo in
            if itemIDs.count >= Self.minimumItemCount {
                let stripHeight = geo.size.height
                let thumbHeight = max(44, stripHeight * 0.08)
                let usableHeight = max(stripHeight - thumbHeight, 1)

                ZStack(alignment: .top) {
                    // The hit target is this whole trailing strip, not
                    // just the thin visible capsule below — that's the
                    // actual usability fix, since a finger can't
                    // reliably land on a 6pt-wide line.
                    Color.clear
                        .frame(width: 44, height: stripHeight)
                        .contentShape(Rectangle())

                    Capsule()
                        .fill(isDragging ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: isDragging ? 12 : 6, height: thumbHeight)
                        .offset(y: usableHeight * dragFraction)
                        .animation(.easeOut(duration: 0.15), value: isDragging)
                }
                .padding(.trailing, 4)
                .position(x: geo.size.width - 22, y: stripHeight / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = min(max((value.location.y - thumbHeight / 2) / usableHeight, 0), 1)
                            dragFraction = fraction
                            scrollToFraction(fraction)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
        }
        .accessibilityHidden(true)
    }

    private func scrollToFraction(_ fraction: CGFloat) {
        guard !itemIDs.isEmpty else { return }
        let index = min(itemIDs.count - 1, Int(fraction * CGFloat(itemIDs.count)))
        proxy.scrollTo(itemIDs[index], anchor: .top)
    }
}
#endif
