import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A resolution-independent poster, painted entirely with type and geometry.
/// Neither the renderer nor its texture depends on randomness, UUIDs, or the clock.
enum WallpaperRenderer {
    enum RenderError: LocalizedError {
        case invalidSize, bitmapCreationFailed, imageEncodingFailed
        var errorDescription: String? {
            switch self {
            case .invalidSize: "배경화면 크기가 올바르지 않습니다."
            case .bitmapCreationFailed: "배경화면을 그릴 공간을 만들지 못했습니다."
            case .imageEncodingFailed: "PNG 이미지로 저장하지 못했습니다."
            }
        }
    }

    static func render(entries: [ScheduleEntry], configuration: WallpaperConfiguration, size: CGSize? = nil) throws -> NSImage {
        let image = try makeImage(entries: entries, configuration: configuration, size: size)
        return NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
    }

    static func pngData(entries: [ScheduleEntry], configuration: WallpaperConfiguration, size: CGSize? = nil) throws -> Data {
        let image = try makeImage(entries: entries, configuration: configuration, size: size)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.imageEncodingFailed }
        return data as Data
    }

    private static func makeImage(entries: [ScheduleEntry], configuration: WallpaperConfiguration, size: CGSize?) throws -> CGImage {
        let requested = size ?? configuration.resolution.size
        guard requested.width.isFinite, requested.height.isFinite,
              requested.width >= 160, requested.height >= 100,
              requested.width <= 8192, requested.height <= 8192 else { throw RenderError.invalidSize }
        let width = Int(requested.width.rounded()), height = Int(requested.height.rounded())
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw RenderError.bitmapCreationFailed
        }
        let scale = CGFloat(width) / 1512
        let canvas = CGSize(width: 1512, height: CGFloat(height) / scale)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let painter = Painter(context: context, size: canvas, configuration: configuration)
        painter.draw(entries: entries.filter { $0.validationError == nil }.sorted(by: stableOrder))
        guard let image = context.makeImage() else { throw RenderError.bitmapCreationFailed }
        return image
    }

    private static func stableOrder(_ lhs: ScheduleEntry, _ rhs: ScheduleEntry) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        if lhs.startMinutes != rhs.startMinutes { return lhs.startMinutes < rhs.startMinutes }
        if lhs.endMinutes != rhs.endMinutes { return lhs.endMinutes < rhs.endMinutes }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.location < rhs.location
    }

    private struct Palette {
        let base: NSColor
        let deep: NSColor
        let glow: NSColor
        let light: NSColor
        let ink: NSColor

        init(_ theme: WallpaperTheme) {
            switch theme {
            case .ember:
                base = Self.rgb(0xB83816); deep = Self.rgb(0x5A170E)
                glow = Self.rgb(0xFF861F); light = Self.rgb(0xFBA677); ink = Self.rgb(0xFFF0D1)
            case .moss:
                base = Self.rgb(0x3C4931); deep = Self.rgb(0x142B25)
                glow = Self.rgb(0x9B9C55); light = Self.rgb(0xA2AC83); ink = Self.rgb(0xF4EED6)
            case .midnight:
                base = Self.rgb(0x142857); deep = Self.rgb(0x070F2C)
                glow = Self.rgb(0x386BB9); light = Self.rgb(0x718FB8); ink = Self.rgb(0xE7EDFF)
            }
        }

        private static func rgb(_ hex: Int) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }

    struct PositionedEntry {
        var entry: ScheduleEntry
        var lane: Int
        var laneCount: Int
    }

    /// Partition every connected group of overlapping classes into independent lanes.
    static func positioned(_ entries: [ScheduleEntry]) -> [PositionedEntry] {
        var result: [PositionedEntry] = []
        var group: [ScheduleEntry] = []
        var groupEnd = -1
        func appendGroup() {
            var laneEnds: [Int] = []
            var placed: [PositionedEntry] = []
            for entry in group {
                let lane = laneEnds.firstIndex(where: { $0 <= entry.startMinutes }) ?? laneEnds.count
                if lane == laneEnds.count { laneEnds.append(entry.endMinutes) }
                else { laneEnds[lane] = entry.endMinutes }
                placed.append(PositionedEntry(entry: entry, lane: lane, laneCount: 0))
            }
            result.append(contentsOf: placed.map { PositionedEntry(entry: $0.entry, lane: $0.lane, laneCount: laneEnds.count) })
        }
        for entry in entries.sorted(by: stableOrder) {
            if entry.startMinutes >= groupEnd, !group.isEmpty {
                appendGroup()
                group.removeAll(keepingCapacity: true)
                groupEnd = -1
            }
            group.append(entry)
            groupEnd = max(groupEnd, entry.endMinutes)
        }
        if !group.isEmpty { appendGroup() }
        return result
    }

    private final class Painter {
        let context: CGContext
        let size: CGSize
        let configuration: WallpaperConfiguration
        let palette: Palette
        var ink: NSColor { palette.ink }

        init(context: CGContext, size: CGSize, configuration: WallpaperConfiguration) {
            self.context = context
            self.size = size
            self.configuration = configuration
            palette = Palette(configuration.theme)
        }

        func draw(entries: [ScheduleEntry]) {
            background()
            let frame = CGRect(x: 84, y: 64, width: size.width - 168, height: size.height - 174)
            let dividerY = min(max(size.height * 0.345, 250), 352)
            stroke(frame, color: ink.withAlphaComponent(0.49), width: 0.8)
            line(CGPoint(x: frame.minX, y: dividerY), CGPoint(x: frame.maxX, y: dividerY), alpha: 0.46)
            cornerMarks(frame)
            header(frame: frame, dividerY: dividerY)
            timetable(entries: entries, frame: frame, dividerY: dividerY)

            text("WEEKLY RHYTHM", in: CGRect(x: frame.minX, y: frame.maxY + 17, width: 300, height: 17),
                 font: mono(10), color: ink.withAlphaComponent(0.72), tracking: 2.4)
            text("A PLACE FOR YOUR TIME.", in: CGRect(x: frame.maxX - 330, y: frame.maxY + 17, width: 330, height: 17),
                 font: mono(10), color: ink.withAlphaComponent(0.72), alignment: .right, tracking: 1.8)
        }

        private func background() {
            fill(CGRect(origin: .zero, size: size), color: palette.base)
            gradient(colors: [palette.deep, palette.base, palette.glow], locations: [0, 0.53, 1],
                     from: CGPoint(x: 0, y: size.height), to: CGPoint(x: size.width, y: 0))
            radial(center: CGPoint(x: size.width * 0.32, y: size.height * 0.18), radius: size.width * 0.43,
                   color: palette.light, opacity: 0.80)
            radial(center: CGPoint(x: size.width * 0.89, y: size.height * 0.60), radius: size.width * 0.43,
                   color: palette.glow, opacity: 0.81)
            radial(center: CGPoint(x: size.width * 0.05, y: size.height * 0.90), radius: size.width * 0.49,
                   color: palette.deep, opacity: 0.9)
            radial(center: CGPoint(x: size.width * 0.66, y: size.height * 0.46), radius: size.width * 0.25,
                   color: palette.deep, opacity: 0.6)

            // A blurred, elliptical fold gives the color field depth without a bitmap asset.
            context.saveGState()
            context.translateBy(x: size.width * 0.33, y: size.height * 0.53)
            context.rotate(by: -0.28)
            context.scaleBy(x: 1, y: 0.45)
            radial(center: .zero, radius: 590, color: palette.deep, opacity: 0.66)
            context.restoreGState()

            // Subordinate drafting-paper lines continue behind the timetable.
            context.saveGState()
            context.clip(to: CGRect(x: 84, y: 64, width: size.width - 168, height: size.height - 174))
            for x in stride(from: CGFloat(84), through: size.width - 84, by: 19.2) {
                line(CGPoint(x: x, y: 64), CGPoint(x: x, y: size.height - 110), alpha: 0.033, width: 0.55)
            }
            for y in stride(from: CGFloat(64), through: size.height - 110, by: 19.2) {
                line(CGPoint(x: 84, y: y), CGPoint(x: size.width - 84, y: y), alpha: 0.033, width: 0.55)
            }
            context.restoreGState()
            if configuration.showTexture { texture() }
        }

        private func header(frame: CGRect, dividerY: CGFloat) {
            let padding: CGFloat = 30
            text(configuration.subtitle.uppercased(), in: CGRect(x: frame.minX + padding, y: frame.minY + 24, width: frame.width * 0.69, height: 22),
                 font: mono(11), color: ink.withAlphaComponent(0.88), tracking: 2.4)

            let titleRect = CGRect(x: frame.minX + padding - 2, y: frame.minY + 64,
                                   width: frame.width * 0.65, height: dividerY - frame.minY - 83)
            let title = configuration.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = title.isEmpty ? "Make room\nfor what matters." : title
            let maxSize: CGFloat = min(72, titleRect.height / 2.03)
            var pointSize = maxSize
            while pointSize > 27 {
                let bounds = attributed(displayTitle, font: serif(pointSize), color: ink, lineSpacing: -2)
                    .boundingRect(with: CGSize(width: titleRect.width, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading])
                if bounds.height <= titleRect.height { break }
                pointSize -= 1
            }
            text(displayTitle, in: titleRect, font: serif(pointSize), color: ink, lineSpacing: -2)

            let diagram = CGRect(x: frame.maxX - 314, y: frame.minY + 31, width: 266, height: dividerY - frame.minY - 61)
            geometricStudy(in: diagram)
            text("01 / TIME, WELL SPENT", in: CGRect(x: diagram.minX, y: diagram.minY, width: diagram.width, height: 17),
                 font: mono(10), color: ink.withAlphaComponent(0.81), tracking: 1.3)
            text("A LITTLE STRUCTURE.\nA LOT OF POSSIBILITY.",
                 in: CGRect(x: diagram.minX, y: diagram.maxY - 31, width: diagram.width, height: 34),
                 font: mono(9), color: ink.withAlphaComponent(0.68), alignment: .right, tracking: 1.5, lineSpacing: 4)
        }

        private func geometricStudy(in rect: CGRect) {
            let center = CGPoint(x: rect.midX, y: rect.midY + 4)
            let radius = min(rect.height * 0.34, 73)
            context.saveGState()
            context.setStrokeColor(ink.withAlphaComponent(0.29).cgColor)
            context.setLineWidth(0.75)
            context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.strokeEllipse(in: CGRect(x: center.x - radius * 0.73, y: center.y - radius, width: radius * 1.46, height: radius * 2))
            context.strokeEllipse(in: CGRect(x: center.x - radius * 0.30, y: center.y - radius, width: radius * 0.6, height: radius * 2))
            line(CGPoint(x: center.x - radius - 18, y: center.y), CGPoint(x: center.x + radius + 18, y: center.y), alpha: 0.35)
            line(CGPoint(x: center.x, y: center.y - radius - 10), CGPoint(x: center.x, y: center.y + radius + 10), alpha: 0.35)
            line(CGPoint(x: center.x - radius - 27, y: center.y + radius * 0.8),
                 CGPoint(x: center.x + radius + 27, y: center.y - radius * 0.8), alpha: 0.7)
            fill(CGRect(x: center.x + radius * 0.80 - 2, y: center.y - radius * 0.62 - 2, width: 4, height: 4), color: ink)
            context.restoreGState()
        }

        private func timetable(entries: [ScheduleEntry], frame: CGRect, dividerY: CGFloat) {
            let dayCount = configuration.showWeekends || entries.contains(where: { $0.day >= 5 }) ? 7 : 5
            var firstHour = min(23, max(0, configuration.startHour))
            var lastHour = min(24, max(firstHour + 1, configuration.endHour))
            if let first = entries.map(\.startMinutes).min() { firstHour = min(firstHour, first / 60) }
            if let last = entries.map(\.endMinutes).max() { lastHour = max(lastHour, Int(ceil(Double(last) / 60))) }
            let grid = CGRect(x: frame.minX + 63, y: dividerY + 61, width: frame.width - 89,
                              height: max(70, frame.maxY - dividerY - 107))
            let dayWidth = grid.width / CGFloat(dayCount)
            let hourHeight = grid.height / CGFloat(lastHour - firstHour)
            let minuteHeight = hourHeight / 60

            text("HOUR", in: CGRect(x: frame.minX + 9, y: dividerY + 26, width: 47, height: 12),
                 font: mono(7.5), color: ink.withAlphaComponent(0.52))
            for day in 0..<dayCount {
                let dayX = grid.minX + CGFloat(day) * dayWidth
                text(ScheduleEntry.dayLabels[day], in: CGRect(x: dayX + 11, y: dividerY + 25, width: dayWidth - 22, height: 22),
                     font: mono(12), color: ink.withAlphaComponent(0.93), tracking: 2.2)
                text(String(format: "%02d", day + 1), in: CGRect(x: dayX + dayWidth - 49, y: dividerY + 27, width: 35, height: 15),
                     font: mono(9), color: ink.withAlphaComponent(0.43), alignment: .right)
            }

            for halfHour in 0...((lastHour - firstHour) * 2) {
                let y = grid.minY + CGFloat(halfHour) * hourHeight / 2
                let isHour = halfHour.isMultiple(of: 2)
                line(CGPoint(x: grid.minX, y: y), CGPoint(x: grid.maxX, y: y), alpha: isHour ? 0.32 : 0.12, width: isHour ? 0.8 : 0.5)
                if isHour {
                    let hour = firstHour + halfHour / 2
                    text(String(format: "%02d", hour), in: CGRect(x: frame.minX + 15, y: y - 7, width: 35, height: 16),
                         font: mono(10), color: ink.withAlphaComponent(0.72), alignment: .right)
                    line(CGPoint(x: grid.minX - 5, y: y), CGPoint(x: grid.minX, y: y), alpha: 0.5)
                }
            }
            for day in 0...dayCount {
                let x = grid.minX + CGFloat(day) * dayWidth
                line(CGPoint(x: x, y: dividerY + 16), CGPoint(x: x, y: grid.maxY), alpha: 0.35)
            }

            for day in 0..<dayCount {
                for item in WallpaperRenderer.positioned(entries.filter { $0.day == day }) {
                    let laneWidth = dayWidth / CGFloat(item.laneCount)
                    let event = CGRect(x: grid.minX + CGFloat(day) * dayWidth + CGFloat(item.lane) * laneWidth + 3,
                                       y: grid.minY + CGFloat(item.entry.startMinutes - firstHour * 60) * minuteHeight + 2,
                                       width: laneWidth - 6,
                                       height: max(2, CGFloat(item.entry.endMinutes - item.entry.startMinutes) * minuteHeight - 4))
                    course(item.entry, in: event)
                }
            }

            if entries.isEmpty {
                let label = CGRect(x: grid.midX - 213, y: grid.midY - 39, width: 426, height: 79)
                fill(label, color: palette.deep.withAlphaComponent(0.85))
                stroke(label, color: ink.withAlphaComponent(0.4), width: 0.7)
                text("Room for a new rhythm.", in: label.insetBy(dx: 20, dy: 20), font: serif(28), color: ink, alignment: .center)
            }

            text("PLAN WITH PURPOSE. LEAVE ROOM TO PLAY.",
                 in: CGRect(x: grid.minX, y: frame.maxY - 26, width: grid.width * 0.75, height: 15),
                 font: mono(8), color: ink.withAlphaComponent(0.7), tracking: 1.65)
            let totalMinutes = entries.reduce(0) { $0 + $1.endMinutes - $1.startMinutes }
            let hours = Double(totalMinutes) / 60
            let stats = String(format: "%02d SESSIONS / %.1f HRS", entries.count, hours)
            text(stats, in: CGRect(x: grid.maxX - 250, y: frame.maxY - 27, width: 250, height: 16),
                 font: mono(9), color: ink.withAlphaComponent(0.85), alignment: .right, tracking: 1.1)
        }

        private func course(_ entry: ScheduleEntry, in rect: CGRect) {
            guard rect.width > 3, rect.height > 2 else { return }
            context.saveGState()
            context.clip(to: rect)
            let hash = entry.name.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
            let tint = CGFloat(hash % 4) * 0.025
            fill(rect, color: palette.deep.withAlphaComponent(0.35 + tint))
            gradient(colors: [ink.withAlphaComponent(0.13 + tint), ink.withAlphaComponent(0.035)], locations: [0, 1],
                     from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
            stroke(rect.insetBy(dx: 0.4, dy: 0.4), color: ink.withAlphaComponent(0.38), width: 0.8)
            fill(CGRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height), color: ink.withAlphaComponent(0.85))

            let padding: CGFloat = rect.width < 100 ? 6 : 10
            let content = rect.insetBy(dx: padding, dy: 7)
            guard content.width >= 12 else { context.restoreGState(); return }
            if rect.height < 39 {
                let pointSize = min(13, max(7, rect.height - 6))
                let lineHeight = pointSize * 1.3
                let lineY = rect.minY + max(1, (rect.height - lineHeight) / 2)
                let compactTimeWidth: CGFloat = content.width >= 150 ? 75 : 0
                text(entry.name, in: CGRect(x: content.minX, y: lineY, width: content.width - compactTimeWidth, height: lineHeight + 1),
                     font: NSFont.systemFont(ofSize: pointSize, weight: .medium), color: ink, truncate: true)
                if compactTimeWidth > 0 {
                    text(entry.timeLabel, in: CGRect(x: content.maxX - 73, y: rect.midY - 5, width: 73, height: 12),
                         font: mono(7.5), color: ink.withAlphaComponent(0.79), alignment: .right, truncate: true)
                }
            } else {
                let fontSize: CGFloat = rect.width < 125 ? 13 : 17
                let canShowTime = content.height >= 51
                let canShowLocation = configuration.showLocations && !entry.location.isEmpty && content.height >= 68
                let titleHeight = min(fontSize * 2.7, content.height - (canShowTime ? 18 : 0) - (canShowLocation ? 17 : 0))
                text(entry.name, in: CGRect(x: content.minX, y: content.minY, width: content.width, height: titleHeight),
                     font: NSFont.systemFont(ofSize: fontSize, weight: .medium), color: ink, lineSpacing: 2)
                if canShowTime {
                    let timeY = canShowLocation ? rect.maxY - 40 : rect.maxY - 24
                    text(entry.timeLabel, in: CGRect(x: content.minX, y: timeY, width: content.width, height: 14),
                         font: mono(rect.width < 140 ? 8 : 9), color: ink.withAlphaComponent(0.79), truncate: true)
                }
                if canShowLocation {
                    text(entry.location, in: CGRect(x: content.minX, y: rect.maxY - 23, width: content.width, height: 14),
                         font: NSFont.systemFont(ofSize: 9.5), color: ink.withAlphaComponent(0.68), truncate: true)
                }
            }
            context.restoreGState()
        }

        private func cornerMarks(_ rect: CGRect) {
            for point in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                          CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
                line(CGPoint(x: point.x - 5, y: point.y), CGPoint(x: point.x + 5, y: point.y), alpha: 0.86)
                line(CGPoint(x: point.x, y: point.y - 5), CGPoint(x: point.x, y: point.y + 5), alpha: 0.86)
            }
            for tick in 0..<39 {
                let x = rect.minX + CGFloat(tick) * rect.width / 38
                line(CGPoint(x: x, y: rect.minY - 10), CGPoint(x: x, y: rect.minY - (tick.isMultiple(of: 5) ? 15 : 12)), alpha: 0.35, width: 0.6)
            }
        }

        private func texture() {
            // Fixed integer hashing creates repeatable paper grain at every export size.
            let width = 1512, height = max(1, Int(CGFloat(1512) * size.height / size.width))
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            for index in 0..<(width * height) {
                var value = UInt32(index) &* 747796405 &+ 2891336453
                value = ((value >> ((value >> 28) + 4)) ^ value) &* 277803737
                value = (value >> 22) ^ value
                let bright = value & 1 == 0
                let alpha = UInt8((value >> 8) % 6)
                let shade: UInt8 = bright ? alpha : 0
                pixels[index * 4] = shade
                pixels[index * 4 + 1] = shade
                pixels[index * 4 + 2] = shade
                pixels[index * 4 + 3] = alpha
            }
            let data = Data(pixels)
            guard let provider = CGDataProvider(data: data as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(origin: .zero, size: size))
            context.restoreGState()
        }

        private func radial(center: CGPoint, radius: CGFloat, color: NSColor, opacity: CGFloat) {
            let colors = [color.withAlphaComponent(opacity).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }

        private func gradient(colors: [NSColor], locations: [CGFloat], from: CGPoint, to: CGPoint) {
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: locations) else { return }
            context.saveGState()
            context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }

        private func fill(_ rect: CGRect, color: NSColor) {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        }

        private func stroke(_ rect: CGRect, color: NSColor, width: CGFloat) {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.stroke(rect)
        }

        private func line(_ from: CGPoint, _ to: CGPoint, alpha: CGFloat, width: CGFloat = 0.8) {
            context.setStrokeColor(ink.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(width)
            context.move(to: from)
            context.addLine(to: to)
            context.strokePath()
        }

        private func mono(_ size: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }
        private func serif(_ size: CGFloat) -> NSFont { NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size) }

        private func attributed(_ value: String, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left,
                                tracking: CGFloat = 0, lineSpacing: CGFloat = 0, truncate: Bool = false) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            paragraph.lineSpacing = lineSpacing
            paragraph.lineBreakMode = truncate ? .byTruncatingTail : .byWordWrapping
            return NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: color,
                                                                  .kern: tracking, .paragraphStyle: paragraph])
        }

        private func text(_ value: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .left,
                          tracking: CGFloat = 0, lineSpacing: CGFloat = 0, truncate: Bool = false) {
            guard rect.width > 0, rect.height > 0 else { return }
            context.saveGState()
            context.clip(to: rect)
            attributed(value, font: font, color: color, alignment: alignment, tracking: tracking, lineSpacing: lineSpacing, truncate: truncate)
                .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine])
            context.restoreGState()
        }
    }
}
