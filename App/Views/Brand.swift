import PhinTechStoreKit
import SwiftUI

/// The Phin Tech mark: Pepper, in an inked circle.
struct PepperMark: View {
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let mark = Art.image("pepper-mark") {
                Image(nsImage: mark).resizable().interpolation(.high).scaledToFit()
            } else {
                Circle().fill(Color.paper).overlay(Circle().strokeBorder(Color.ink, lineWidth: size * 0.05))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Phin Tech")
    }
}

/// Pepper with "phin tech" set beside it in Garamond, as on the bottom of every ad.
struct Wordmark: View {
    var size: CGFloat = 36
    var color: Color = .ink

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.2) {
            PepperMark(size: size * 1.5)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] - size * 0.12 }
            Text("phin tech")
                .font(Typeface.garamond(size, "ExtraBold"))
                .tracking(-size * 0.03)
                .foregroundStyle(color)
        }
    }
}

/// The small cream-on-colour "phin tech" badge used on boxes.
struct BoxBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            PepperMark(size: 15)
            Text("PHIN TECH")
                .font(.custom("Futura-Bold", fixedSize: 8))
                .tracking(1.2)
                .foregroundStyle(Color.paper)
        }
    }
}
