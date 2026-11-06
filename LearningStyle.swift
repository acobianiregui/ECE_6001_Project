import SwiftUI

extension LearningTrack {
    var tint: Color {
        switch self {
        case .circuits: .mint
        case .mechanics: .orange
        case .design: .indigo
        }
    }
}

enum LearningStyle {
    static let teal = Color(red: 0.3, green: 0.88, blue: 0.78)
    static let muted = Color.white.opacity(0.62)
}

struct StudyCard<Content: View>: View {
    var tint: Color = .white
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(tint.opacity(0.13)))
    }
}

struct StudyHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased()).font(.caption.weight(.semibold)).tracking(2).foregroundStyle(LearningStyle.teal)
            Text(title).font(.system(size: 34, weight: .bold, design: .rounded))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TrackBadge: View {
    let track: LearningTrack
    var body: some View {
        Label(track.title, systemImage: track.symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(track.tint)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(track.tint.opacity(0.12), in: Capsule())
    }
}

struct MetricTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = LearningStyle.teal
    var body: some View {
        StudyCard(tint: tint) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
