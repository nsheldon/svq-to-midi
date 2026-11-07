// Generates the app icon concepts and About window art for SVQ to MIDI.
//
//   swiftc -O Design/IconArt.swift -o /tmp/iconart && /tmp/iconart "Design/Icon Concepts"
//   Design/install-icon.sh Platinum      # install a concept into the app
//
// The MC-80 is traced from "Reference Material/Roland MC-80 top.jpg" as coordinates (1600 px
// scale) in drawMC80(). Roland's logo and model lettering are deliberately left out (trademarks).
// Each concept gets an Icon Composer "AppIcon.icon" (background + foreground layers on the 1024 pt
// macOS canvas) and "about@2x.png" (560 × 200 pt banner).
import AppKit

// MARK: - Basics (y-down drawing space)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    return ctx
}

func save(_ ctx: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func roundRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
}

/// Apple-style continuous-corner rounded square approximated by a superellipse.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath()
    let n: CGFloat = 5.0
    let cx = r.midX, cy = r.midY, a = r.width / 2, b = r.height / 2
    for i in 0 ... 720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint, locations: [CGFloat]? = nil) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

// MARK: - 5×7 dot-matrix font (like the MC-80's LCD)

let glyphs: [Character: [String]] = [
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    ">": ["01000", "00100", "00010", "00001", "00010", "00100", "01000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
]

/// Draws text as round LCD dots. `dot` is the pitch of one dot.
func dotText(_ ctx: CGContext, _ text: String, at origin: CGPoint, dot: CGFloat, on: CGColor, off: CGColor?, glow: CGColor? = nil) {
    var x = origin.x
    for ch in text {
        let rows = glyphs[ch] ?? glyphs[" "]!
        for (ry, row) in rows.enumerated() {
            for (rx, bit) in row.enumerated() {
                let r = CGRect(x: x + CGFloat(rx) * dot, y: origin.y + CGFloat(ry) * dot, width: dot * 0.86, height: dot * 0.86)
                if bit == "1" {
                    ctx.saveGState()
                    if let glow { ctx.setShadow(offset: .zero, blur: dot * 1.2, color: glow) }
                    ctx.setFillColor(on)
                    ctx.fill(r)
                    ctx.restoreGState()
                } else if let off {
                    ctx.setFillColor(off)
                    ctx.fill(r)
                }
            }
        }
        x += dot * 6
    }
}

func dotTextWidth(_ text: String, dot: CGFloat) -> CGFloat { CGFloat(text.count) * dot * 6 - dot }

// MARK: - The traced MC-80 (coordinates measured from the reference photo, 1600 px scale)

struct DeviceStyle {
    var body: CGColor = color(0x3A3A3D)
    var deck: CGColor = color(0x434347)
    var front: CGColor = color(0x37373A)
    var lip: CGColor = color(0x2A2A2C)
    var slot: CGColor = color(0x101012)
    var bezel: CGColor = color(0x121214)
    var lcd: CGColor = color(0xA9CF78)
    var lcdInk: CGColor = color(0x23361A)
    var darkKey: CGColor = color(0x1C1C1E)
    var lightKey: CGColor = color(0xB9B4A2)
    var transportKey: CGColor = color(0xE6C88E)
    var recKey: CGColor = color(0xB4262E)
    var panel: CGColor = color(0x2B2B2E)
    var teal: CGColor = color(0x2E9CB5)
    var ledRed: CGColor = color(0xD8342C)
    var ledGreen: CGColor = color(0x6BCB4A)
    var dial: CGColor = color(0x161618)
    var stroke: CGColor? = nil        // outline every shape ("traced" line art)
    var strokeWidth: CGFloat = 1      // in photo units
    var fillShapes = true
    var glow: CGColor? = nil
    var keyHighlight: CGFloat = 0.18  // 0 = flat keys
    var lcdText = "SVQ>MIDI"
}

/// Draws the MC-80 into `frame`, keeping its aspect ratio. `detail`: 0 = minimal, 1 = medium, 2 = full.
func drawMC80(_ ctx: CGContext, in frame: CGRect, style s: DeviceStyle, detail: Int = 2) {
    let src = CGRect(x: 96, y: 250, width: 1408, height: 1160)
    let k = min(frame.width / src.width, frame.height / src.height)
    ctx.saveGState()
    ctx.translateBy(x: frame.midX - src.width * k / 2, y: frame.midY - src.height * k / 2)
    ctx.scaleBy(x: k, y: k)
    ctx.translateBy(x: -src.minX, y: -src.minY)
    let lw = s.strokeWidth

    func shape(_ path: CGPath, _ fill: CGColor?, stroke: Bool = true, width: CGFloat? = nil) {
        if s.fillShapes, let fill {
            ctx.addPath(path); ctx.setFillColor(fill); ctx.fillPath()
        }
        if stroke, let st = s.stroke {
            ctx.saveGState()
            if let g = s.glow { ctx.setShadow(offset: .zero, blur: 14, color: g) }
            ctx.addPath(path); ctx.setStrokeColor(st); ctx.setLineWidth(width ?? lw); ctx.setLineJoin(.round); ctx.strokePath()
            ctx.restoreGState()
        }
    }
    func key(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: CGColor, radius: CGFloat = 5) {
        let r = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        // Key shadow
        if s.fillShapes && s.keyHighlight > 0 {
            ctx.addPath(roundRect(r.offsetBy(dx: 0, dy: 4), radius)); ctx.setFillColor(color(0x000000, 0.45)); ctx.fillPath()
        }
        shape(roundRect(r, radius), fill)
        if s.fillShapes && s.keyHighlight > 0 {
            ctx.saveGState()
            ctx.addPath(roundRect(r, radius)); ctx.clip()
            ctx.setFillColor(color(0xFFFFFF, s.keyHighlight))
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.35))
            ctx.restoreGState()
        }
    }
    func led(_ cx: CGFloat, _ cy: CGFloat, _ c: CGColor) {
        let r = CGRect(x: cx - 6, y: cy - 6, width: 12, height: 12)
        ctx.saveGState()
        if s.fillShapes { ctx.setShadow(offset: .zero, blur: 10, color: c) }
        ctx.setFillColor(c); ctx.fillEllipse(in: r)
        ctx.restoreGState()
        if !s.fillShapes, let st = s.stroke { ctx.setStrokeColor(st); ctx.setLineWidth(lw * 0.6); ctx.strokeEllipse(in: r) }
    }
    func bar(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat) {
        let r = CGRect(x: x0, y: y - 7, width: x1 - x0, height: 14)
        if s.fillShapes { ctx.setFillColor(color(0x1E2A30)); ctx.fill(r) }
        ctx.setFillColor(s.teal); ctx.fill(CGRect(x: (x0 + x1) / 2 - 30, y: y - 3, width: 60, height: 6))
        if let st = s.stroke, !s.fillShapes { ctx.setStrokeColor(st); ctx.setLineWidth(lw * 0.6); ctx.stroke(r) }
    }

    // Disk lip below the front edge (two drive slots), then the body.
    shape(roundRect(CGRect(x: 168, y: 1330, width: 1268, height: 72), 10), s.lip)
    shape(roundRect(CGRect(x: 104, y: 258, width: 1392, height: 1110), 22), s.body)
    shape(roundRect(CGRect(x: 150, y: 1225, width: 1300, height: 134), 10), s.front)
    shape(roundRect(CGRect(x: 160, y: 588, width: 1280, height: 640), 14), s.deck)
    if detail >= 1 {
        shape(roundRect(CGRect(x: 184, y: 1362, width: 410, height: 28), 4), s.slot)
        shape(roundRect(CGRect(x: 1006, y: 1362, width: 416, height: 28), 4), s.slot)
    }

    // LCD
    shape(roundRect(CGRect(x: 246, y: 538, width: 752, height: 200), 8), s.bezel)
    let glass = CGRect(x: 372, y: 566, width: 510, height: 144)
    if s.fillShapes {
        ctx.saveGState()
        ctx.addPath(roundRect(glass, 4)); ctx.clip()
        linear(ctx, [s.lcd, s.lcd.copy(alpha: 0.82)!], from: CGPoint(x: 0, y: glass.minY), to: CGPoint(x: 0, y: glass.maxY))
        ctx.restoreGState()
    }
    shape(roundRect(glass, 4), nil)
    if detail >= 1, !s.lcdText.isEmpty {
        let dot: CGFloat = detail >= 2 ? 11 : 13
        let w = dotTextWidth(s.lcdText, dot: dot)
        dotText(ctx, s.lcdText, at: CGPoint(x: glass.midX - w / 2, y: glass.midY - dot * 3.5), dot: dot,
                on: s.lcdInk, off: detail >= 2 ? s.lcdInk.copy(alpha: 0.07) : nil, glow: s.glow)
    }

    // Value dial
    ctx.saveGState()
    if s.fillShapes { ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 12, color: color(0x000000, 0.6)) }
    shape(CGPath(ellipseIn: CGRect(x: 988 - 86, y: 957 - 86, width: 172, height: 172), transform: nil), s.dial)
    ctx.restoreGState()
    if s.fillShapes {
        ctx.setFillColor(color(0x2C2C30)); ctx.fillEllipse(in: CGRect(x: 960 - 24, y: 915 - 24, width: 48, height: 48))
    } else if let st = s.stroke {
        ctx.setStrokeColor(st); ctx.setLineWidth(lw * 0.7); ctx.strokeEllipse(in: CGRect(x: 960 - 24, y: 915 - 24, width: 48, height: 48))
    }

    // Transport section
    shape(roundRect(CGRect(x: 220, y: 995, width: 340, height: 212), 6), s.panel)
    let bigW: CGFloat = 84, bigH: CGFloat = 50
    key(276, 1165, bigW, bigH, s.transportKey, radius: 6)
    key(388, 1165, bigW, bigH, s.transportKey, radius: 6)
    key(500, 1165, bigW, bigH, s.recKey, radius: 6)
    if detail >= 1 {
        for x in [270, 351, 432, 514] as [CGFloat] { key(x, 1054, 62, 30, s.transportKey) }
        // Stop / play / record symbols
        let ink = s.fillShapes ? color(0x2A2418) : (s.stroke ?? color(0))
        ctx.setFillColor(ink)
        ctx.fill(CGRect(x: 276 - 11, y: 1165 - 11, width: 22, height: 22))
        let tri = CGMutablePath(); tri.move(to: CGPoint(x: 378, y: 1152)); tri.addLine(to: CGPoint(x: 404, y: 1165)); tri.addLine(to: CGPoint(x: 378, y: 1178)); tri.closeSubpath()
        ctx.addPath(tri); ctx.fillPath()
        ctx.setFillColor(s.fillShapes ? color(0xF4EEE6) : ink)
        ctx.fillEllipse(in: CGRect(x: 500 - 11, y: 1165 - 11, width: 22, height: 22))
    }

    if detail >= 1 {
        // Function row and cursor keys
        for x in [276, 412, 496, 580, 664, 748, 832, 967, 1200, 1280] as [CGFloat] { key(x, 810, 60, 30, s.darkKey) }
        for (x, y) in [(1237, 647), (1157, 690), (1318, 690), (1237, 735)] as [(CGFloat, CGFloat)] { key(x, y, 60, 30, s.darkKey) }
        // Keypad
        for y in [928, 1008, 1087] as [CGFloat] { for x in [1162, 1243, 1325] as [CGFloat] { key(x, y, 62, 30, s.darkKey) } }
        key(1165, 1165, 62, 30, s.darkKey)
        key(1330, 1165, 62, 30, s.darkKey)
        // Mode / song / repeat / shift / mark jump / tap
        for x in [271, 352, 620, 702, 782] as [CGFloat] { key(x, 958, 60, 30, s.lightKey) }
        key(620, 1054, 60, 30, s.lightKey); key(782, 1054, 60, 30, s.lightKey)
        for x in [618, 700, 782, 863] as [CGFloat] { key(x, 1165, 60, 32, s.lightKey) }
        key(989, 1165, 82, 46, s.lightKey, radius: 6)
    }

    if detail >= 2 {
        // Track and pattern keys across the top
        for y in [397, 452] as [CGFloat] {
            key(365, y, 42, 27, s.lightKey)
            for x in [450, 500, 551, 602, 652, 703, 754, 805] as [CGFloat] { key(x, y, 38, 27, s.lightKey) }
            key(887, y, 44, 27, s.lightKey)
            key(987, y, 44, 27, s.lightKey)
        }
        // Level knob
        shape(CGPath(ellipseIn: CGRect(x: 265 - 22, y: 423 - 22, width: 44, height: 44), transform: nil), s.dial)
        // Section bars and LEDs
        bar(340, 915, 344); bar(240, 390, 887); bar(590, 815, 887); bar(590, 895, 1094)
        for x in [271, 352, 620, 702, 782] as [CGFloat] { led(x, 912, s.ledRed) }
        led(620, 1008, s.ledRed); led(276, 768, s.ledRed)
        for x in [618, 700, 782, 863] as [CGFloat] { led(x, 1118, s.ledRed) }
        led(390, 1108, s.ledGreen); led(502, 1108, s.ledRed); led(515, 995, color(0x8A7A40))
        // Grille above the function keys
        if s.fillShapes {
            ctx.setFillColor(color(0x000000, 0.25))
            for x in [412, 496, 580, 664, 748, 832] as [CGFloat] {
                for i in 0 ..< 4 { ctx.fill(CGRect(x: x - 18, y: 748 + CGFloat(i) * 7, width: 36, height: 3)) }
            }
        }
    } else if detail == 0 {
        // Minimal: a hint of the key rows
        for x in stride(from: 450 as CGFloat, through: 805, by: 71) { key(x, 425, 46, 46, s.lightKey) }
        key(1240, 1000, 230, 190, s.darkKey, radius: 14)
    }
    ctx.restoreGState()
}

