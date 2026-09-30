import SwiftUI

// MARK: - Characters Pip can dress up as
// Everything is drawn in code and layered onto Pip, so outfits squash, tilt, wave
// and get thrown along with the body. All sizes are fractions of Pip's `size`.

enum Skin: String, CaseIterable, Identifiable {
    case pip, peaky, tanjiro, harry

    var id: String { rawValue }

    var name: String {
        switch self {
        case .pip: "Pip"
        case .peaky: "Peaky Blinders"
        case .tanjiro: "Tanjiro Kamado"
        case .harry: "Harry Potter"
        }
    }

    var greetings: [String] {
        switch self {
        case .pip: ["Hi there!", "Oh, hello!", "Hey you!", "Psst… hi!"]
        case .peaky: ["Alright?", "Evening.", "Oh. It's you.", "Mind the cap."]
        case .tanjiro: ["I'll do my best!", "Hi! Ready to train?", "Total concentration… hi!"]
        case .harry: ["Lumos! …oh, hi.", "Hello! Seen my owl?", "Hi! Mischief managed."]
        }
    }

    /// The flat cap sits where the sprout would be.
    var showsSprout: Bool { self != .peaky }

    /// Saved choice (also read by the menus through @AppStorage("skin")).
    static var current: Skin {
        Skin(rawValue: UserDefaults.standard.string(forKey: "skin") ?? "") ?? .pip
    }
}

/// "Character" picker used in the menu bar menu and Pip's right-click menu.
struct CharacterPicker: View {
    @AppStorage("skin") private var skin: Skin = .pip

    var body: some View {
        Picker("Character", selection: $skin) {
            ForEach(Skin.allCases) { Text($0.name).tag($0) }
        }
    }
}

// MARK: - Layers, in drawing order

/// Marks on the skin (scars), drawn right on top of the body.
struct SkinBodyMarks: View {
    let skin: Skin
    let size: CGFloat

    var body: some View {
        switch skin {
        case .tanjiro:
            FlameScar()
                .fill(Color(red: 0.64, green: 0.13, blue: 0.16).opacity(0.92))
                .frame(width: size * 0.27, height: size * 0.17)
                .offset(x: size * 0.19, y: -size * 0.27)
        case .harry:
            Bolt()
                .stroke(Color(red: 0.78, green: 0.16, blue: 0.14),
                        style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.08, height: size * 0.15)
                .offset(x: -size * 0.05, y: -size * 0.3)
        default:
            EmptyView()
        }
    }
}

/// Things worn on the face (glasses). Goes inside the face so it turns with it.
struct SkinFaceWear: View {
    let skin: Skin
    let size: CGFloat

    var body: some View {
        if skin == .harry {
            RoundGlasses(size: size)
                .offset(y: -size * 0.04)
        }
    }
}

/// Hats, drawn over the face.
struct SkinHeadwear: View {
    let skin: Skin
    let size: CGFloat

    var body: some View {
        if skin == .peaky {
            FlatCap(size: size)
        }
    }
}

extension Skin {
    /// What Pip holds in each hand. The view's center is the grip.
    @ViewBuilder
    func heldItem(right: Bool, size: CGFloat) -> some View {
        switch (self, right) {
        case (.peaky, true): Revolver(size: size).rotationEffect(.degrees(-12)).scaleEffect(1.5).offset(y: size * 0.1)
        case (.tanjiro, true): Katana(size: size).rotationEffect(.degrees(8))
        case (.harry, false): Wand(size: size).rotationEffect(.degrees(-14))
        default: EmptyView()
        }
    }

    func holdsSomething(right: Bool) -> Bool {
        switch (self, right) {
        case (.peaky, true), (.tanjiro, true), (.harry, false): true
        default: false
        }
    }
}

// MARK: - Peaky Blinders: tweed flat cap with a razor blade in the peak

private struct FlatCap: View {
    let size: CGFloat
    private let tweedLight = Color(red: 0.45, green: 0.43, blue: 0.39)
    private let tweedDark = Color(red: 0.31, green: 0.29, blue: 0.26)

