import AppKit
import SwiftUI

/// Drag the open panel bigger or smaller: the bottom edge changes its height, the grip in
/// the bottom-right corner changes both (it grows on both sides, staying centred on the
/// notch). Double-click the grip to go back to the standard size. Sizes are remembered.
struct ResizeHandles: View {
    @ObservedObject var model: NotchModel
    let level: NotchLevel
    @State private var startSize: CGSize?

    init(model: NotchModel, level: NotchLevel) {
        self.model = model
        self.level = level
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // The bottom edge: height only.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 7)
                .contentShape(Rectangle())
                .gesture(resizing(width: false))
                .onHover { inside in
                    (inside ? NSCursor.resizeUpDown : NSCursor.arrow).set()
                }
                .frame(maxHeight: .infinity, alignment: .bottom)

            // The corner grip: width and height.
            ResizeGrip()
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
                .padding(.trailing, 7)
                .padding(.bottom, 7)
                .gesture(resizing(width: true))
                .onTapGesture(count: 2) { model.resetSize(level) }
                .help("Drag to resize · double-click for the standard size")
        }
    }

    /// Measured in window coordinates, which stay put while the panel changes size.
    private func resizing(width: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { drag in
                if startSize == nil {
                    startSize = model.size(level)
                    model.pinHome()
                }
                guard let start = startSize else { return }
                let newWidth = width ? start.width + drag.translation.width * 2 : start.width
                model.resize(level, to: CGSize(width: newWidth, height: start.height + drag.translation.height))
            }
            .onEnded { _ in
                startSize = nil
                model.finishResizing()
            }
    }
}

/// Three short diagonal lines, like a window's resize corner.
struct ResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            for step in 1...3 {
                let reach = CGFloat(step) * 4
                var line = Path()
                line.move(to: CGPoint(x: size.width - 1, y: size.height - 1 - reach))
                line.addLine(to: CGPoint(x: size.width - 1 - reach, y: size.height - 1))
                context.stroke(line, with: .color(Color.white.opacity(0.28)), lineWidth: 1.2)
            }
        }
        .frame(width: 14, height: 14)
    }
}
