import SwiftUI

// MARK: - Drag, fling and petting
// A plain class (not observed): PipView's TimelineView steps it once per frame while the
// notch is open, and reads Pip's offset, extra pose tweaks and hearts back out of it.
// Positions are in the "notch" coordinate space (top-left of the open notch).

final class PipMotion {
    enum Event { case bump, dizzy, petted }

    struct Heart: Identifiable {
        let id = UUID()
        let born: Date
        let x: CGFloat
        let size: CGFloat
    }

    // Tuning
    private let springK: CGFloat = 40        // pull back to Pip's spot
    private let damping: CGFloat = 4         // air friction
    private let flyingSpringK: CGFloat = 6   // weaker while thrown, so Pip ricochets around first
    private let flyingDamping: CGFloat = 0.9
    private let bounciness: CGFloat = 0.75   // speed kept after hitting a wall
    private let flingSpeed: CGFloat = 500    // release faster than this = a throw
    private let bumpSpeed: CGFloat = 300     // wall hits harder than this make Pip squash
    private let bouncesToDizzy = 2

    // Fling state
    private(set) var isHeld = false
    private var pos: CGPoint?                // Pip's center while away from its spot; nil = at rest
    private var vel = CGVector.zero
    private var dragPoint = CGPoint.zero
    private var grabDelta = CGSize.zero
    private var dragVel = CGVector.zero
    private var lastDrag: (point: CGPoint, time: Date)?
    private var flying = false
    private var bounces = 0
    private var lastBump = Date.distantPast
    private var rest = CGPoint.zero

    // Petting state
    private var petLevel: Double = 0         // seconds of recent stroking
    private var earned = false               // petted long enough to get a reaction
    private var lastStroke = Date.distantPast
    private var lastMouse: CGPoint?
    private var mouseSpeed: CGFloat = 0
    private(set) var hearts: [Heart] = []
    private var lastHeart = Date.distantPast

    private var lastStep: Date?

    var center: CGPoint { pos ?? rest }
    var offset: CGSize { pos.map { CGSize(width: $0.x - rest.x, height: $0.y - rest.y) } ?? .zero }
    var isPetting: Bool { petLevel > 0.4 }

    // MARK: Dragging (called from the gesture)

    func beginDrag(at point: CGPoint) {
        let c = center
        isHeld = true
        flying = false
        pos = c
        vel = .zero
        dragVel = .zero
        grabDelta = CGSize(width: point.x - c.x, height: point.y - c.y)
        dragPoint = point
        lastDrag = (point, Date())
        petLevel = 0
    }

    func drag(to point: CGPoint) {
        let now = Date()
        if let last = lastDrag {
            let dt = now.timeIntervalSince(last.time)
            if dt > 0.001 {
                let v = CGVector(dx: (point.x - last.point.x) / dt, dy: (point.y - last.point.y) / dt)
                dragVel = CGVector(dx: dragVel.dx * 0.4 + v.dx * 0.6, dy: dragVel.dy * 0.4 + v.dy * 0.6)
            }
        }
        lastDrag = (point, now)
        dragPoint = point
    }

    /// Returns true if Pip was thrown (rather than just put down).
    func endDrag() -> Bool {
        isHeld = false
        // Held still before letting go: that's a drop, not a throw.
        let stale = lastDrag.map { Date().timeIntervalSince($0.time) > 0.08 } ?? true
        var v = stale ? .zero : dragVel
        let speed = hypot(v.dx, v.dy)
        if speed > 2600 { v = CGVector(dx: v.dx / speed * 2600, dy: v.dy / speed * 2600) }
        vel = v
        flying = speed > flingSpeed
        bounces = 0
        return flying
    }

    // MARK: Every frame

    /// Moves Pip one frame. `bounds` is where Pip's center may go; `mouse` is in notch space.
    func step(date: Date, rest: CGPoint, bounds: CGRect, mouse: CGPoint) -> [Event] {
        var dt = lastStep.map { date.timeIntervalSince($0) } ?? 0
        lastStep = date
        if dt > 0.25 { reset(); dt = 0 }         // the notch was closed in between
        guard dt > 0 else { self.rest = rest; return [] }
        dt = min(dt, 1.0 / 30)
        self.rest = rest

        var events: [Event] = []
        if isHeld {
            pos = clamp(CGPoint(x: dragPoint.x - grabDelta.width, y: dragPoint.y - grabDelta.height), to: bounds)
            // Stop the "swing" when the mouse stops.
            let fade = max(0, 1 - CGFloat(dt) * 6)
            dragVel = CGVector(dx: dragVel.dx * fade, dy: dragVel.dy * fade)
        } else if var p = pos {
            let steps = 3
            let h = CGFloat(dt) / CGFloat(steps)
            let k = flying ? flyingSpringK : springK
            let c = flying ? flyingDamping : damping
            for _ in 0..<steps {
                vel.dx += (-k * (p.x - rest.x) - c * vel.dx) * h
                vel.dy += (-k * (p.y - rest.y) - c * vel.dy) * h
                p.x += vel.dx * h
                p.y += vel.dy * h

                if p.x < bounds.minX { p.x = bounds.minX; hitWall(&vel.dx, date, &events) }
                if p.x > bounds.maxX { p.x = bounds.maxX; hitWall(&vel.dx, date, &events) }
                if p.y < bounds.minY { p.y = bounds.minY; hitWall(&vel.dy, date, &events) }
                if p.y > bounds.maxY { p.y = bounds.maxY; hitWall(&vel.dy, date, &events) }
            }
            let speed = hypot(vel.dx, vel.dy)
            if speed < 150 { flying = false }
            if hypot(p.x - rest.x, p.y - rest.y) < 0.6 && speed < 8 {
                pos = nil
                vel = .zero
            } else {
                pos = p
            }
        }

        stepPetting(date: date, dt: dt, mouse: mouse, events: &events)
        return events
    }

