import AppKit
import Darwin

/// Synthetic, release-mode drawing + PNG encoding baseline. No saved state,
/// EventKit, desktop changes, or user-specific calendar data are accessed.
@main
enum RendererBenchmark {
    private static func cpuTime() -> Double { Double(clock()) / Double(CLOCKS_PER_SEC) }
    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    static func main() throws {
        let repetitions = 7
        for size in [CGSize(width: 756, height: 491), CGSize(width: 3024, height: 1964), CGSize(width: 3840, height: 2160)] {
            var configurations = [WallpaperConfiguration(), WallpaperConfiguration()]
            configurations[1].showTexture = false
            var reference: [Data] = []
            for configuration in configurations {
                reference.append(try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: configuration, size: size))
            }
            var cpu = [[Double](), [Double]()]
            var wall = [[Double](), [Double]()]
            for repetition in 0..<repetitions {
                // Alternate to reduce order/temperature bias.
                for index in repetition.isMultiple(of: 2) ? [0, 1] : [1, 0] {
                    try autoreleasepool {
                        let cpuStart = cpuTime()
                        let wallStart = ProcessInfo.processInfo.systemUptime
                        let output = try WallpaperRenderer.pngData(entries: ScheduleEntry.sample, configuration: configurations[index], size: size)
                        wall[index].append((ProcessInfo.processInfo.systemUptime - wallStart) * 1000)
                        cpu[index].append((cpuTime() - cpuStart) * 1000)
                        precondition(output == reference[index], "Repeated production PNG must be byte-identical")
                    }
                }
            }
            print("\(Int(size.width))×\(Int(size.height)); \(repetitions) repetitions per mode; identical PNG bytes on every repetition")
            for index in 0...1 {
                let mode = index == 0 ? "texture on " : "texture off"
                print(String(format: "  %@: median CPU %.2f ms; median wall %.2f ms", mode, median(cpu[index]), median(wall[index])))
            }
            let delta = median(cpu[0]) - median(cpu[1])
            print(String(format: "  texture-enabled PNG CPU delta (includes encoding): %.2f ms (%.1f%%)", delta, 100 * delta / median(cpu[0])))
        }
    }
}