/// A 3.5-inch floppy disk (where SVQ files lived), drawn in a 100×100 box.
func drawFloppy(_ ctx: CGContext, in r: CGRect, body: CGColor, label: CGColor, rotation: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: r.midX, y: r.midY); ctx.rotate(by: rotation)
    let k = r.width / 100; ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -50, y: -50)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 4, y: 0)); p.addLine(to: CGPoint(x: 92, y: 0)); p.addLine(to: CGPoint(x: 100, y: 8))
    p.addLine(to: CGPoint(x: 100, y: 96)); p.addQuadCurve(to: CGPoint(x: 96, y: 100), control: CGPoint(x: 100, y: 100))
    p.addLine(to: CGPoint(x: 4, y: 100)); p.addQuadCurve(to: CGPoint(x: 0, y: 96), control: CGPoint(x: 0, y: 100))
    p.addLine(to: CGPoint(x: 0, y: 4)); p.addQuadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 0, y: 0)); p.closeSubpath()
    ctx.setShadow(offset: CGSize(width: 3, height: -3), blur: 0, color: color(0x000000, 0.55))
    ctx.addPath(p); ctx.setFillColor(body); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(p); ctx.setStrokeColor(color(0x000000)); ctx.setLineWidth(1.6); ctx.strokePath()
    // Metal shutter
    ctx.saveGState(); ctx.addRect(CGRect(x: 26, y: 0, width: 50, height: 32)); ctx.clip()
    linear(ctx, [color(0xF2F4F7), color(0x9AA0A8)], from: CGPoint(x: 26, y: 0), to: CGPoint(x: 76, y: 32)); ctx.restoreGState()
    ctx.setStrokeColor(color(0x000000)); ctx.setLineWidth(1.2); ctx.stroke(CGRect(x: 26, y: 0, width: 50, height: 32))
    ctx.setFillColor(color(0x1A1A1A)); ctx.fill(CGRect(x: 60, y: 5, width: 10, height: 22))
    // Label with "SVQ" in LCD dots
    ctx.setFillColor(label); ctx.fill(CGRect(x: 12, y: 44, width: 76, height: 52))
    ctx.setStrokeColor(color(0x000000)); ctx.stroke(CGRect(x: 12, y: 44, width: 76, height: 52))
    ctx.setFillColor(color(0x3E7CC6)); ctx.fill(CGRect(x: 12, y: 44, width: 76, height: 7))
    dotText(ctx, "SVQ", at: CGPoint(x: 21, y: 60), dot: 3.4, on: color(0x1C1C1E), off: nil)
    ctx.restoreGState()
}