    private func hitWall(_ v: inout CGFloat, _ date: Date, _ events: inout [Event]) {
        let impact = abs(v)
        v = -v * bounciness
        guard impact > bumpSpeed, date.timeIntervalSince(lastBump) > 0.12 else { return }
        lastBump = date
        events.append(.bump)
        guard flying else { return }
        bounces += 1
        if bounces == bouncesToDizzy { events.append(.dizzy) }
    }

    private func stepPetting(date: Date, dt: Double, mouse: CGPoint, events: inout [Event]) {
        if let last = lastMouse {
            let s = hypot(mouse.x - last.x, mouse.y - last.y) / CGFloat(dt)
            mouseSpeed = mouseSpeed * 0.85 + s * 0.15
        }
        lastMouse = mouse

        // Slow strokes right over Pip. Too fast is just the mouse passing by.
        let c = center
        let near = hypot(mouse.x - c.x, mouse.y - c.y) < 44
        let stroking = !isHeld && pos == nil && near && mouseSpeed > 20 && mouseSpeed < 450
        petLevel = stroking ? min(petLevel + dt, 3) : max(petLevel - dt * 0.8, 0)
        if stroking { lastStroke = date }

        // Pip reacts once you stop, so the speech bubble doesn't slide Pip out from under your hand.
        // Only while actually stroking, so the fade-out afterwards can't re-trigger it every frame.
        if stroking && petLevel > 1.0 { earned = true }
        if earned && date.timeIntervalSince(lastStroke) > 0.5 {
            earned = false
            events.append(.petted)
        }

        if isPetting && date.timeIntervalSince(lastHeart) > 0.3 {
            lastHeart = date
            hearts.append(Heart(born: date, x: .random(in: -20...20), size: .random(in: 9...13)))
        }
        hearts.removeAll { date.timeIntervalSince($0.born) > 1.4 }
    }

    private func reset() {
        isHeld = false
        pos = nil
        vel = .zero
        flying = false
        petLevel = 0
        earned = false
        lastMouse = nil
        mouseSpeed = 0
        hearts.removeAll()
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    // MARK: Pose tweaks

    /// `upset`: poked recently and not forgiven yet.
    func decorate(_ p: inout Pose, at date: Date, upset: Bool) {
        let t = date.timeIntervalSinceReferenceDate
        if isHeld {
            // Dangling: swings against the direction you drag, arms flailing, eyes wide.
            p.tilt = .degrees(Double(max(-28, min(28, -dragVel.dx * 0.012))))
            p.leftArm = .degrees(150 + sin(t * 18) * 14)
            p.rightArm = .degrees(-150 - sin(t * 18 + 1) * 14)
            p.eyeScale = 1.25
            p.cheekGlow = 0.85
            p.squashY *= 1.06
            p.squashX *= 0.95
        } else if flying {
            p.tilt = .degrees(p.tilt.degrees + Double(max(-30, min(30, vel.dx * 0.015))))
            p.leftArm = .degrees(120 + sin(t * 25) * 25)
            p.rightArm = .degrees(-120 - sin(t * 25) * 25)
            if p.eyeStyle == .normal { p.eyeStyle = .squint }
        }

        if isPetting && !isHeld && upset {
            // Still a bit grumpy: puts up with it. Half-closed eyes, flat "—" mouth.
            p.eyeStyle = .normal
            p.blink = min(p.blink, 0.55)
            p.eyeScale = 1
            p.flatMouth = true
            p.cheekGlow = 0.6
        } else if isPetting && !isHeld {
            p.eyeStyle = .happy
            p.cheekGlow = 1
            p.tilt = .degrees(p.tilt.degrees + sin(t * 3) * 3)   // leans into your hand
            p.sprout = .degrees(sin(t * 7) * 14)
        }
    }
}
