import SwiftUI

// MARK: - Pip (the interactive wrapper)

struct PipView: View {
    @ObservedObject var model: PalModel
    var size: CGFloat = 62
    @State private var pressed = false

    var body: some View {
        let snap = model.snapshot
        GeometryReader { geo in
            let frame = geo.frame(in: .named("root"))
            let center = CGPoint(x: frame.midX, y: frame.midY)
            // Redraws every frame while open; fully paused when the notch is closed.
            TimelineView(.animation(minimumInterval: nil, paused: !snap.isOpen)) { timeline in
                PipDrawing(pose: Pose.make(at: timeline.date, snap: snap, center: center), size: size)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(width: size * 1.7, height: size * 1.55)
        .contentShape(Rectangle())
        // React on mouse-down (feels snappier than waiting for release).
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    model.hit()
                }
                .onEnded { _ in pressed = false }
        )
    }
}

// MARK: - Pose: everything that changes frame to frame

enum EyeStyle { case normal, happy, squint, dizzy }

struct Pose {
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1
    var bodyOffset: CGSize = .zero
    var tilt: Angle = .zero
    var eyeOffset: CGSize = .zero
    var eyeScale: CGFloat = 1
    var blink: CGFloat = 1
    var eyeStyle: EyeStyle = .normal
    var leftArm: Angle = .degrees(25)     // 0° = hanging straight down
    var rightArm: Angle = .degrees(-25)
    var sprout: Angle = .zero
    var cheekGlow: Double = 0.35
    var spin: Double = 0
    var starsPhase: Double? = nil
}

/// A spring that starts at 1 and wobbles back to 0.
private func wobble(_ dt: Double, freq: Double, decay: Double) -> Double {
    guard dt >= 0 else { return 0 }
    return exp(-decay * dt) * cos(freq * dt)
}

extension Pose {
    static func make(at date: Date, snap: PalSnapshot, center: CGPoint) -> Pose {
        var p = Pose()
        let t = date.timeIntervalSinceReferenceDate

        // Idle: gentle breathing and a swaying sprout
        let breath = CGFloat(sin(t * 2.3)) * 0.025
        p.squashX = 1 - breath * 0.6
        p.squashY = 1 + breath
        p.sprout = .degrees(sin(t * 1.8) * 9)

        // Blink about every 4 seconds
        if t.truncatingRemainder(dividingBy: 4.3) > 4.16 { p.blink = 0.1 }

        // Eyes follow the cursor
        let dx = snap.mouse.x - center.x
        let dy = snap.mouse.y - center.y
        let dist = max(hypot(dx, dy), 0.001)
        let reach = min(dist / 140, 1) * 4.5
        p.eyeOffset = CGSize(width: dx / dist * reach, height: dy / dist * reach * 0.75)

        // Hovering right over Pip: eyes widen, cheeks glow
        if dist < 42 {
            p.eyeScale = 1.15
            p.cheekGlow = 0.75
        }

        // Pop up with a bounce when the notch opens
        let sinceOpen = date.timeIntervalSince(snap.openedAt)
        if sinceOpen < 1.2 {
            p.bodyOffset.height += CGFloat(wobble(sinceOpen, freq: 11, decay: 6)) * 20
        }

        // Wave hello
        let sinceWave = date.timeIntervalSince(snap.waveStart)
        if sinceWave >= 0 && sinceWave < 1.8 {
            let env = min(sinceWave / 0.22, 1) * min((1.8 - sinceWave) / 0.3, 1)
            let raised = -145 + sin(sinceWave * 13) * 22
            p.rightArm = .degrees(-25 + (raised + 25) * env)
            p.tilt = .degrees(sin(sinceWave * 6.5) * 4 * env)
            p.eyeStyle = .happy
        }

        // Got hit: squash & stretch, shake, arms fly out, squint
        let sinceHit = date.timeIntervalSince(snap.hitStart)
        if sinceHit >= 0 && sinceHit < 1.0 {
            let w = CGFloat(wobble(sinceHit, freq: 24, decay: 7))
            p.squashY *= 1 - 0.3 * w
            p.squashX *= 1 + 0.24 * w
            p.bodyOffset.width += CGFloat(sin(sinceHit * 60) * exp(-sinceHit * 6)) * 5
            p.tilt = .degrees(p.tilt.degrees - 9 * exp(-sinceHit * 5) * cos(sinceHit * 18))
            p.leftArm = .degrees(25 + 50 * exp(-sinceHit * 5))
            p.rightArm = .degrees(-25 - 50 * exp(-sinceHit * 5))
            p.cheekGlow = 0.95
            if sinceHit < 0.5 { p.eyeStyle = .squint }
        }

        // Dizzy (3 quick hits): spiral eyes, wobbling, stars
        if snap.mood == .dizzy {
            let s = date.timeIntervalSince(snap.dizzyStart)
            p.eyeStyle = .dizzy
            p.spin = s
            p.eyeOffset = .zero
            p.tilt = .degrees(p.tilt.degrees + sin(s * 4.5) * 11)
            p.bodyOffset.width += CGFloat(sin(s * 4.5)) * 4
            p.starsPhase = s
            p.leftArm = .degrees(25 + sin(s * 9) * 20)
            p.rightArm = .degrees(-25 + sin(s * 9 + 1) * 20)
        }

        return p
    }
}