// MARK: - Icon backgrounds (1990s themes)

struct Theme {
    var name: String
    var device: DeviceStyle
    var background: (CGContext, CGRect, Bool) -> Void
    var deviceShadow: CGColor? = color(0x000000, 0.5)
    var hardShadow = false
}

let icon = CGRect(x: 100, y: 100, width: 824, height: 824) // Apple's macOS icon grid on a 1024 canvas

func pinstripes(_ ctx: CGContext, _ r: CGRect, _ c: CGColor, every: CGFloat) {
    ctx.setFillColor(c)
    var y = r.minY
    while y < r.maxY { ctx.fill(CGRect(x: r.minX, y: y, width: r.width, height: every / 2)); y += every }
}

func perspectiveGrid(_ ctx: CGContext, _ r: CGRect, horizon: CGFloat, c: CGColor, lw: CGFloat) {
    ctx.setStrokeColor(c); ctx.setLineWidth(lw)
    let vp = CGPoint(x: r.midX, y: horizon)
    for i in -12 ... 12 {
        ctx.move(to: vp); ctx.addLine(to: CGPoint(x: r.midX + CGFloat(i) * r.width / 7, y: r.maxY)); ctx.strokePath()
    }
    var y = horizon + 6, step: CGFloat = 6
    while y < r.maxY { ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y)); ctx.strokePath(); step *= 1.32; y += step }
}