    var body: some View {
        ZStack {
            // Crown
            CapCrown()
                .fill(LinearGradient(colors: [tweedLight, tweedDark], startPoint: .top, endPoint: .bottom))
                .overlay { Herringbone().clipShape(CapCrown()) }
                .overlay {
                    // Panel seams from the button
                    CapSeams().stroke(Color.black.opacity(0.25), lineWidth: size * 0.012)
                }
                .frame(width: size * 1.14, height: size * 0.44)
                .offset(y: -size * 0.47)

            // Peak
            Ellipse()
                .fill(LinearGradient(colors: [tweedDark, Color(red: 0.25, green: 0.23, blue: 0.21)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay { Herringbone().clipShape(Ellipse()) }
                .frame(width: size * 0.98, height: size * 0.13)
                .offset(y: -size * 0.27)

            // Button on top
            Circle()
                .fill(Color(red: 0.26, green: 0.24, blue: 0.22))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(y: -size * 0.68)

            RazorBlade(size: size)
                .rotationEffect(.degrees(-38))
                .offset(x: size * 0.38, y: -size * 0.56)
        }
    }
}

private struct CapCrown: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        // Puffy dome, slightly fuller at the front (left) like a newsboy cap.
        p.addCurve(to: CGPoint(x: r.midX + r.width * 0.05, y: r.minY),
                   control1: CGPoint(x: r.minX - r.width * 0.02, y: r.minY + r.height * 0.25),
                   control2: CGPoint(x: r.minX + r.width * 0.2, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                   control1: CGPoint(x: r.maxX - r.width * 0.15, y: r.minY),
                   control2: CGPoint(x: r.maxX + r.width * 0.02, y: r.minY + r.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY),
                       control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.12))
        p.closeSubpath()
        return p
    }
}

private struct CapSeams: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let top = CGPoint(x: r.midX + r.width * 0.05, y: r.minY + r.height * 0.02)
        for f in [0.12, 0.34, 0.62, 0.86] as [CGFloat] {
            let end = CGPoint(x: r.minX + r.width * f, y: r.maxY)
            p.move(to: top)
            p.addQuadCurve(to: end, control: CGPoint(x: (top.x + end.x) / 2 + (f - 0.5) * r.width * 0.25,
                                                      y: r.minY + r.height * 0.4))
        }
        return p
    }
}

/// Faint zigzag weave.
private struct Herringbone: View {
    var body: some View {
        Canvas { ctx, sz in
            let step: CGFloat = 3
            var p = Path()
            var y: CGFloat = 0
            var row = 0
            while y < sz.height + step {
                var x: CGFloat = 0
                p.move(to: CGPoint(x: 0, y: y))
                while x < sz.width + step {
                    x += step
                    p.addLine(to: CGPoint(x: x, y: y + (Int(x / step) % 2 == row % 2 ? step * 0.7 : 0)))
                }
                y += step
                row += 1
            }
            ctx.stroke(p, with: .color(.white.opacity(0.1)), lineWidth: 0.6)
        }
    }
}

private struct RazorBlade: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.02)
            .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.62)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                // Slot and holes of a safety razor blade
                ZStack {
                    Capsule().fill(Color(white: 0.3))
                        .frame(width: size * 0.12, height: size * 0.022)
                    HStack(spacing: size * 0.1) {
                        Circle().fill(Color(white: 0.3))
                        Circle().fill(Color(white: 0.3))
                    }
                    .frame(width: size * 0.15, height: size * 0.035)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: size * 0.02).stroke(Color(white: 0.45), lineWidth: 0.5))
            .frame(width: size * 0.21, height: size * 0.1)
    }
}

// MARK: - Revolver (grip at the center)

private struct Revolver: View {
    let size: CGFloat
    private let steel = Color(red: 0.55, green: 0.57, blue: 0.6)
    private let steelDark = Color(red: 0.36, green: 0.38, blue: 0.41)
    private let wood = Color(red: 0.5, green: 0.3, blue: 0.18)

    var body: some View {
        ZStack {
            // Barrel, pointing left
            RoundedRectangle(cornerRadius: size * 0.012)
                .fill(steel)
                .frame(width: size * 0.22, height: size * 0.045)
                .offset(x: -size * 0.2, y: -size * 0.1)
            // Frame
            RoundedRectangle(cornerRadius: size * 0.025)
                .fill(steelDark)
                .frame(width: size * 0.15, height: size * 0.09)
                .offset(x: -size * 0.04, y: -size * 0.08)
            // Cylinder
            Capsule()
                .fill(steel)
                .overlay(Capsule().stroke(steelDark, lineWidth: size * 0.01))
                .frame(width: size * 0.11, height: size * 0.075)
                .offset(x: -size * 0.06, y: -size * 0.08)
            // Hammer
            RoundedRectangle(cornerRadius: size * 0.01)
                .fill(steelDark)
                .frame(width: size * 0.035, height: size * 0.04)
                .rotationEffect(.degrees(25))
                .offset(x: size * 0.03, y: -size * 0.13)
            // Trigger guard
            Circle()
                .stroke(steelDark, lineWidth: size * 0.014)
                .frame(width: size * 0.06, height: size * 0.06)
                .offset(x: -size * 0.03, y: -size * 0.02)
            // Wooden grip
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(LinearGradient(colors: [wood, Color(red: 0.38, green: 0.22, blue: 0.13)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.085, height: size * 0.17)
                .rotationEffect(.degrees(-22))
                .offset(x: size * 0.025, y: size * 0.01)
        }
    }
}

// MARK: - Tanjiro Kamado: forehead scar and a black katana (grip at the center)

private struct FlameScar: Shape {
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (0.0, 0.62), (0.14, 0.36), (0.24, 0.5), (0.34, 0.08), (0.48, 0.4), (0.6, 0.0),
            (0.7, 0.34), (0.88, 0.18), (1.0, 0.56), (0.84, 0.74), (0.66, 0.7), (0.52, 1.0),
            (0.36, 0.76), (0.16, 0.86),
        ]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let c = CGPoint(x: r.minX + pt.0 * r.width, y: r.minY + pt.1 * r.height)
            if i == 0 { p.move(to: c) } else { p.addLine(to: c) }
        }
        p.closeSubpath()
        return p
    }
}

