import SwiftUI

/// Small annotated schematics support the idea being taught; dimensions are illustrative.
struct ConceptDiagramView: View {
    let visual: LessonVisual
    let tint: Color
    var body: some View {
        VStack(spacing: 10) {
            Canvas { context, size in draw(context, size: size) }
                .frame(height: 180)
                .accessibilityLabel(caption)
            Text(caption).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(18).background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
    }
    private var caption: String {
        switch visual {
        case .circuit: "A complete loop lets current flow. Resistance limits that flow."
        case .seriesParallel: "Parallel branches connect to the same two nodes and share the same voltage."
        case .led: "The resistor limits current; the LED must face the conducting direction."
        case .forces: "Net force sets acceleration. Motion alone does not imply a net force."
        case .lever: "The same force has a larger turning effect farther from the pivot."
        case .gears: "A larger driven gear turns more slowly and produces more ideal torque."
        case .coordinates: "A position describes distance along three labeled directions."
        case .solids: "Front views of cubes: doubling every length makes the cube eight times the volume."
        case .constraints: "Leave intentional clearance so separately made parts can fit together."
        }
    }
    private func draw(_ context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        func line(_ a: CGPoint, _ b: CGPoint, color: Color = .white.opacity(0.55), width: CGFloat = 2) {
            var p = Path(); p.move(to: a); p.addLine(to: b)
            context.stroke(p, with: .color(color), lineWidth: width)
        }
        func label(_ text: String, _ x: Double, _ y: Double, color: Color = .white.opacity(0.8)) {
            context.draw(Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(color), at: point(x, y))
        }
        func arrow(_ a: CGPoint, _ b: CGPoint, color: Color) {
            line(a, b, color: color, width: 3)
            let angle = atan2(b.y - a.y, b.x - a.x)
            let left = CGPoint(x: b.x - 11 * cos(angle - .pi / 6), y: b.y - 11 * sin(angle - .pi / 6))
            let right = CGPoint(x: b.x - 11 * cos(angle + .pi / 6), y: b.y - 11 * sin(angle + .pi / 6))
            line(left, b, color: color, width: 3); line(right, b, color: color, width: 3)
        }
        func resistor(_ x: Double, _ y: Double, width: Double = 0.16) {
            let rect = CGRect(x: w * (x - width / 2), y: h * y - 10, width: w * width, height: 20)
            context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(tint.opacity(0.25)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(tint), lineWidth: 2)
        }
        switch visual {
        case .circuit, .led:
            line(point(0.18,0.3),point(0.43,0.3)); line(point(0.59,0.3),point(0.82,0.3))
            if visual == .led {
                line(point(0.82,0.3),point(0.82,0.53 - 16 / h))
                line(point(0.82,0.53 + 16 / h),point(0.82,0.77))
            } else { line(point(0.82,0.3),point(0.82,0.77)) }
            line(point(0.82,0.77),point(0.18,0.77)); line(point(0.18,0.3),point(0.18,0.47)); line(point(0.18,0.58),point(0.18,0.77))
            line(point(0.15,0.47),point(0.21,0.47),color:tint,width:3)
            line(point(0.16,0.58),point(0.20,0.58),color:tint,width:3)
            resistor(0.51,0.3)
            label("+",0.24,0.43,color:tint); label("−",0.24,0.62,color:tint); label("Voltage source",0.2,0.95); label("Resistance",0.51,0.1,color:tint)
            arrow(point(0.55,0.77),point(0.33,0.77),color:tint); label("Current",0.44,0.57,color:tint)
            if visual == .led {
                let rect = CGRect(x:w*0.82-16,y:h*0.53-16,width:32,height:32)
                context.fill(Path(ellipseIn:rect),with:.color(.red.opacity(0.55)))
                label("LED",0.92,0.53,color:.red)
            }
        case .seriesParallel:
            line(point(0.18,0.3),point(0.42,0.3)); line(point(0.58,0.3),point(0.82,0.3))
            line(point(0.18,0.7),point(0.42,0.7)); line(point(0.58,0.7),point(0.82,0.7))
            line(point(0.18,0.3),point(0.18,0.7)); line(point(0.82,0.3),point(0.82,0.7))
            arrow(point(0.03,0.5),point(0.18,0.5),color:tint)
            resistor(0.5,0.3); resistor(0.5,0.7)
            label("Branch 1",0.5,0.1,color:tint); label("Branch 2",0.5,0.94,color:tint)
            label("Node A",0.18,0.1); label("Node B",0.82,0.1)
            label("I splits",0.09,0.85)
        case .forces:
            let rect=CGRect(x:w*0.36,y:h*0.32,width:w*0.20,height:h*0.4)
            context.fill(Path(roundedRect:rect,cornerRadius:10),with:.color(tint.opacity(0.25)))
            context.stroke(Path(roundedRect:rect,cornerRadius:10),with:.color(tint),lineWidth:2)
            arrow(point(0.56,0.52),point(0.87,0.52),color:tint)
            arrow(point(0.36,0.52),point(0.22,0.52),color:.white.opacity(0.4))
            label("Smaller force",0.23,0.24); label("Larger force",0.74,0.24,color:tint)
            label("Net force → acceleration →",0.56,0.9,color:tint)
        case .lever:
            line(point(0.14,0.46),point(0.88,0.46),color:tint,width:6)
            var triangle=Path(); triangle.move(to:point(0.57,0.51)); triangle.addLine(to:point(0.52,0.76)); triangle.addLine(to:point(0.62,0.76)); triangle.closeSubpath()
            context.fill(triangle,with:.color(.white.opacity(0.35)))
            arrow(point(0.2,0.1),point(0.2,0.43),color:tint); arrow(point(0.82,0.1),point(0.82,0.43),color:.orange)
            label("Longer arm",0.35,0.91,color:tint); label("Shorter arm",0.75,0.91,color:.orange); label("Pivot",0.57,0.91)
        case .gears:
            let r:CGFloat=min(h*0.32,w*0.16),small=r/3
            let c1=point(0.37,0.52),c2=CGPoint(x:c1.x+small+r,y:c1.y)
            for (center,radius,color) in [(c1,small,tint),(c2,r,Color.orange)] {
                context.stroke(Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:radius*2,height:radius*2)),with:.color(color),lineWidth:4)
                context.fill(Path(ellipseIn:CGRect(x:center.x-4,y:center.y-4,width:8,height:8)),with:.color(color))
            }
            label("Driver",0.33,0.1,color:tint); label("Driven",0.67,0.1,color:.orange)
            label("Faster ↻",0.31,0.94,color:tint); label("Slower ↺",0.7,0.94,color:.orange)
        case .coordinates:
            let origin=point(0.43,0.7)
            arrow(origin,point(0.86,0.7),color:tint); arrow(origin,point(0.43,0.12),color:.orange); arrow(origin,point(0.20,0.93),color:.indigo)
            label("X",0.9,0.7,color:tint); label("Y",0.43,0.06,color:.orange); label("Z",0.17,0.93,color:.indigo)
            label("Origin (0, 0, 0)",0.46,0.9)
            let p=point(0.7,0.3)
            context.fill(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(.white))
            line(point(0.7,0.7),p,color:.white.opacity(0.25)); line(point(0.43,0.3),p,color:.white.opacity(0.25))
            label("Position",0.77,0.2)
        case .solids:
            for (x,side) in [(0.25,CGFloat(38)),(0.69,CGFloat(76))] {
                let rect=CGRect(x:w*x-side/2,y:h*0.5-side/2,width:side,height:side)
                context.fill(Path(roundedRect:rect,cornerRadius:5),with:.color(tint.opacity(0.25)))
                context.stroke(Path(roundedRect:rect,cornerRadius:5),with:.color(tint),lineWidth:2)
            }
            arrow(point(0.40,0.5),point(0.51,0.5),color:.white.opacity(0.5))
            label("Length ×1",0.25,0.12); label("Length ×2",0.69,0.12,color:tint)
            label("Volume ×1",0.25,0.92); label("Volume ×8",0.69,0.92,color:tint)
        case .constraints:
            let hole=CGRect(x:w*0.29,y:h*0.2,width:w*0.42,height:h*0.56)
            let insert=CGRect(x:w*0.33,y:h*0.3,width:w*0.34,height:h*0.36)
            context.stroke(Path(roundedRect:hole,cornerRadius:8),with:.color(.white.opacity(0.6)),lineWidth:7)
            context.fill(Path(roundedRect:insert,cornerRadius:5),with:.color(tint.opacity(0.35)))
            context.stroke(Path(roundedRect:insert,cornerRadius:5),with:.color(tint),lineWidth:2)
            label("Opening",0.5,0.06); label("Insert",0.5,0.48,color:tint); label("Clearance on each side",0.5,0.94,color:tint)
        }
    }
}