func memphis(_ ctx: CGContext, _ r: CGRect, scale: CGFloat) {
    // Confetti: squiggles, triangles, dots, in hot 90s colors
    func squiggle(_ x: CGFloat, _ y: CGFloat, _ c: UInt32, _ rot: CGFloat) {
        ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: rot)
        ctx.setStrokeColor(color(c)); ctx.setLineWidth(14 * scale); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.move(to: .zero)
        for i in 1 ... 4 { ctx.addLine(to: CGPoint(x: CGFloat(i) * 26 * scale, y: (i % 2 == 0 ? 0 : 22) * scale)) }
        ctx.strokePath(); ctx.restoreGState()
    }
    func triangle(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: UInt32, _ rot: CGFloat) {
        ctx.saveGState(); ctx.translateBy(x: x, y: y); ctx.rotate(by: rot)
        let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: -size)); p.addLine(to: CGPoint(x: size * 0.9, y: size * 0.6)); p.addLine(to: CGPoint(x: -size * 0.9, y: size * 0.6)); p.closeSubpath()
        ctx.addPath(p); ctx.setFillColor(color(c)); ctx.fillPath()
        ctx.addPath(p); ctx.setStrokeColor(color(0x1A1033)); ctx.setLineWidth(5 * scale); ctx.strokePath()
        ctx.restoreGState()
    }
    func dots(_ x: CGFloat, _ y: CGFloat, _ c: UInt32) {
        ctx.setFillColor(color(c))
        for i in 0 ..< 3 { for j in 0 ..< 3 { ctx.fillEllipse(in: CGRect(x: x + CGFloat(i) * 22 * scale, y: y + CGFloat(j) * 22 * scale, width: 9 * scale, height: 9 * scale)) } }
    }
    squiggle(r.minX + r.width * 0.10, r.minY + r.height * 0.12, 0xFF3EA5, -0.2)
    squiggle(r.minX + r.width * 0.66, r.minY + r.height * 0.86, 0xFFD23F, 0.15)
    triangle(r.minX + r.width * 0.84, r.minY + r.height * 0.16, 34 * scale, 0xFFD23F, 0.4)
    triangle(r.minX + r.width * 0.13, r.minY + r.height * 0.84, 28 * scale, 0x8C5CFF, -0.5)
    dots(r.minX + r.width * 0.66, r.minY + r.height * 0.07, 0x1A1033)
    dots(r.minX + r.width * 0.06, r.minY + r.height * 0.55, 0x1A1033)
    ctx.setFillColor(color(0xFF3EA5)); ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.92, y: r.minY + r.height * 0.74, width: 40 * scale, height: 40 * scale))
}

