// Renders Pip into a 1024×1024 PNG for the app icon.
// Compiled together with the app's sources by build-app.sh — not part of the app itself.
import SwiftUI
import AppKit

struct IconView: View {
    var body: some View {
        var pose = Pose()
        pose.eyeStyle = .happy
        pose.leftArm = .degrees(150)      // waving
        pose.rightArm = .degrees(-35)
        pose.sprout = .degrees(-8)
        pose.cheekGlow = 0.6

        return ZStack {
            // macOS icon grid: 824pt rounded square inside a 1024 canvas.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            PipDrawing(pose: pose, size: 430)
                .frame(width: 730, height: 670)
                .offset(y: 30)
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
struct MakeIcon {
    @MainActor static func main() {
        let renderer = ImageRenderer(content: IconView())
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            fatalError("Couldn't render the icon")
        }
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
