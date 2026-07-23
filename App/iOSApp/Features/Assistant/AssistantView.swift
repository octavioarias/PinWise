import SwiftUI
import SwiftData
import PeptideKit

/// A right-anchored slide-in "Assistant" (mirror of the left menu). Conversational, powered by
/// Apple's on-device model where available (no cloud, no API keys, no usage cost). Strong
/// guardrails: informational only, never dosing/medical advice, jailbreak-resistant.
struct AssistantDrawer: View {
    @Binding var isOpen: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width * 0.92
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
                        // Tinted glass over the dimmed app content — the 0.55 scrim also dims what
                        // the blur samples. Scheme-split tint: 0.7 on dark is bounded (scrim +
                        // dark material cap the backdrop), but LIGHT mode needs 0.92 — there the
                        // black scrim works AGAINST a bright panel and no ultraThin tint below
                        // ~0.9 holds textSecondary at 4.5:1 over dark content behind the drawer.
                        .background(BrandColor.background.opacity(scheme == .dark ? 0.7 : 0.92))
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .leading) { Rectangle().fill(BrandColor.stroke).frame(width: 0.5) }
                        .ignoresSafeArea()
                        .shadow(color: .black.opacity(0.45), radius: 24, x: -8)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(Motion.drawer, value: isOpen)
        }
        .allowsHitTesting(isOpen)
    }
}

/// Conversational engine backed by the hosted AI (Supabase `ai-chat` Edge Function). Streams the
/// reply token-by-token. The safety guardrails now live SERVER-SIDE (in the Edge Function) so they
/// can't be stripped by a modified client — this class only sends the conversation history + a
/// bounded snapshot of the user's own data.
@MainActor
@Observable
final class AssistantEngine {
    struct Message: Identifiable {
        let id = UUID()
        let isUser: Bool
        var text: String
    }

    var messages: [Message] = []
    var isThinking = false

    private let client = CloudAIClient()

    func send(_ prompt: String, context: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(Message(isUser: true, text: trimmed))
        isThinking = true
        defer { isThinking = false }

        // Send the full history (ending in the turn just added) so the model has conversational
        // memory — the backend is stateless per request.
        let history = messages.map { CloudAIMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }

        var assistantText = ""
        var assistantIndex: Int?   // index of the streaming reply bubble, created on first token

        do {
            for try await delta in client.stream(messages: history, context: context) {
                assistantText += delta
                if let i = assistantIndex, messages.indices.contains(i) {
                    messages[i].text = assistantText
                } else {
                    messages.append(Message(isUser: false, text: assistantText))
                    assistantIndex = messages.count - 1
                    isThinking = false   // first token arrived — drop the "Thinking…" indicator
                }
            }
            if assistantText.isEmpty {
                messages.append(Message(isUser: false, text: "Sorry — I couldn't answer that just now. Please try again."))
            }
        } catch {
            let text: String
            switch error {
            case CloudAIError.limitReached:
                text = "You've reached today's message limit. Upgrade to Pro for more, or check back tomorrow."
            case CloudAIError.notConfigured:
                text = "The assistant isn't available yet."
            case CloudAIError.notSignedIn:
                text = "Please sign in to chat with Natt."
            default:
                text = "Sorry — something went wrong. Please try again."
            }
            if let i = assistantIndex, messages.indices.contains(i) { messages[i].text = text }
            else { messages.append(Message(isUser: false, text: text)) }
        }
    }
}

