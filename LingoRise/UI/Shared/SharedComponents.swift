import SwiftUI

struct AsyncStoryImage: View {
    let url: String

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x26344F), LingoRiseColors.primary.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let parsed = URL(string: url), !url.isEmpty {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "book.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.16))
                    }
                }
            } else {
                Image(systemName: "book.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.16))
            }
        }
        .clipped()
    }
}

struct CircleAction: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 42)
                .background(.regularMaterial)
                .clipShape(Circle())
        }
    }
}

struct MessageState: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LingoRiseColors.primary)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(LingoRiseColors.primary.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemBackground).opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct WrappingFlowLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat
    var fallbackWidth: CGFloat = 320
    var usesContentWidth: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(width: proposal.width ?? fallbackWidth, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(width: bounds.width, subviews: subviews)
        for item in result.items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func layout(width: CGFloat, subviews: Subviews) -> (items: [(index: Int, origin: CGPoint, size: CGSize)], size: CGSize) {
        var items: [(index: Int, origin: CGPoint, size: CGSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            items.append((index, CGPoint(x: x, y: y), size))
            totalWidth = max(totalWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        let outputWidth = usesContentWidth || width == 0 ? totalWidth : width
        return (items, CGSize(width: outputWidth, height: y + rowHeight))
    }
}
