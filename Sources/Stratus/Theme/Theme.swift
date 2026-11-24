import SwiftUI
import AppKit

/// Pitch-black T3 Code-inspired design tokens.
/// Zero borders, zero pane dividers, pure typographic hierarchy and subtle tonal elevation.
enum T3 {
    // MARK: - Backgrounds (Pure Pitch Black)
    static let bg = Color(hex: 0x000000)
    static let bgSidebar = Color(hex: 0x030304)
    static let bgInspector = Color(hex: 0x060608)
    static let bgPalette = Color(hex: 0x0B0B0F)
    static let bgSheet = Color(hex: 0x050507)
    static let surfaceSubtle = Color(hex: 0x0B0B0E)
    static let surfaceHover = Color(hex: 0x111114)
    static let surfaceActive = Color(hex: 0x16161B)
    static let surfacePill = Color(hex: 0x151519)

    // MARK: - Typography Colors
    static let textPrimary = Color(hex: 0xF4F4F6)
    static let textSecondary = Color(hex: 0x8E8E99)
    static let textTertiary = Color(hex: 0x585862)
    static let textMuted = Color(hex: 0x6E6E77)

    // MARK: - Accent Palette
    static let coral = Color(hex: 0xE88255)
    static let indigo = Color(hex: 0x7A89FF)
    static let sky = Color(hex: 0x4BC3F7)
    static let mint = Color(hex: 0x34D399)
    static let amber = Color(hex: 0xFBBF24)
    static let rose = Color(hex: 0xF87171)
    static let violet = Color(hex: 0xA78BFA)
    static let slate = Color(hex: 0x71717A)

    // MARK: - Typography Helpers
    static func heroKPI() -> Font {
        .system(size: 40, weight: .bold, design: .default).monospacedDigit()
    }

    static func pageTitle() -> Font {
        .system(size: 22, weight: .semibold, design: .default)
    }

    static func sectionTitle() -> Font {
        .system(size: 13, weight: .semibold, design: .default)
    }

    static func statValue() -> Font {
        .system(size: 20, weight: .semibold, design: .default).monospacedDigit()
    }

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        self.init(hex: UInt32(int))
    }
}

enum Formatters {
    static func currency(_ amount: Double) -> String {
        if amount > 0 && amount < 0.01 {
            return String(format: "$%.3f", amount)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = amount >= 1000 ? 0 : 2
        formatter.maximumFractionDigits = amount >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    static func currencyPrecise(_ amount: Double) -> String {
        if amount > 0 && amount < 0.01 {
            return String(format: "$%.3f", amount)
        }
        return String(format: "$%.2f", amount)
    }

    static func compactNumber(_ value: Int) -> String {
        let num = Double(value)
        switch num {
        case 1_000_000_000...:
            return String(format: "%.2fB", num / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.2fM", num / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", num / 1_000)
        default:
            return "\(value)"
        }
    }

    static func byteCount(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }

    static func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        return f.string(from: date).uppercased()
    }

    static func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

/// Configures the hosting NSWindow for a seamless, borderless pitch-black macOS appearance.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }

    @MainActor
    private func configure(_ window: NSWindow) {
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.styleMask.insert(.fullSizeContentView)
    }
}