struct AssistantView: View {
    let topInset: CGFloat
    let close: () -> Void

    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var recent: [LoggedDose]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \SymptomEntry.timestamp, order: .reverse) private var symptoms: [SymptomEntry]
    @Query(sort: \BiomarkerEntry.timestamp, order: .reverse) private var biomarkers: [BiomarkerEntry]
    @State private var health = HealthManager.shared
    @State private var auth = AuthManager.shared
    // Versioned so a change in how the assistant handles data (e.g. this move to cloud processing)
    // can force re-acceptance. Tied to `Disclaimer.currentVersion` — bumping it re-prompts here too.
    @AppStorage("aiConsentVersion") private var aiConsentVersion = 0
    private var aiAccepted: Bool { aiConsentVersion >= Disclaimer.currentVersion }
    @State private var engine = AssistantEngine()
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @State private var showCompounds = false
    @State private var showLegend = false

    private var activeProtocols: [SavedProtocol] { protocols.filter(\.isActive) }
    private var thisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return recent.filter { $0.timestamp >= weekAgo }.count
    }
    private var mostUsedSite: InjectionSite? {
        var counts: [InjectionSite: Int] = [:]
        for d in recent { if let s = d.site { counts[s, default: 0] += 1 } }
        return counts.max { $0.value < $1.value }?.key
    }

    /// A rich, bounded snapshot of everything PinWise knows about this user, so the assistant can
    /// actually reason about their stack, logs, symptoms, labs, and connected health.
    private var contextString: String {
        func day(_ d: Date) -> String { d.formatted(.dateTime.month().day()) }
        var lines: [String] = []

        if let n = AuthManager.shared.displayName, !n.isEmpty {
            lines.append("USER: \(n)")
        }
        if !activeProtocols.isEmpty {
            lines.append("ACTIVE PROTOCOLS:")
            for p in activeProtocols {
                let parts = p.items.enumerated().map { idx, item -> String in
                    let unit = p.doseUnit(forItemAt: idx, vials: vials)
                    let dose = Mass(micrograms: item.doseMicrograms)
                    // A blend vial is one injection delivering every compound at a fixed mass ratio —
                    // give the assistant the full breakdown, not just the primary.
                    if let v = vials.first(where: { $0.id == item.vialID }), v.isBlend,
                       let primary = v.primaryAPI, primary.massMicrograms > 0 {
                        let deliver = v.apis.map { "\($0.name) \(Mass(micrograms: $0.massMicrograms / primary.massMicrograms * dose.micrograms).displayString(in: unit))" }
                            .joined(separator: " + ")
                        return "\(v.displayName) (blend, one shot: \(deliver))"
                    }
                    return "\(item.compoundName) \(dose.displayString(in: unit))"
                }
                lines.append("- \(p.name): " + parts.joined(separator: " + ") + " · \(p.cadenceText)")
            }
        }
        if !vials.isEmpty {
            lines.append("INVENTORY:")
            for v in vials.prefix(8) {
                lines.append("- \(v.displayName): \(max(0, v.totalDoses - v.dosesTaken)) of \(v.totalDoses) doses left")
            }
        }
        if !recent.isEmpty {
            lines.append("RECENT DOSES (\(thisWeek) this week):")
            for d in recent.prefix(8) {
                let unit = vials.first { $0.id == d.vialID }?.doseUnit ?? MassUnit.auto(forMicrograms: d.dose.micrograms)
                lines.append("- \(day(d.timestamp)): \(d.compoundName) \(d.dose.displayString(in: unit))" + (d.site.map { " @ \($0.displayName)" } ?? ""))
            }
            if let m = mostUsedSite { lines.append("Most-used site: \(m.displayName).") }
        }
        if !symptoms.isEmpty {
            lines.append("RECENT SYMPTOMS: " + symptoms.prefix(6).map { "\($0.symptomRaw) \($0.severity)/10 (\(day($0.timestamp)))" }.joined(separator: ", "))
        }
        if !biomarkers.isEmpty {
            var latestByType: [String: BiomarkerEntry] = [:]
            for b in biomarkers where latestByType[b.typeRaw] == nil { latestByType[b.typeRaw] = b }
            lines.append("LATEST LABS/METRICS: " + latestByType.values.map { "\($0.typeRaw) \($0.value)" }.joined(separator: ", "))
        }
        // NOTE: Apple Health (HealthKit-read) metrics are deliberately NOT included here. This
        // context is sent to the cloud assistant, and Apple guideline 5.1.3 restricts sharing
        // HealthKit-derived data with third parties — so it stays on-device only. Data the user
        // typed into PinWise (above) is fair game to send; HealthKit-sourced data is walled off.
        return lines.isEmpty ? "The user hasn't logged anything yet." : lines.joined(separator: "\n")
    }

    private let starters = ["What is BPC-157?", "Explain the evidence tiers", "What does half-life mean?", "How's my week looking?"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Natt", systemImage: "sparkles")
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(BrandColor.textPrimary)
                Spacer()
                Button { close() } label: {
                    Image(systemName: "xmark").font(.headline.weight(.semibold))
                        .foregroundStyle(BrandColor.textSecondary).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Close Natt")
            }
            .padding(.top, topInset + Space.md)
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.sm)

            if auth.isGuest {
                signInGate
            } else if aiAccepted {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.md) {
                        Text("Informational only — never dosing or medical advice.")
                            .font(.caption2).foregroundStyle(BrandColor.textSecondary)

                        if engine.messages.isEmpty {
                            starterCard
                            snapshotCard
                        } else {
                            ForEach(engine.messages) { bubble($0) }
                            if engine.isThinking {
                                HStack(spacing: Space.sm) { ProgressView(); Text("Thinking…").font(.caption).foregroundStyle(BrandColor.textSecondary) }
                            }
                        }
                    }
                    .padding(.horizontal, Space.lg)
                    .padding(.bottom, Space.md)
                }

                inputBar
            } else {
                disclaimerGate
            }
        }
        .task { if health.authorized { await health.refresh() } }
        .sheet(isPresented: $showCompounds) { NavigationStack { CompoundsView() } }
        .sheet(isPresented: $showLegend) { CompoundLegendView() }
    }

    /// Guests can use the free tracker, but the assistant is account-only. Prompt sign-in and drop
    /// back to the welcome screen (beginAccountUpgrade clears the guest session so it reappears).
    private var signInGate: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.largeTitle).foregroundStyle(BrandColor.accentText)
                    Text("Sign in to chat with Natt")
                        .font(Typo.title).foregroundStyle(BrandColor.textPrimary)
                    Text("The assistant is part of your PinWise account. Sign in with Apple or your email to start chatting — the rest of the app stays free as a guest.")
                        .font(.callout).foregroundStyle(BrandColor.textSecondary)
                }
                .padding(Space.lg)
            }
            PrimaryButton(title: "Sign in", systemImage: "person.crop.circle") {
                auth.beginAccountUpgrade()
                close()
            }
            .padding(.horizontal, Space.lg).padding(.top, Space.sm).padding(.bottom, Space.lg)
            .background(BrandColor.surface)
        }
    }

    /// First-use liability gate — the assistant is unusable until the user accepts.
    private var disclaimerGate: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Image(systemName: "exclamationmark.bubble")
                        .font(.largeTitle).foregroundStyle(BrandColor.accentText)
                    Text("Before you chat with Natt")
                        .font(Typo.title).foregroundStyle(BrandColor.textPrimary)
                    VStack(alignment: .leading, spacing: Space.md) {
                        gatePoint("It runs in the cloud. To answer, your questions and a snapshot of your PinWise data — your stack, dose logs, symptoms, labs, and any connected Health metrics — are sent securely to our AI provider for processing. See the Privacy Policy for what's shared and how it's handled.")
                        gatePoint("It's AI, and it can be wrong. Responses may be inaccurate, incomplete, or out of date — always fact-check them against the linked/primary sources.")
                        gatePoint("It is not medical advice. It does not diagnose, treat, or recommend doses. Decisions about your health belong with a licensed healthcare professional.")
                        gatePoint("You use it at your own risk. PinWise and its makers are not liable for any actions or outcomes based on Natt's responses.")
                    }
                    Text("By continuing you acknowledge and accept the above.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                }
                .padding(Space.lg)
            }
            PrimaryButton(title: "Accept & continue", systemImage: "checkmark") { aiConsentVersion = Disclaimer.currentVersion }
                .padding(.horizontal, Space.lg)
                .padding(.top, Space.sm)
                .padding(.bottom, Space.lg)
                .background(BrandColor.surface)
        }
    }

    private func gatePoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: "checkmark.shield").font(.body).foregroundStyle(BrandColor.warning).padding(.top, 2)
            Text(text).font(.callout).foregroundStyle(BrandColor.textPrimary)
        }
    }

    private var starterCard: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Ask about peptides, the science, or your own data. Try:")
                .font(.caption).foregroundStyle(BrandColor.textSecondary)
            ForEach(starters, id: \.self) { s in
                Button { Task { await ask(s) } } label: {
                    HStack {
                        Text(s).font(.body).foregroundStyle(BrandColor.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(BrandColor.textSecondary)
                    }
                    .padding(Space.md)
                    .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var snapshotCard: some View {
        VStack(spacing: Space.sm) {
            actionRow("Look up a compound", "magnifyingglass") { showCompounds = true }
            actionRow("Tiers & half-life explained", "questionmark.circle") { showLegend = true }
        }
    }

    private func actionRow(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.md) {
                Image(systemName: icon).font(.body).frame(width: 24).foregroundStyle(BrandColor.accentText)
                Text(title).font(.body).foregroundStyle(BrandColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
            }
            .padding(Space.md)
            .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func bubble(_ m: AssistantEngine.Message) -> some View {
        HStack {
            if m.isUser { Spacer(minLength: Space.xl) }
            Text(m.text)
                .font(.body)
                .foregroundStyle(m.isUser ? BrandColor.onAccent : BrandColor.textPrimary)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .background(m.isUser ? BrandColor.accent : BrandColor.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: .infinity, alignment: m.isUser ? .trailing : .leading)
            if !m.isUser { Spacer(minLength: Space.xl) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: Space.sm) {
            TextField("Ask Natt…", text: $input, axis: .vertical)
                .focused($inputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
            Button { Task { await ask(input) } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
                    .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty ? BrandColor.textSecondary : BrandColor.accent)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || engine.isThinking)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, Space.lg)
        .padding(.top, Space.sm)
        .padding(.bottom, Space.lg)
        .background(BrandColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(BrandColor.stroke).frame(height: 0.5) }
    }

    private func ask(_ text: String) async {
        let toSend = text
        input = ""
        inputFocused = false
        await engine.send(toSend, context: contextString)
    }
}
