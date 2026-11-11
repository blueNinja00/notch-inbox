import SwiftUI

/// The black shape hanging from the notch. It morphs between levels and shows
/// the matching content inside.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let metrics = model.metrics
        let level = model.level
        let ears = model.restEars
        let outline = model.outline(level)
        let shape = NotchShape(bottomRadius: metrics.bottomRadius(level),
                               shoulder: metrics.shoulder(level, ears: ears))
        // Minimised to the mail icon: nothing at the notch until it's opened.
        let hidden = model.minimised && level == .rest

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape
                    .fill(Color.black)
                    .shadow(color: Color.black.opacity(level == .rest ? 0 : 0.55), radius: 26, x: 0, y: 14)
                content(for: level)
                    .frame(width: outline.width, height: outline.height, alignment: .top)
                    .clipShape(shape)
                if level != .rest {
                    ResizeHandles(model: model, level: level)
                        .frame(width: outline.width, height: outline.height)
                }
            }
            .frame(width: outline.width, height: outline.height)
            .opacity(hidden ? 0 : 1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(Theme.spring, value: level)
        .animation(Theme.spring, value: ears)
    }

    @ViewBuilder
    private func content(for level: NotchLevel) -> some View {
        switch level {
        case .rest:
            RestView(model: model)
                .transition(.opacity)
        case .peek:
            HomeView(model: model)
                .transition(.opacity)
        case .lanes, .detail:
            if model.tool == .settings {
                SettingsView(model: model, settings: AppSettings.shared, assistant: Assistant.shared)
                    .transition(.opacity)
            } else if model.tool == .notes, let store = model.notesStore {
                NotesView(model: model, store: store, expanded: level == .detail)
                    .transition(.opacity)
            } else if model.tool == .planner, let store = model.plannerStore, let timetable = model.timetableStore {
                PlannerView(model: model, store: store, timetable: timetable, settings: AppSettings.shared,
                            assistant: Assistant.shared, expanded: level == .detail)
                    .transition(.opacity)
            } else if model.tool == .timetable, let store = model.timetableStore, let planner = model.plannerStore {
                TimetableView(model: model, store: store, planner: planner, settings: AppSettings.shared, expanded: level == .detail)
                    .transition(.opacity)
            } else if model.tool == .extras {
                ExtrasView(model: model, settings: AppSettings.shared, expanded: level == .detail)
                    .transition(.opacity)
            } else if model.tool == .assistant {
                AssistantView(model: model, assistant: Assistant.shared, expanded: level == .detail)
                    .transition(.opacity)
            } else if level == .lanes {
                LanesView(model: model)
                    .transition(.opacity)
            } else {
                DetailView(model: model)
                    .transition(.opacity)
            }
        }
    }
}

/// Flat top flush with the screen edge, inward-curving shoulders where it meets
/// the menu bar, and rounded bottom corners — the shape of the notch itself.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var shoulder: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulder) }
        set {
            bottomRadius = newValue.first
            shoulder = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = max(0, min(shoulder, rect.width / 4))
        let r = max(0, min(bottomRadius, (rect.width - 2 * s) / 2, rect.height / 2))
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: left, y: top))
        path.addArc(tangent1End: CGPoint(x: left + s, y: top),
                    tangent2End: CGPoint(x: left + s, y: top + s),
                    radius: s)
        path.addLine(to: CGPoint(x: left + s, y: bottom - r))
        path.addArc(tangent1End: CGPoint(x: left + s, y: bottom),
                    tangent2End: CGPoint(x: left + s + r, y: bottom),
                    radius: r)
        path.addLine(to: CGPoint(x: right - s - r, y: bottom))
        path.addArc(tangent1End: CGPoint(x: right - s, y: bottom),
                    tangent2End: CGPoint(x: right - s, y: bottom - r),
                    radius: r)
        path.addLine(to: CGPoint(x: right - s, y: top + s))
        path.addArc(tangent1End: CGPoint(x: right - s, y: top),
                    tangent2End: CGPoint(x: right, y: top),
                    radius: s)
        path.closeSubpath()
        return path
    }
}
