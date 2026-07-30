import SwiftUI

/// Classic UNO card face drawn in pure SwiftUI. Aspect ratio is fixed at 2:3.
struct CardView: View {
    let card: UnoCard
    var width: CGFloat = 72

    private var height: CGFloat { width * 1.5 }
    private var cornerRadius: CGFloat { width * 0.14 }
    /// Unchosen wilds render on a near-black slab.
    private var baseColor: Color {
        card.effectiveColor?.tint ?? Color(red: 0.13, green: 0.13, blue: 0.16)
    }
    private var showsCorners: Bool { width >= 40 }
    /// Frosted-glass treatment only pays off at readable sizes; tiny stack/count
    /// cards keep the cheap opaque gradient (the blur is invisible there anyway).
    private var glassy: Bool { width >= 40 }

    var body: some View {
        ZStack {
            cardSurface
            RoundedRectangle(cornerRadius: cornerRadius)
                .inset(by: width * 0.05)
                .stroke(.white.opacity(0.85), lineWidth: max(1, width * 0.028))
            Ellipse()
                .fill(.white.opacity(glassy ? 0.22 : 0.16))
                .frame(width: width * 0.95, height: height * 0.6)
                .rotationEffect(.degrees(-32))
                .blendMode(.plusLighter)
            centerArt
            if showsCorners { cornerSymbols }
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }

    /// Card body: a translucent color wash so the background shows straight
    /// through — no material layer, which would frost over that transparency.
    @ViewBuilder
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        shape.fill(baseColor.opacity(glassy ? 0.45 : 1).gradient)
    }

    @ViewBuilder
    private var centerArt: some View {
        if card.isWild {
            ZStack {
                QuadrantCircle()
                    .frame(width: width * 0.58, height: width * 0.58)
                if card.type == .wildDrawFour {
                    Text("+4")
                        .font(.system(size: width * 0.3, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 2)
                }
            }
        } else {
            symbolView(size: width * 0.42)
        }
    }

    @ViewBuilder
    private func symbolView(size: CGFloat) -> some View {
        Group {
            switch card.type {
            case .skip:
                Image(systemName: "nosign")
                    .font(.system(size: size * 0.9, weight: .bold))
            case .wild:
                Text("★").font(.system(size: size, weight: .heavy))
            default:
                Text(card.symbol)
                    .font(.system(size: size, weight: .heavy, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
    }

    private var cornerSymbols: some View {
        VStack {
            HStack {
                symbolView(size: width * 0.16)
                Spacer()
            }
            Spacer()
            HStack {
                Spacer()
                symbolView(size: width * 0.16)
                    .rotationEffect(.degrees(180))
            }
        }
        .padding(width * 0.1)
    }
}

/// The 4-color disc used by wild cards.
private struct QuadrantCircle: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                CardColor.red.tint
                CardColor.blue.tint
            }
            HStack(spacing: 0) {
                CardColor.yellow.tint
                CardColor.green.tint
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

/// UNO card back: dark red with the tilted white "UNO" oval wordmark.
struct CardBackView: View {
    var width: CGFloat = 72

    private var height: CGFloat { width * 1.5 }
    private var cornerRadius: CGFloat { width * 0.14 }

    private var glassy: Bool { width >= 40 }

    var body: some View {
        ZStack {
            backSurface
            RoundedRectangle(cornerRadius: cornerRadius)
                .inset(by: width * 0.05)
                .stroke(.white.opacity(0.85), lineWidth: max(1, width * 0.025))
            Ellipse()
                .fill(Color(red: 0.75, green: 0.12, blue: 0.16))
                .frame(width: width * 0.95, height: height * 0.55)
                .rotationEffect(.degrees(-32))
                .overlay(
                    Ellipse()
                        .stroke(.white, lineWidth: max(1, width * 0.02))
                        .frame(width: width * 0.95, height: height * 0.55)
                        .rotationEffect(.degrees(-32))
                )
            Text("UNO")
                .font(.system(size: width * 0.3, weight: .black, design: .rounded))
                .italic()
                .foregroundStyle(.yellow)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                .rotationEffect(.degrees(-12))
        }
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }

    @ViewBuilder
    private var backSurface: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        let deckRed = Color(red: 0.16, green: 0.05, blue: 0.07)
        shape.fill(deckRed.opacity(glassy ? 0.5 : 1).gradient)
    }
}
