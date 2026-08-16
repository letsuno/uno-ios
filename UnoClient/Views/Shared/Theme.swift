import SwiftUI

/// Shared accent palette for the table/game surfaces. These exact RGB values
/// were duplicated across the FX, hand and seat views; centralising them keeps
/// the "gold table" look consistent and tweakable in one place.
enum UnoPalette {
    /// Primary table gold — rings, playable outlines, acting-player name.
    static let amber = Color(red: 0.96, green: 0.75, blue: 0.24)
    /// Warmer glow gold — shadows and breathing pulses.
    static let gold = Color(red: 0.98, green: 0.75, blue: 0.14)
    /// Alert rose — critical countdown and low-time warnings.
    static let rose = Color(red: 1.0, green: 0.36, blue: 0.51)
    /// Safe emerald — countdown ring while time is plentiful.
    static let emerald = Color(red: 0.20, green: 0.80, blue: 0.40)
}

/// Shared measurements for the landscape-first layout. iPhone is locked to landscape,
/// so screens are wide and short: content is laid out in columns, and controls are
/// capped rather than stretched across the full width.
enum UnoLayout {
    /// Primary buttons stop growing here — stretched across a landscape screen a button
    /// reads as a banner, not a control.
    static let actionWidth: CGFloat = 280
    /// Widest a screen's content grows before it stops tracking the display.
    static let contentWidth: CGFloat = 1000
    /// Narrowest a content column may become before the grid drops to fewer columns.
    static let columnWidth: CGFloat = 260
}

extension View {
    /// Uniform inset for a screen's content, on top of the half safe-area margin
    /// `RootView` already applies — hence the modest values.
    func screenInsets() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    /// Caps a primary action so it stays a button on a 1000pt-wide screen.
    func actionWidth() -> some View {
        frame(maxWidth: UnoLayout.actionWidth)
    }

    /// Compact "chip" surface: symmetric padding on a regular-glass capsule.
    /// Replaces the padding-plus-`glassEffect(.regular, in: .capsule)` chain that
    /// was hand-repeated across the HUD, lobby and room views.
    func glassChip(horizontal: CGFloat = 10, vertical: CGFloat = 5) -> some View {
        padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .glassEffect(.regular, in: .capsule)
    }
}

/// Round-trip indicator: a health-colored dot next to the measurement. Used both for
/// the live socket ping in the lobby and for landing-screen server probes.
struct LatencyLabel: View {
    let milliseconds: Int?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(milliseconds.map { "\($0) ms" } ?? "-- ms")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Round trip")
    }

    private var color: Color {
        guard let milliseconds else { return .gray }
        if milliseconds < 50 { return .green }
        if milliseconds <= 150 { return .yellow }
        return .red
    }
}

/// Shared dark table backdrop: deep neutral base with soft color glows so the
/// Liquid Glass layers above have something to refract.
struct UnoBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.08, blue: 0.11)
            RadialGradient(
                colors: [Color(red: 0.85, green: 0.25, blue: 0.30).opacity(0.35), .clear],
                center: .init(x: 0.15, y: 0.05),
                startRadius: 10,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.15, green: 0.40, blue: 0.95).opacity(0.30), .clear],
                center: .init(x: 0.9, y: 0.25),
                startRadius: 10,
                endRadius: 380
            )
            RadialGradient(
                colors: [Color(red: 0.20, green: 0.65, blue: 0.35).opacity(0.22), .clear],
                center: .init(x: 0.2, y: 0.95),
                startRadius: 10,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// `NavigationStack` and sheet presentations paint their own opaque container
    /// background, which hides the one `RootView` puts behind everything. Screens living
    /// inside such a container repaint the same backdrop so every surface matches.
    func unoBackdrop() -> some View {
        background(UnoBackground())
    }
}

/// Section container used across screens: content on a glass slab.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct ToastView: View {
    let message: SessionStore.ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isError ? .orange : .green)
            Text(message.text)
                .font(.subheadline.weight(.medium))
                .lineLimit(3)
        }
        .glassChip(horizontal: 16, vertical: 12)
        .padding(.horizontal, 24)
        .safeAreaPadding(.top)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Attach once near the root of a screen hierarchy.
    func toastOverlay(_ session: SessionStore) -> some View {
        overlay(alignment: .top) {
            if let toast = session.toast {
                ToastView(message: toast)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(3))
                        if session.toast?.id == toast.id { session.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: session.toast)
    }
}
