import AppKit
import SwiftUI

enum GlassCapability: Equatable {
    case full
    case fallback
}

enum GlassStatusKind {
    case warning
    case success
    case neutral
}

@MainActor
enum LiquidGlassSupport {
    static func currentCapability() -> GlassCapability {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion >= 26 else {
            return .fallback
        }

        let workspace = NSWorkspace.shared
        let requiresFallback = workspace.accessibilityDisplayShouldReduceTransparency
            || workspace.accessibilityDisplayShouldIncreaseContrast
        return requiresFallback ? .fallback : .full
    }
}

struct GlassTokens {
    let capability: GlassCapability

    var panelCornerRadius: CGFloat { capability == .full ? 14 : 10 }
    var cardCornerRadius: CGFloat { capability == .full ? 10 : 8 }

    var panelFill: AnyShapeStyle {
        switch capability {
        case .full:
            return AnyShapeStyle(.thinMaterial)
        case .fallback:
            return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
    }

    var cardFill: AnyShapeStyle {
        switch capability {
        case .full:
            return AnyShapeStyle(.ultraThinMaterial)
        case .fallback:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }
    }

    var previewFill: AnyShapeStyle {
        switch capability {
        case .full:
            return AnyShapeStyle(.regularMaterial)
        case .fallback:
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }
    }

    var panelBorder: Color {
        switch capability {
        case .full:
            return Color.primary.opacity(0.22)
        case .fallback:
            return Color(nsColor: .separatorColor).opacity(0.75)
        }
    }

    var cardBorder: Color {
        switch capability {
        case .full:
            return Color.primary.opacity(0.16)
        case .fallback:
            return Color(nsColor: .separatorColor).opacity(0.6)
        }
    }

    func statusForeground(_ kind: GlassStatusKind) -> Color {
        switch kind {
        case .warning:
            return Color(nsColor: .systemOrange)
        case .success:
            return Color(nsColor: .systemGreen)
        case .neutral:
            return .primary
        }
    }

    func statusFill(_ kind: GlassStatusKind) -> AnyShapeStyle {
        let base: Color
        switch kind {
        case .warning:
            base = Color(nsColor: .systemOrange)
        case .success:
            base = Color(nsColor: .systemGreen)
        case .neutral:
            base = Color(nsColor: .secondaryLabelColor)
        }

        let opacity: Double = capability == .full ? 0.16 : 0.12
        return AnyShapeStyle(base.opacity(opacity))
    }

    func statusBorder(_ kind: GlassStatusKind) -> Color {
        let base: Color
        switch kind {
        case .warning:
            base = Color(nsColor: .systemOrange)
        case .success:
            base = Color(nsColor: .systemGreen)
        case .neutral:
            base = Color(nsColor: .separatorColor)
        }

        let opacity: Double = capability == .full ? 0.34 : 0.28
        return base.opacity(opacity)
    }
}

private struct GlassContainerStyleModifier: ViewModifier {
    let capability: GlassCapability

    func body(content: Content) -> some View {
        let tokens = GlassTokens(capability: capability)
        return content
            .background(
                RoundedRectangle(cornerRadius: tokens.panelCornerRadius, style: .continuous)
                    .fill(tokens.panelFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.panelCornerRadius, style: .continuous)
                    .stroke(tokens.panelBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: tokens.panelCornerRadius, style: .continuous))
    }
}

private struct GlassCardStyleModifier: ViewModifier {
    let capability: GlassCapability

    func body(content: Content) -> some View {
        let tokens = GlassTokens(capability: capability)
        return content
            .background(
                RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                    .fill(tokens.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                    .stroke(tokens.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
    }
}

private struct GlassStatusStyleModifier: ViewModifier {
    let capability: GlassCapability
    let kind: GlassStatusKind

    func body(content: Content) -> some View {
        let tokens = GlassTokens(capability: capability)
        return content
            .background(
                RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                    .fill(tokens.statusFill(kind))
            )
            .overlay(
                RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous)
                    .stroke(tokens.statusBorder(kind), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: tokens.cardCornerRadius, style: .continuous))
    }
}

extension View {
    func glassContainerStyle(_ capability: GlassCapability) -> some View {
        modifier(GlassContainerStyleModifier(capability: capability))
    }

    func glassCardStyle(_ capability: GlassCapability) -> some View {
        modifier(GlassCardStyleModifier(capability: capability))
    }

    func glassStatusStyle(_ capability: GlassCapability, kind: GlassStatusKind) -> some View {
        modifier(GlassStatusStyleModifier(capability: capability, kind: kind))
    }
}