func themes() -> [Theme] {
    var platinum = DeviceStyle()
    platinum.stroke = color(0x0A0A0A); platinum.strokeWidth = 4
    // Transport keys as on a new MC-80 (the reference photo's keys have yellowed with age)
    platinum.transportKey = color(0xF3F2EE)
    let platinumTheme = Theme(name: "Platinum", device: platinum, background: { ctx, r, isIcon in
        linear(ctx, [color(0xF0F0F0), color(0xC8C8CC)], from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.maxY))
        pinstripes(ctx, r, color(0xFFFFFF, 0.35), every: r.height / 206)
        if isIcon && drawBevel {
            // Beveled inner edge, Mac OS 8 style
            let inset = r.insetBy(dx: r.width * 0.03, dy: r.height * 0.03)
            ctx.setStrokeColor(color(0xFFFFFF, 0.9)); ctx.setLineWidth(r.width * 0.006)
            ctx.addPath(squircle(inset)); ctx.strokePath()
        }
    }, deviceShadow: color(0x000000, 0.55), hardShadow: true)

    var neon = DeviceStyle()
    neon.stroke = color(0x3DF2FF); neon.strokeWidth = 7; neon.glow = color(0x00E5FF, 0.9)
    for keyPath in [\DeviceStyle.body, \.deck, \.front, \.lip, \.panel, \.bezel, \.darkKey, \.lightKey, \.dial] {
        neon[keyPath: keyPath] = color(0x140A33)
    }
    neon.slot = color(0x05020F); neon.lcd = color(0x2A0B3F)
    neon.lcdInk = color(0xFF4FD8); neon.transportKey = color(0xFFE14F); neon.recKey = color(0xFF4F7B)
    neon.keyHighlight = 0
    let neonTheme = Theme(name: "Neon Grid", device: neon, background: { ctx, r, isIcon in
        linear(ctx, [color(0x0B0630), color(0x2B0B5A), color(0x6A0F72)], from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.maxY), locations: [0, 0.6, 1])
        // Sun
        ctx.saveGState()
        let d = isIcon ? r.width * 0.42 : r.height * 0.78
        let sun = isIcon ? CGRect(x: r.midX - d / 2, y: r.minY + r.height * 0.06, width: d, height: d)
                         : CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.02, width: d, height: d)
        ctx.addEllipse(in: sun); ctx.clip()
        linear(ctx, [color(0xFFE14F), color(0xFF4FA0)], from: CGPoint(x: 0, y: sun.minY), to: CGPoint(x: 0, y: sun.maxY))
        ctx.setFillColor(color(0x2B0B5A))
        var y = sun.midY; var h = r.height * 0.008
        while y < sun.maxY { ctx.fill(CGRect(x: sun.minX, y: y, width: sun.width, height: h)); y += h * 3.2; h *= 1.25 }
        ctx.restoreGState()
        perspectiveGrid(ctx, r, horizon: r.minY + r.height * 0.62, c: color(0xFF4FD8, 0.75), lw: r.width * 0.004)
    }, deviceShadow: nil)

    var memphisStyle = DeviceStyle()
    memphisStyle.stroke = color(0x1A1033); memphisStyle.strokeWidth = 9; memphisStyle.keyHighlight = 0
    memphisStyle.body = color(0x3B3B48); memphisStyle.deck = color(0x4A4A5A); memphisStyle.lcd = color(0xB6F27A)
    memphisStyle.lightKey = color(0xD9D2F2); memphisStyle.transportKey = color(0xFFD23F); memphisStyle.recKey = color(0xFF3EA5)
    memphisStyle.teal = color(0x18D6C6)
    let memphisTheme = Theme(name: "Memphis", device: memphisStyle, background: { ctx, r, _ in
        linear(ctx, [color(0x19C6C0), color(0x0E8FA8)], from: CGPoint(x: r.minX, y: r.minY), to: CGPoint(x: r.maxX, y: r.maxY))
        memphis(ctx, r, scale: r.width / 824)
    }, deviceShadow: color(0x1A1033, 1), hardShadow: true)

    var lcd = DeviceStyle()
    lcd.lcdText = ""
    let lcdTheme = Theme(name: "Dot Matrix", device: lcd, background: { ctx, r, _ in
        linear(ctx, [color(0xC9E68E), color(0x93BE58)], from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.maxY))
    }, deviceShadow: nil)

    return [platinumTheme, neonTheme, memphisTheme, lcdTheme]
}