// MARK: - Drawing

struct PipDrawing: View {
    let pose: Pose
    let size: CGFloat

    private let peachTop = Color(red: 1.00, green: 0.80, blue: 0.58)
    private let peachBottom = Color(red: 0.98, green: 0.56, blue: 0.43)
    private let armColor = Color(red: 0.99, green: 0.66, blue: 0.49)
    private let leafGreen = Color(red: 0.45, green: 0.82, blue: 0.47)
    private let ink = Color(white: 0.12)

    var body: some View {
        let bodyW = size
        let bodyH = size * 0.9

        ZStack {
            arm(pose.leftArm, side: -1, bodyW: bodyW, bodyH: bodyH)
            arm(pose.rightArm, side: 1, bodyW: bodyW, bodyH: bodyH)

            Sprout(color: leafGreen, size: size)
                .rotationEffect(pose.sprout, anchor: .bottom)
                .offset(y: -bodyH / 2 - size * 0.12 + 2)

            RoundedRectangle(cornerRadius: size * 0.4, style: .continuous)
                .fill(LinearGradient(colors: [peachTop, peachBottom], startPoint: .top, endPoint: .bottom))
                .frame(width: bodyW, height: bodyH)
                .overlay(alignment: .topLeading) {
                    Ellipse()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: size * 0.22, height: size * 0.11)
                        .rotationEffect(.degrees(-22))
                        .offset(x: size * 0.13, y: size * 0.09)
                }

            face
            stars
        }
        .scaleEffect(x: pose.squashX, y: pose.squashY, anchor: .bottom)
        .rotationEffect(pose.tilt, anchor: .bottom)
        .offset(pose.bodyOffset)
    }

    // Arms hang from the shoulders, tucked behind the body.
    private func arm(_ angle: Angle, side: CGFloat, bodyW: CGFloat, bodyH: CGFloat) -> some View {
        let length = size * 0.3
        return Capsule()
            .fill(armColor)
            .frame(width: size * 0.16, height: length)
            .rotationEffect(angle, anchor: .top)
            .offset(x: side * bodyW * 0.42, y: bodyH * 0.06 + length / 2)
    }

    private var face: some View {
        ZStack {
            HStack(spacing: size * 0.44) { cheek; cheek }
                .offset(y: size * 0.1)
            mouth
                .offset(y: size * 0.12)
            HStack(spacing: size * 0.1) {
                eye(left: true)
                eye(left: false)
            }
            .offset(x: pose.eyeOffset.width, y: -size * 0.04 + pose.eyeOffset.height)
        }
        // The whole face shifts a little too, so Pip seems to turn toward you.
        .offset(x: pose.eyeOffset.width * 0.4, y: pose.eyeOffset.height * 0.4)
    }

    private var cheek: some View {
        Ellipse()
            .fill(Color(red: 1, green: 0.42, blue: 0.5).opacity(pose.cheekGlow))
            .frame(width: size * 0.15, height: size * 0.08)
    }

    @ViewBuilder
    private func eye(left: Bool) -> some View {
        let w = size * 0.12
        let h = size * 0.18
        let line = StrokeStyle(lineWidth: size * 0.05, lineCap: .round, lineJoin: .round)
        Group {
            switch pose.eyeStyle {
            case .normal:
                Capsule()
                    .fill(ink)
                    .frame(width: w, height: h)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(Color.white)
                            .frame(width: w * 0.42, height: w * 0.42)
                            .offset(x: -w * 0.1, y: h * 0.14)
                    }
                    .scaleEffect(x: pose.eyeScale, y: pose.eyeScale * pose.blink)
            case .happy:
                ArcUp().stroke(ink, style: line)
                    .frame(width: w * 1.4, height: h * 0.45)
            case .squint:
                Chevron(pointsRight: left).stroke(ink, style: line)
                    .frame(width: w * 1.1, height: h * 0.75)
            case .dizzy:
                Spiral().stroke(ink, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .frame(width: w * 1.6, height: w * 1.6)
                    .rotationEffect(.radians(pose.spin * 7 * (left ? 1 : -1)))
            }
        }
        .frame(width: w * 1.8, height: h * 1.3)
    }

    @ViewBuilder
    private var mouth: some View {
        switch pose.eyeStyle {
        case .squint:
            Ellipse().fill(ink)
                .frame(width: size * 0.09, height: size * 0.11)
        case .dizzy:
            Wave().stroke(ink, style: StrokeStyle(lineWidth: size * 0.03, lineCap: .round))
                .frame(width: size * 0.2, height: size * 0.05)
        case .happy:
            ArcDown().stroke(ink, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.14, height: size * 0.07)
        case .normal:
            ArcDown().stroke(ink, style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                .frame(width: size * 0.12, height: size * 0.04)
        }
    }

    @ViewBuilder
    private var stars: some View {
        if let phase = pose.starsPhase {
            ForEach(0..<3, id: \.self) { i in
                let a = phase * 4 + Double(i) * 2 * Double.pi / 3
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.3))
                    .offset(x: CGFloat(cos(a)) * size * 0.42,
                            y: -size * 0.58 + CGFloat(sin(a)) * size * 0.1)
                    .opacity(sin(a) < 0 ? 0.5 : 1)
            }
        }
    }
}