private struct Katana: View {
    let size: CGFloat

    var body: some View {
        let bladeLength = size * 0.86
        ZStack {
            // Blade (black nichirin steel with a lighter edge)
            KatanaBlade()
                .fill(LinearGradient(colors: [Color(white: 0.06), Color(white: 0.2)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(KatanaBlade().stroke(Color(white: 0.55).opacity(0.6), lineWidth: 0.6))
                .frame(width: size * 0.06, height: bladeLength)
                .offset(y: -size * 0.14 - bladeLength / 2)
            // Collar
            Rectangle()
                .fill(Color(red: 0.78, green: 0.62, blue: 0.3))
                .frame(width: size * 0.06, height: size * 0.025)
                .offset(y: -size * 0.13)
            // Guard
            Ellipse()
                .fill(Color(white: 0.1))
                .overlay(Ellipse().stroke(Color(red: 0.6, green: 0.15, blue: 0.15), lineWidth: 0.8))
                .frame(width: size * 0.15, height: size * 0.045)
                .offset(y: -size * 0.11)
            // Handle: red with black diamond wrap
            RoundedRectangle(cornerRadius: size * 0.015)
                .fill(Color(red: 0.62, green: 0.12, blue: 0.14))
                .overlay(HandleWrap().stroke(Color(white: 0.08), lineWidth: size * 0.018))
                .frame(width: size * 0.065, height: size * 0.22)
                .offset(y: size * 0.01)
            // Pommel
            Capsule()
                .fill(Color(white: 0.1))
                .frame(width: size * 0.07, height: size * 0.03)
                .offset(y: size * 0.125)
        }
    }
}

private struct KatanaBlade: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Slight curve, pointed tip at the top.
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.25, y: r.minY + r.width * 1.2),
                       control: CGPoint(x: r.minX - r.width * 0.25, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                       control: CGPoint(x: r.maxX + r.width * 0.05, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct HandleWrap: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let rows = 5
        let h = r.height / CGFloat(rows)
        for i in 0..<rows {
            let y = r.minY + CGFloat(i) * h
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y + h))
            p.move(to: CGPoint(x: r.maxX, y: y))
            p.addLine(to: CGPoint(x: r.minX, y: y + h))
        }
        return p
    }
}

// MARK: - Harry Potter: round glasses, lightning scar, wand (grip at the center)

private struct RoundGlasses: View {
    let size: CGFloat

    var body: some View {
        let lens = size * 0.3
        let eyeX = size * 0.158
        let line = size * 0.034
        let frame = Color(white: 0.1)
        ZStack {
            Circle().stroke(frame, lineWidth: line)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .frame(width: lens, height: lens)
                .offset(x: -eyeX)
            Circle().stroke(frame, lineWidth: line)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .frame(width: lens, height: lens)
                .offset(x: eyeX)
            // Bridge
            Capsule().fill(frame)
                .frame(width: size * 0.07, height: line)
                .offset(y: -lens * 0.12)
            // Arms out to the sides of the head
            Capsule().fill(frame)
                .frame(width: size * 0.2, height: line)
                .offset(x: -(eyeX + lens / 2 + size * 0.09), y: -lens * 0.12)
            Capsule().fill(frame)
                .frame(width: size * 0.2, height: line)
                .offset(x: eyeX + lens / 2 + size * 0.09, y: -lens * 0.12)
        }
    }
}

private struct Bolt: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX * 0.85, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.45))
        p.addLine(to: CGPoint(x: r.maxX * 0.8, y: r.minY + r.height * 0.52))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.15, y: r.maxY))
        return p
    }
}

private struct Wand: View {
    let size: CGFloat
    private let wood = Color(red: 0.48, green: 0.3, blue: 0.17)
    private let woodDark = Color(red: 0.34, green: 0.2, blue: 0.11)

    var body: some View {
        let length = size * 0.58
        ZStack {
            Tapered()
                .fill(LinearGradient(colors: [wood, woodDark], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.055, height: length)
                .offset(y: -length / 2 + size * 0.1)
            // Carved rings near the handle
            ForEach(0..<2, id: \.self) { i in
                Capsule().fill(woodDark)
                    .frame(width: size * 0.065, height: size * 0.02)
                    .offset(y: size * (0.04 - Double(i) * 0.045))
            }
        }
    }
}

/// Wide at the bottom, narrow at the top.
private struct Tapered: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX - r.width * 0.22, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + r.width * 0.22, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
