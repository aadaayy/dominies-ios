import SwiftUI
import UIKit

/// Framing a new profile picture, like Contacts does: the photo behind a
/// round window, pinch to zoom and drag to move, then Choose. The photo
/// always covers the circle, so the picture never has empty corners.
struct PictureCropView: View {
    /// Upright and no bigger than `Pictures.workingSize` (Pictures.prepare).
    let image: UIImage
    var onCancel: () -> Void
    var onChoose: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    /// Most the photo zooms in, past just covering the circle.
    private let maxScale: CGFloat = 6
    private let barHeight: CGFloat = 52

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            // As big as fits between the bars, with a margin all round.
            let side = max(120, min(size.width - 48, size.height - (barHeight + 12) * 2, 440))
            let fill = side / max(min(image.size.width, image.size.height), 1)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: image.size.width * fill * scale, height: image.size.height * fill * scale)
                    .offset(offset)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .accessibilityHidden(true)
                Window(side: side)
                    .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 1)
                    .frame(width: side, height: side)
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    topBar(side: side, fill: fill)
                    Spacer(minLength: 0)
                    Text("Pinch to zoom and drag to move")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(height: barHeight)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        offset = clamped(CGSize(width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height),
                                         side: side, fill: fill)
                    }
                    .onEnded { _ in lastOffset = offset }
                    .simultaneously(with: MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value.magnification, 1), maxScale)
                            offset = clamped(offset, side: side, fill: fill)
                        }
                        .onEnded { _ in
                            lastScale = scale
                            lastOffset = offset
                        })
            )
            .accessibilityIdentifier("crop-area")
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func topBar(side: CGFloat, fill: CGFloat) -> some View {
        HStack {
            Button("Cancel", action: onCancel)
                .font(.body.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassPanel(Capsule(), interactive: true)
                .buttonStyle(.plain)
                .accessibilityIdentifier("crop-cancel")
            Spacer()
            Text("Move and Scale")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button {
                onChoose(Pictures.picture(from: image, crop: crop(side: side, fill: fill)))
            } label: {
                Text("Choose")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
            }
            .prominentGlassButton()
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("crop-choose")
        }
        .padding(.horizontal, 16)
        .frame(height: barHeight)
    }

    /// Keeps the photo over the whole circle.
    private func clamped(_ proposed: CGSize, side: CGFloat, fill: CGFloat) -> CGSize {
        let maxX = max(0, (image.size.width * fill * scale - side) / 2)
        let maxY = max(0, (image.size.height * fill * scale - side) / 2)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    /// The circle's square, in the photo's own pixels.
    private func crop(side: CGFloat, fill: CGFloat) -> CGRect {
        let k = fill * scale // screen points per photo pixel
        let shown = CGSize(width: image.size.width * k, height: image.size.height * k)
        let x = (shown.width / 2 - offset.width - side / 2) / k
        let y = (shown.height / 2 - offset.height - side / 2) / k
        return CGRect(x: x, y: y, width: side / k, height: side / k)
    }

    /// The dimmed screen with a round window in the middle.
    private struct Window: Shape {
        let side: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path(rect)
            path.addEllipse(in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
            return path
        }
    }
}