// MARK: - Little shapes

struct Sprout: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(color)
                .frame(width: max(2.5, size * 0.045), height: size * 0.16)
            Ellipse().fill(color)
                .frame(width: size * 0.2, height: size * 0.1)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.08, y: -size * 0.13)
            Ellipse().fill(color.opacity(0.9))
                .frame(width: size * 0.17, height: size * 0.09)
                .rotationEffect(.degrees(28))
                .offset(x: size * 0.075, y: -size * 0.15)
        }
        .frame(width: size * 0.44, height: size * 0.24, alignment: .bottom)
    }
}

/// "^" — happy closed eye
struct ArcUp: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                       control: CGPoint(x: r.midX, y: r.minY - r.height))
        return p
    }
}

/// Smile
struct ArcDown: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY),
                       control: CGPoint(x: r.midX, y: r.maxY + r.height))
        return p
    }
}

/// ">" or "<" — squeezed-shut eye
struct Chevron: Shape {
    let pointsRight: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        let backX = pointsRight ? r.minX : r.maxX
        let tipX = pointsRight ? r.maxX : r.minX
        p.move(to: CGPoint(x: backX, y: r.minY))
        p.addLine(to: CGPoint(x: tipX, y: r.midY))
        p.addLine(to: CGPoint(x: backX, y: r.maxY))
        return p
    }
}

/// Swirly dizzy eye
struct Spiral: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let maxR = min(r.width, r.height) / 2
        let steps = 60
        for i in 0...steps {
            let f = Double(i) / Double(steps)
            let a = f * 2.2 * 2 * Double.pi
            let rad = maxR * CGFloat(f)
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// Wobbly dizzy mouth
struct Wave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let steps = 24
        for i in 0...steps {
            let f = CGFloat(i) / CGFloat(steps)
            let pt = CGPoint(x: r.minX + f * r.width,
                             y: r.midY + CGFloat(sin(Double(f) * 2 * Double.pi * 2)) * r.height / 2)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
