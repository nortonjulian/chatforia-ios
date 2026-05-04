import SwiftUI

struct ChatBubbleShape: Shape {
    let isMe: Bool
    let groupedWithPrevious: Bool
    let groupedWithNext: Bool

    private let large: CGFloat = 18
    private let small: CGFloat = 6

    private let tailWidth: CGFloat = 5
    private let tailHeight: CGFloat = 6
    private let tailAttachLift: CGFloat = 1.5
    
    func path(in rect: CGRect) -> Path {
        let tl: CGFloat
        let tr: CGFloat
        let bl: CGFloat
        let br: CGFloat

        let showsTail = !groupedWithNext

        if isMe {
            tl = large
            tr = groupedWithPrevious ? small : large
            bl = large
            br = showsTail ? 5 : (groupedWithNext ? small : large)
        } else {
            tl = groupedWithPrevious ? small : large
            tr = large
            bl = showsTail ? 5 : (groupedWithNext ? small : large)
            br = large
        }

        let leftInset = (!isMe && showsTail) ? tailWidth : 0
        let rightInset = (isMe && showsTail) ? tailWidth : 0

        let minX = rect.minX + leftInset
        let maxX = rect.maxX - rightInset
        let minY = rect.minY
        let maxY = rect.maxY

        let p = UIBezierPath()

        p.move(to: CGPoint(x: minX + tl, y: minY))

        // top edge
        p.addLine(to: CGPoint(x: maxX - tr, y: minY))
        p.addArc(
            withCenter: CGPoint(x: maxX - tr, y: minY + tr),
            radius: tr,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )

        // right edge
        p.addLine(to: CGPoint(x: maxX, y: maxY - br))

        if isMe && showsTail {
            // Come down the right side almost to the bottom.
            p.addLine(to: CGPoint(x: maxX, y: maxY - 7.2))

            // Softer neck into the tail.
            p.addCurve(
                to: CGPoint(x: maxX + 1.05, y: maxY - 3.5),
                controlPoint1: CGPoint(x: maxX, y: maxY - 4.7),
                controlPoint2: CGPoint(x: maxX + 0.55, y: maxY - 3.95)
            )

            // Tail tip.
            p.addCurve(
                to: CGPoint(x: rect.maxX, y: maxY - tailAttachLift),
                controlPoint1: CGPoint(x: maxX + 2.45, y: maxY - 2.95),
                controlPoint2: CGPoint(x: rect.maxX - 0.35, y: maxY - 1.95)
            )

            // Softer return into the bubble bottom.
            p.addCurve(
                to: CGPoint(x: maxX - 4.0, y: maxY - 0.18),
                controlPoint1: CGPoint(x: rect.maxX - 0.25, y: maxY + 0.12),
                controlPoint2: CGPoint(x: maxX - 1.7, y: maxY + 0.02)
            )
        } else {
            p.addArc(
                withCenter: CGPoint(x: maxX - br, y: maxY - br),
                radius: br,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: true
            )
        }

        // bottom edge
        p.addLine(to: CGPoint(x: minX + bl, y: maxY))

        if !isMe && showsTail {
            // incoming bottom-left corner
            p.addArc(
                withCenter: CGPoint(x: minX + bl, y: maxY - bl),
                radius: bl,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: true
            )

            // slightly refined mirrored droplet tail
            p.addCurve(
                to: CGPoint(x: rect.minX, y: maxY - tailAttachLift),
                controlPoint1: CGPoint(x: minX - 1.0, y: maxY + 0.05),
                controlPoint2: CGPoint(x: rect.minX + 0.8, y: maxY - 1.25)
            )

            p.addCurve(
                to: CGPoint(x: minX + 3.0, y: maxY - 0.15),
                controlPoint1: CGPoint(x: rect.minX + 0.8, y: maxY + 0.45),
                controlPoint2: CGPoint(x: minX + 1.4, y: maxY + 0.12)
            )
        } else {
            p.addArc(
                withCenter: CGPoint(x: minX + bl, y: maxY - bl),
                radius: bl,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: true
            )
        }

        // left edge
        p.addLine(to: CGPoint(x: minX, y: minY + tl))
        p.addArc(
            withCenter: CGPoint(x: minX + tl, y: minY + tl),
            radius: tl,
            startAngle: .pi,
            endAngle: -.pi / 2,
            clockwise: true
        )

        p.close()
        return Path(p.cgPath)
    }
}
