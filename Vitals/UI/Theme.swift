import AppKit
import SwiftUI

extension Severity {
    var color: Color {
        switch self {
        case .calm: .green
        case .notice: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct AppIconView: View {
    let identity: AppIdentity?
    let fallbackSymbol: String
    var size: CGFloat = 28

    var body: some View {
        if let icon = SystemActions.icon(for: identity) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.25))
        }
    }
}

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .heavy))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing),
                in: Capsule())
    }
}

struct Card<Content: View>: View {
    var accent: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder((accent ?? Color.primary).opacity(accent == nil ? 0.08 : 0.45), lineWidth: 1))
    }
}
