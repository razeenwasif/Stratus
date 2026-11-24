import SwiftUI

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 6
    var pulse: Bool = false

    @State private var isAnimating = false

    var body: some View {
        ZStack {
            if pulse {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: size * 2.1, height: size * 2.1)
                    .scaleEffect(isAnimating ? 1.25 : 0.85)
                    .opacity(isAnimating ? 0.2 : 0.7)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
                    .onAppear { isAnimating = true }
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 2, height: size * 2)
    }
}

struct TagPill: View {
    let text: String
    var color: Color? = nil
    var textColor: Color = T3.textSecondary
    var monospaced: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(monospaced ? T3.mono(11, weight: .medium) : .system(size: 11, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(T3.surfacePill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct MetricStatColumn: View {
    let label: String
    let value: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(T3.textMuted)
                .lineLimit(1)
            Text(value)
                .font(T3.statValue())
                .foregroundStyle(T3.textPrimary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(T3.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BarSegment: Identifiable, Sendable, Hashable {
    let id: String
    let label: String
    let value: Double
    let formattedValue: String
    let colorHex: String

    init(id: String? = nil, label: String, value: Double, formattedValue: String, colorHex: String) {
        self.id = id ?? label
        self.label = label
        self.value = value
        self.formattedValue = formattedValue
        self.colorHex = colorHex
    }
}

struct SegmentedBar: View {
    let segments: [BarSegment]

    private var total: Double {
        max(segments.reduce(0) { $0 + max(0, $1.value) }, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                let gapTotal = CGFloat(max(0, segments.count - 1)) * 2
                let availableWidth = max(1, geo.size.width - gapTotal)
                HStack(spacing: 2) {
                    ForEach(segments) { segment in
                        let fraction = max(0, segment.value) / total
                        let w = max(4, availableWidth * fraction)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hexString: segment.colorHex))
                            .frame(width: w, height: 6)
                            .help("\(segment.label): \(segment.formattedValue)")
                    }
                }
            }
            .frame(height: 6)

            // Compact inline wrap-style legend matching T3 Code style
            FlowWrapLayout(horizontalSpacing: 14, verticalSpacing: 6) {
                ForEach(segments) { segment in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(hexString: segment.colorHex))
                            .frame(width: 6, height: 6)
                        Text(segment.label)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(T3.textSecondary)
                        Text(segment.formattedValue)
                            .font(T3.mono(11, weight: .semibold))
                            .foregroundStyle(T3.textPrimary)
                    }
                }
            }
        }
    }
}

/// Lightweight custom wrap layout (macOS 14+) for inline legends and tag strips.
struct FlowWrapLayout: Layout {
    var horizontalSpacing: CGFloat = 10
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct BorderlessSearchField: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    var width: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(T3.textTertiary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(T3.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(T3.textPrimary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(T3.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: width)
        .background(T3.surfaceHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct ActionPillButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = T3.textPrimary
    var background: Color = T3.surfacePill
    var isLoading: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                (isHovered ? T3.surfaceActive : background),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { isHovered = $0 }
    }
}

struct FilterPillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? T3.textPrimary : T3.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    isSelected ? T3.surfaceActive : (isHovered ? T3.surfaceHover : Color.clear),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(T3.textTertiary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(T3.textPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(T3.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                ActionPillButton(title: actionTitle, systemImage: "arrow.clockwise", tint: T3.indigo) {
                    action()
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct ToastBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: isError ? T3.rose : T3.mint, size: 6)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(T3.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(T3.bgPalette, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.65), radius: 16, y: 6)
    }
}