// MARK: - Dot-matrix rendering of the device (pixel trace)

func drawPixelDevice(_ ctx: CGContext, in frame: CGRect, cols: Int, ink: CGColor, off: CGColor) {
    // Render the traced device at low resolution, then show each pixel as an LCD dot.
    let rows = Int(CGFloat(cols) * 1160 / 1408)
    let small = makeContext(cols, rows)
    var mono = DeviceStyle()
    let white = color(0xFFFFFF), black = color(0x000000)
    mono.body = white; mono.deck = white; mono.front = white; mono.lip = white; mono.slot = black
    mono.bezel = black; mono.lcd = white; mono.lcdInk = black
    mono.darkKey = black; mono.lightKey = black; mono.transportKey = black; mono.recKey = black
    mono.panel = white; mono.teal = white; mono.ledRed = white; mono.ledGreen = white
    mono.dial = black; mono.keyHighlight = 0; mono.lcdText = ""
    mono.stroke = black; mono.strokeWidth = 1408 / CGFloat(cols) * 1.1
    small.setFillColor(color(0xFFFFFF)); small.fill(CGRect(x: 0, y: 0, width: cols, height: rows))
    drawMC80(small, in: CGRect(x: 0, y: 0, width: cols, height: rows), style: mono, detail: cols >= 40 ? 1 : 0)
    let img = small.makeImage()!
    let data = CFDataGetBytePtr(img.dataProvider!.data)!
    let bpr = img.bytesPerRow
    let pitch = min(frame.width / CGFloat(cols), frame.height / CGFloat(rows))
    let ox = frame.midX - pitch * CGFloat(cols) / 2, oy = frame.midY - pitch * CGFloat(rows) / 2
    for y in 0 ..< rows {
        for x in 0 ..< cols {
            // The context was flipped, so bitmap rows are stored bottom-up.
            let v = data[(rows - 1 - y) * bpr + x * 4]
            ctx.setFillColor(v < 128 ? ink : off)
            ctx.fill(CGRect(x: ox + CGFloat(x) * pitch, y: oy + CGFloat(y) * pitch, width: pitch * 0.84, height: pitch * 0.84))
        }
    }
}

