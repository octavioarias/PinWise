import SwiftUI
import SwiftData
import PeptideKit

/// A right-anchored slide-in "Assistant" (mirror of the left menu). Fully on-device: it
/// summarizes YOUR logged data and links to reference material. It never gives dosing or
/// medical advice — by design it only reflects your data and the catalog.
struct AssistantDrawer: View {
    @Binding var isOpen: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.85
            let topInset = geo.safeAreaInsets.top
            ZStack(alignment: .trailing) {
                if isOpen {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { isOpen = false }
                        .transition(.opacity)

                    AssistantView(topInset: topInset) { isOpen = false }
                        .frame(width: width, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(BrandColor.surface)
                        .overlay(alignment: .leading) { Rectangle().fill(BrandColor.stroke).frame(width: 0.5) }
                        .ignoresSafeArea()
                        .shadow(color: .black.opacity(0.45), radius: 24, x: -8)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.9), value: isOpen)
        }
        .allowsHitTesting(isOpen)
    }
}

struct AssistantView: View {
    let topInset: CGFloat
    let close: () -> Void

    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var recent: [LoggedDose]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @State private var showCompounds = false
    @State private var showLegend = false

    private var activeProtocols: [SavedProtocol] { protocols.filter(\.isActive) }
    private var thisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return recent.filter { $0.timestamp >= weekAgo }.count
    }
    private var nextDose: Date? { activeProtocols.compactMap { $0.nextDose() }.min() }
    private var mostUsedSite: InjectionSite? {
        var counts: [InjectionSite: Int] = [:]
        for d in recent { if let s = d.site { counts[s, default: 0] += 1 } }
        return counts.max { $0.value < $1.value }?.key
    }
    private var suggestedSite: InjectionSite? {
        SiteRotationAdvisor.suggestNext(history: recent.map { $0.asDomain() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Assistant", systemImage: "sparkles")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(BrandColor.textPrimary)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark").font(.headline.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close assistant")
            }
            .padding(.top, topInset + Space.md)
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("On-device — reflects your own data and the science. It won't recommend a dose or give medical advice.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)

                    Card {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader(title: "Your snapshot")
                            Text(snapshot).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                            if let m = mostUsedSite {
                                Text("Most-used site: \(m.displayName).").font(.caption).foregroundStyle(BrandColor.textSecondary)
                            }
                        }
                    }

                    if let s = suggestedSite, !recent.isEmpty {
                        Card {
                            HStack(spacing: Space.md) {
                                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(BrandColor.success)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Rotation tip").font(.caption).foregroundStyle(BrandColor.textSecondary)
                                    Text("Next, consider \(s.displayName).").font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                                }
                                Spacer()
                            }
                        }
                    }

                    VStack(spacing: Space.md) {
                        actionRow("Look up a compound", "magnifyingglass", "What it is, the evidence, half-life") { showCompounds = true }
                        actionRow("What tiers & labels mean", "questionmark.circle", "Evidence A–D, WADA, half-life") { showLegend = true }
                    }
                }
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.xl)
            }
            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showCompounds) { NavigationStack { CompoundsView() } }
        .sheet(isPresented: $showLegend) { CompoundLegendView() }
    }

    private var snapshot: String {
        var parts: [String] = []
        parts.append("You've logged \(thisWeek) dose\(thisWeek == 1 ? "" : "s") this week")
        if !activeProtocols.isEmpty {
            parts.append("across \(activeProtocols.count) active protocol\(activeProtocols.count == 1 ? "" : "s")")
        }
        var sentence = parts.joined(separator: " ") + "."
        if let d = nextDose {
            sentence += " Next scheduled dose: \(d.formatted(.dateTime.weekday(.abbreviated).month().day()))."
        }
        return sentence
    }

    private func actionRow(_ title: String, _ icon: String, _ subtitle: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: icon).font(.title3).frame(width: 26).foregroundStyle(BrandColor.accentText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.headline).foregroundStyle(BrandColor.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
            }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}
