import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.97)
    static let secondaryBackground = Color(red: 0.92, green: 0.95, blue: 0.95)
    static let panel = Color.white
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.19)
    static let muted = Color(red: 0.39, green: 0.45, blue: 0.50)
    static let line = Color(red: 0.82, green: 0.86, blue: 0.89)
    static let accent = Color(red: 0.10, green: 0.32, blue: 0.45)
    static let focus = Color(red: 0.70, green: 0.31, blue: 0.24)
    static let free = Color(red: 0.22, green: 0.62, blue: 0.38)

    static func contentWidth(for availableWidth: CGFloat, maximum: CGFloat = 1100) -> CGFloat? {
        availableWidth >= maximum + 72 ? maximum : nil
    }

    static func outerPadding(for availableWidth: CGFloat) -> CGFloat {
        availableWidth < 520 ? 12 : 18
    }
}

struct Panel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: AppTheme.line)
    }
}

extension View {
    func decorativeStroke<S: InsettableShape>(_ shape: S, color: Color, lineWidth: CGFloat = 1) -> some View {
        overlay(
            shape
                .stroke(color, lineWidth: lineWidth)
                .allowsHitTesting(false)
        )
    }
}

struct CategoryBadge: View {
    let category: ScheduleCategory

    var body: some View {
        Label(category.displayName, systemImage: category.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(category.surface)
            .clipShape(Capsule())
    }
}

struct SchedulePlacePicker: View {
    let title: String
    @Binding var selection: SchedulePlace

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(SchedulePlace.allCases.filter { $0 != .free }) { place in
                Label(place.rawValue, systemImage: place.symbolName).tag(place)
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbolName: String
    let tint: Color

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(value)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .monospacedDigit()

                    Text(title)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DaySelector: View {
    @Binding var selection: Weekday

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Weekday.allCases) { day in
                    Button {
                        selection = day
                    } label: {
                        Text(day.rawValue)
                    }
                    .buttonStyle(SelectorChipButtonStyle(isSelected: selection == day, width: 38))
                    .accessibilityLabel(day.longName)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct SelectorChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    var width: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        let effectiveWidth = width.map { max($0, 42) }

        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : AppTheme.ink)
            .frame(width: effectiveWidth, height: 40)
            .padding(.horizontal, width == nil ? 14 : 0)
            .background(isSelected ? AppTheme.accent : AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .decorativeStroke(
                RoundedRectangle(cornerRadius: 8, style: .continuous),
                color: isSelected ? AppTheme.accent : AppTheme.line
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct ActionPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = AppTheme.accent
    var isProminent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let foreground = isEnabled ? (isProminent ? Color.white : tint) : AppTheme.muted.opacity(0.72)
        let background = isEnabled
            ? (isProminent ? tint : tint.opacity(0.10))
            : AppTheme.background.opacity(0.72)
        let stroke = isEnabled ? tint.opacity(isProminent ? 0 : 0.28) : AppTheme.line

        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .decorativeStroke(RoundedRectangle(cornerRadius: 8, style: .continuous), color: stroke)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed && isEnabled ? 0.72 : 1)
    }
}

struct ResponsiveScroll<Content: View>: View {
    let maximumWidth: CGFloat
    let content: (CGFloat) -> Content

    init(maximumWidth: CGFloat = 1100, @ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.maximumWidth = maximumWidth
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(proxy.size.width)
                    .padding(AppTheme.outerPadding(for: proxy.size.width))
                    .frame(maxWidth: AppTheme.contentWidth(for: proxy.size.width, maximum: maximumWidth), alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: proxy.size.width > maximumWidth + 72 ? .center : .leading)
            }
        }
    }
}