// MARK: - Icons

var drawBevel = true

/// Draws the device (and decorations) in the 824-point icon body coordinates (`icon`).
func drawForeground(_ ctx: CGContext, _ theme: Theme, size: Int) {
    let detail = size <= 32 ? 0 : (size <= 64 ? 1 : 2)
    let inset: CGFloat = size <= 32 ? 22 : 64
    var frame = icon.insetBy(dx: inset, dy: inset * 1.6)
    if theme.name == "Neon Grid" { frame = frame.offsetBy(dx: 0, dy: size <= 32 ? 40 : 90) }
    else { frame = frame.offsetBy(dx: -8, dy: 0) }
    if theme.name == "Dot Matrix" {
        // Pixel-traced device plus "SVQ>MIDI" in big dots
        let ink = color(0x1E3311), off = color(0x1E3311, 0.06)
        if size <= 64 {
            drawPixelDevice(ctx, in: icon.insetBy(dx: 70, dy: 70), cols: size <= 32 ? 18 : 30, ink: ink, off: off)
        } else {
            drawPixelDevice(ctx, in: CGRect(x: icon.minX + 80, y: icon.minY + 70, width: icon.width - 160, height: 480), cols: 60, ink: ink, off: off)
            let text = "SVQ>MIDI"
            let dot: CGFloat = (icon.width - 150) / CGFloat(text.count * 6 - 1)
            let w = dotTextWidth(text, dot: dot)
            dotText(ctx, text, at: CGPoint(x: icon.midX - w / 2, y: icon.maxY - 70 - dot * 7), dot: dot, on: ink, off: off)
        }
    } else {
        if let sh = theme.deviceShadow {
            ctx.saveGState()
            ctx.setShadow(offset: theme.hardShadow ? CGSize(width: 22, height: -22) : CGSize(width: 0, height: -16),
                          blur: theme.hardShadow ? 0 : 30, color: sh)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawMC80(ctx, in: frame, style: theme.device, detail: detail)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        } else {
            drawMC80(ctx, in: frame, style: theme.device, detail: detail)
        }
    }
    if theme.name.hasPrefix("Platinum") && size >= 128 {
        drawFloppy(ctx, in: CGRect(x: icon.maxX - 300, y: icon.maxY - 290, width: 230, height: 230),
                   body: color(0x2B2E36), label: color(0xF6F3EA), rotation: -0.16)
    }
}

/// Writes an Icon Composer `.icon` package: a full-bleed background layer and a transparent
/// foreground layer on the 1024-point macOS icon canvas. macOS 26 applies the shape, lighting and
/// dark/tinted appearances itself; Xcode derives the older-macOS icons from it.
func writeIconComposer(_ theme: Theme, to dir: String, fill: String) {
    let assets = "\(dir)/Assets"
    try? FileManager.default.createDirectory(atPath: assets, withIntermediateDirectories: true)
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    // Map the 824-point icon body onto the whole canvas (the system masks it to the icon shape).
    func mapToCanvas(_ ctx: CGContext) {
        let k = canvas.width / icon.width
        ctx.scaleBy(x: k, y: k); ctx.translateBy(x: -icon.minX, y: -icon.minY)
    }
    let bg = makeContext(1024, 1024)
    mapToCanvas(bg)
    drawBevel = false
    theme.background(bg, icon, true)
    drawBevel = true
    save(bg, "\(assets)/background.png")
    let fg = makeContext(1024, 1024)
    // Keep the artwork inside the icon's safe area (clear of the rim the system draws).
    fg.translateBy(x: 512, y: 512); fg.scaleBy(x: 0.86, y: 0.86); fg.translateBy(x: -512, y: -512)
    mapToCanvas(fg)
    drawForeground(fg, theme, size: 1024)
    save(fg, "\(assets)/foreground.png")
    let json = """
    {
      "fill" : {
        "solid" : "\(fill)"
      },
      "groups" : [
        {
          "layers" : [
            {
              "glass" : false,
              "image-name" : "foreground.png",
              "name" : "foreground"
            }
          ],
          "shadow" : {
            "kind" : "neutral",
            "opacity" : 0.5
          },
          "translucency" : {
            "enabled" : false,
            "value" : 0.5
          }
        },
        {
          "layers" : [
            {
              "glass" : false,
              "image-name" : "background.png",
              "name" : "background"
            }
          ],
          "shadow" : {
            "kind" : "none",
            "opacity" : 0
          },
          "translucency" : {
            "enabled" : false,
            "value" : 0.5
          }
        }
      ],
      "supported-platforms" : {
        "squares" : [
          "macOS"
        ]
      }
    }
    """
    try! json.write(toFile: "\(dir)/icon.json", atomically: true, encoding: .utf8)
}


