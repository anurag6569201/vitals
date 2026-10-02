import SwiftUI

/// One motion language for all of Vitals: the same springs, timings and hover feel everywhere,
/// so the app moves like one thing. Everything here backs off when Reduce Motion is on.
enum Motion {
    /// Layout changes, cards appearing, selections.
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    /// Hover and press feedback.
    static let quick = Animation.snappy(duration: 0.2)
    /// Gauges and bars settling to a new value.
    static let gauge = Animation.smooth(duration: 0.7)
    /// Delay between items in a staggered entrance.
    static let stagger = 0.035
}

// MARK: - Staggered entrance

private struct AppearEpochKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    /// Bumped each time the popover opens, so its entrance replays.
    var appearEpoch: Int {
        get { self[AppearEpochKey.self] }
        set { self[AppearEpochKey.self] = newValue }
    }
}

private struct StaggeredAppear: ViewModifier {
    let index: Int
    @Environment(\.appearEpoch) private var epoch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .scaleEffect(shown || reduceMotion ? 1 : 0.985, anchor: .top)
            .onAppear(perform: animateIn)
            .onChange(of: epoch) { _, _ in
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { shown = false }
                DispatchQueue.main.async(execute: animateIn)
            }
    }

    private func animateIn() {
        let animation = reduceMotion ? Animation.easeOut(duration: 0.15)
                                     : Motion.spring.delay(Double(min(index, 12)) * Motion.stagger)
        withAnimation(animation) { shown = true }
    }
}

// MARK: - Hover & press

private struct HoverLift: ViewModifier {
    var scale: CGFloat
    var shadow: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? scale : 1)
            .shadow(color: .black.opacity(shadow && hovering ? 0.12 : 0), radius: hovering ? 8 : 0, y: hovering ? 3 : 0)
            .animation(Motion.quick, value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Buttons that dip slightly when pressed and glow on hover.
struct PressableStyle: ButtonStyle {
    var hoverFill = true

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, hoverFill: hoverFill)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        let hoverFill: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            configuration.label
                .brightness(hoverFill && hovering ? 0.03 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(Motion.quick, value: configuration.isPressed)
                .animation(Motion.quick, value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// Fade-and-rise entrance, staggered by `index`.
    func vitalsAppear(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }

    /// A gentle lift under the pointer.
    func hoverLift(_ scale: CGFloat = 1.015, shadow: Bool = true) -> some View {
        modifier(HoverLift(scale: scale, shadow: shadow))
    }
}

// MARK: - Animated bar

/// A thin progress bar that glides to new values (ProgressView jumps).
struct AnimatedBar: View {
    let value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(tint.gradient)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .animation(Motion.gauge, value: value)
    }
}

/// Breathing ring around the status badge while something needs attention.
struct BreathingRing: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .stroke(color.opacity(on ? 0 : 0.55), lineWidth: 2)
            .scaleEffect(on ? 1.45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { on = true }
            }
    }
}
