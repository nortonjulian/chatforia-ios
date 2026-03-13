import SwiftUI

struct ChatBubbleShape: Shape {
    let isMe: Bool
    let groupedWithPrevious: Bool
    let groupedWithNext: Bool

    private let large: CGFloat = 18
    private let small: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let tl: CGFloat
        let tr: CGFloat
        let bl: CGFloat
        let br: CGFloat

        if isMe {
            tl = large
            bl = large
            tr = groupedWithPrevious ? small : large
            br = groupedWithNext ? small : large
        } else {
            tr = large
            br = large
            tl = groupedWithPrevious ? small : large
            bl = groupedWithNext ? small : large
        }

        let bezier = UIBezierPath()
        bezier.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))

        bezier.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        bezier.addArc(
            withCenter: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )

        bezier.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        bezier.addArc(
            withCenter: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )

        bezier.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        bezier.addArc(
            withCenter: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )

        bezier.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        bezier.addArc(
            withCenter: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
            radius: tl,
            startAngle: .pi,
            endAngle: -.pi / 2,
            clockwise: true
        )

        bezier.close()

        return Path(bezier.cgPath)
    }
}