func renderIcon(_ theme: Theme, size: Int) -> CGContext {
    let ctx = makeContext(size, size)
    let s = CGFloat(size) / 1024
    ctx.scaleBy(x: s, y: s)
    // Apple template drop shadow under the icon body
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.5)) // y-flipped: negative = down
    ctx.addPath(squircle(icon)); ctx.setFillColor(color(0x808080)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle(icon)); ctx.clip()
    theme.background(ctx, icon, true)
    drawForeground(ctx, theme, size: size)
    ctx.restoreGState()
    // Subtle edge so the icon reads on any background
    ctx.addPath(squircle(icon)); ctx.setStrokeColor(color(0x000000, 0.18)); ctx.setLineWidth(2); ctx.strokePath()
    return ctx
}

// MARK: - About banner (560 × 200 pt, drawn at 2x)

func renderAbout(_ theme: Theme) -> CGContext {
    let W = 1120, H = 400
    let ctx = makeContext(W, H)
    let r = CGRect(x: 0, y: 0, width: W, height: H)
    theme.background(ctx, r, false)
    let device = CGRect(x: 40, y: 40, width: 470, height: 320)
    if theme.name == "Dot Matrix" {
        drawPixelDevice(ctx, in: device, cols: 72, ink: color(0x1E3311), off: color(0x1E3311, 0.06))
    } else if let sh = theme.deviceShadow {
        ctx.saveGState()
        ctx.setShadow(offset: theme.hardShadow ? CGSize(width: 12, height: -12) : CGSize(width: 0, height: -10), blur: theme.hardShadow ? 0 : 20, color: sh)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawMC80(ctx, in: device, style: theme.device, detail: 2)
        ctx.endTransparencyLayer(); ctx.restoreGState()
    } else {
        drawMC80(ctx, in: device, style: theme.device, detail: 2)
    }
    if theme.name.hasPrefix("Platinum") {
        drawFloppy(ctx, in: CGRect(x: 410, y: 225, width: 120, height: 120), body: color(0x2B2E36), label: color(0xF6F3EA), rotation: -0.16)
    }
    // Title in LCD dots, styled per theme
    let (ink, off, glow): (CGColor, CGColor?, CGColor?) = {
        switch theme.name {
        case "Neon Grid": return (color(0x3DF2FF), nil, color(0x00E5FF))
        case "Memphis": return (color(0x1A1033), nil, nil)
        case "Dot Matrix": return (color(0x1E3311), color(0x1E3311, 0.06), nil)
        default: return (color(0x1C1C1E), nil, nil)
        }
    }()
    dotText(ctx, "SVQ", at: CGPoint(x: 560, y: 92), dot: 22, on: ink, off: off, glow: glow)
    dotText(ctx, "TO MIDI", at: CGPoint(x: 560, y: 260), dot: 11, on: theme.name == "Neon Grid" ? color(0xFFE14F) : ink, off: off, glow: theme.name == "Neon Grid" ? color(0xFFB13F) : nil)
    return ctx
}

// MARK: - Main

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for theme in themes() {
    let dir = "\(out)/\(theme.name)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    save(renderAbout(theme), "\(dir)/about@2x.png")
    let fills = ["Platinum": "srgb:0.86000,0.86000,0.87000,1.00000", "Neon Grid": "srgb:0.11000,0.04000,0.25000,1.00000", "Memphis": "srgb:0.07000,0.70000,0.73000,1.00000", "Dot Matrix": "srgb:0.70000,0.83000,0.45000,1.00000"]
    writeIconComposer(theme, to: "\(dir)/AppIcon.icon", fill: fills[theme.name]!)
}

print("done")
