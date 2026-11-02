import SwiftUI
import UIKit

/// The line of tiles on the table, laid out by `BoardLayout` so tiles never
/// overlap. The snake's width follows the space; the whole line shrinks to fit
/// only once it grows past the edges.
struct TableView: View {
    let board: Board
    /// The tile played last, which gets a soft highlight.
    var lastTile: Tile?
    /// Ends to offer when a tile in your hand fits both.
    var endChoice: (left: Int, right: Int)?
    var onChooseEnd: (End) -> Void = { _ in }

    /// The tile length the layout aims for, in points.
    static let idealTileLength = 56.0

    /// Pinch to look closer; the view goes back to the whole line after
    /// every tile played.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var zoomAtPinchStart: CGFloat?
    @State private var panAtDragStart: CGSize?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let halfWidth = BoardLayout.halfWidth(forTableWidth: Double(size.width), idealTileLength: Self.idealTileLength)
            let laid = BoardLayout.lay(board, halfWidth: halfWidth)
            let frame = Self.frame(for: laid, halfWidth: halfWidth, size: size)

            ZStack(alignment: .topLeading) {
                ForEach(laid) { tile in
                    let rect = frame.convert(tile.rect)
                    // A hairline gap shows where tiles meet.
                    let gap = CGFloat(frame.unit * 0.05)
                    DominoView(first: tile.firstFace, second: tile.secondFace, isVertical: tile.isVertical)
                        .frame(width: rect.width - gap * 2, height: rect.height - gap * 2)
                        .overlay {
                            if tile.tile == lastTile {
                                RoundedRectangle(cornerRadius: frame.unit * 0.18, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: max(1.5, frame.unit * 0.08))
                            }
                        }
                        // Name the tile itself (before positioning, which
                        // would stretch the element over the whole table).
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(tile.tile.low) and \(tile.tile.high)")
                        .accessibilityIdentifier("table-tile-\(tile.tile.id)")
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                if let endChoice, let ends = endTargets(laid: laid, frame: frame) {
                    endButton(.left, value: endChoice.left, at: ends.left, unit: frame.unit)
                    endButton(.right, value: endChoice.right, at: ends.right, unit: frame.unit)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .animation(.spring(duration: 0.35), value: board.count)
            .scaleEffect(zoom)
            .offset(pan)
            .frame(width: size.width, height: size.height)
            .clipped()
            // Pinch and drag land on a layer underneath (the tiles let
            // touches through), so the tiles keep their own identities.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(pinch(in: size))
                    .simultaneousGesture(drag(in: size), including: zoom > 1 ? .all : .none)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .topTrailing) {
                if zoom > 1 {
                    Button(action: zoomOut) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 36)
                            .glassPanel(Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityIdentifier("zoom-fit")
                    .accessibilityLabel("Show the whole line")
                }
            }
            .onChange(of: board.count) { zoomOut() }
        }
        // Contain the tiles rather than renaming them all "table".
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("table")
    }

    // MARK: - Zoom

    private func zoomOut() {
        withAnimation(.spring(duration: 0.45)) {
            zoom = 1
            pan = .zero
        } completion: {
            Self.tilesMoved()
        }
    }

    /// Tells VoiceOver (and the automatic checks) the tiles moved on screen,
    /// since zooming only changes how they're drawn, not the layout.
    private static func tilesMoved() {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    private func pinch(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomAtPinchStart ?? zoom
                zoomAtPinchStart = start
                zoom = min(2.5, max(1, start * value.magnification))
                pan = clamped(pan, in: size)
            }
            .onEnded { _ in
                zoomAtPinchStart = nil
                if zoom < 1.05 { zoomOut() } else { Self.tilesMoved() }
            }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let start = panAtDragStart ?? pan
                panAtDragStart = start
                pan = clamped(CGSize(width: start.width + value.translation.width,
                                     height: start.height + value.translation.height), in: size)
            }
            .onEnded { _ in
                panAtDragStart = nil
                Self.tilesMoved()
            }
    }

    /// Keeps the zoomed line from sliding off the table.
    private func clamped(_ offset: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (zoom - 1) / 2
        let maxY = size.height * (zoom - 1) / 2
        return CGSize(width: min(maxX, max(-maxX, offset.width)), height: min(maxY, max(-maxY, offset.height)))
    }

    /// Converts table units to points: a scale and an offset.
    struct Frame {
        var unit: Double
        var originX: Double
        var originY: Double

        func convert(_ rect: TableRect) -> CGRect {
            CGRect(x: originX + rect.x * unit, y: originY + rect.y * unit, width: rect.width * unit, height: rect.height * unit)
        }

        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: originX + x * unit, y: originY + y * unit) }
    }

    /// Fits the line in the space. Until it outgrows it, the scale stays put
    /// and the opening tile stays in the middle, so nothing jumps around.
    static func frame(for laid: [LaidTile], halfWidth: Double, size: CGSize) -> Frame {
        let margin = 8.0
        let width = max(1, Double(size.width) - margin * 2)
        let height = max(1, Double(size.height) - margin * 2)
        // The resting view: the full row width (plus the turn columns), centred.
        let restingWidth = halfWidth * 2 + 2
        let unit = min(width / restingWidth, idealTileLength / 2)
        var box = TableRect(x: -restingWidth / 2, y: -height / unit / 2, width: restingWidth, height: height / unit)
        if let bounds = BoardLayout.bounds(of: laid) { box = box.union(bounds) }
        let fitted = min(unit, width / box.width, height / box.height)
        let originX = margin + width / 2 - box.midX * fitted
        let originY = margin + height / 2 - box.midY * fitted
        return Frame(unit: fitted, originX: originX, originY: originY)
    }

    /// Where to show the two end buttons: just past each open end.
    private func endTargets(laid: [LaidTile], frame: Frame) -> (left: CGPoint, right: CGPoint)? {
        guard let origin = laid.first(where: { $0.branch == .origin }) else { return nil }
        let leftEnd = laid.filter { $0.branch == .left }.max(by: { $0.step < $1.step }) ?? origin
        let rightEnd = laid.filter { $0.branch == .right }.max(by: { $0.step < $1.step }) ?? origin
        return (frame.convert(leftEnd.rect).center, frame.convert(rightEnd.rect).center)
    }

    private func endButton(_ end: End, value: Int, at point: CGPoint, unit: Double) -> some View {
        Button {
            onChooseEnd(end)
        } label: {
            Text("\(value)")
                .font(.system(size: max(13, unit * 0.7), weight: .semibold, design: .rounded))
                .frame(width: max(34, unit * 1.6), height: max(34, unit * 1.6))
                .foregroundStyle(.white)
                .glassPanel(Circle(), tint: .accentColor, interactive: true)
        }
        .buttonStyle(.plain)
        .position(point)
        .accessibilityIdentifier(end == .left ? "end-left" : "end-right")
        .accessibilityLabel("Play on the \(value) end")
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
