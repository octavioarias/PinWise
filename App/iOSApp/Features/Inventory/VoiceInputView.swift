import SwiftUI
import PeptideKit

/// Add a vial by voice: speak the details → on-device transcription (`VoiceTranscriber`) → the same
/// on-device extractor the photo scanner uses (`LabelAI`) → confirmable fields. Mirrors
/// `LabelScannerView`'s confirm-before-use flow, and its result routes to pre-mixed vs powder the
/// same way (a per-mL strength ⇒ pre-mixed; a bare mass ⇒ powder).
struct VoiceInputView: View {
    var extraCompoundNames: [String] = []
    let onApply: (ScannedLabel) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var voice = VoiceTranscriber()
    @State private var result: ScannedLabel?
    @State private var isReading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Say the vial's details out loud — for example, “BPC-157, 10 milligrams, expires December 2026.” PinWise transcribes it on your device; nothing is uploaded.")
                        .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                    if !voice.isSupported {
                        Text("Voice input isn't available on this device.")
                            .font(.footnote).foregroundStyle(BrandColor.warning)
                    } else {
                        micButton
                        if !voice.transcript.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: Space.sm) {
                                    SectionHeader(title: voice.isListening ? "Listening…" : "Heard")
                                    Text(voice.transcript).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
                                }
                            }
                        }
                    }

                    if isReading {
                        HStack(spacing: Space.sm) { ProgressView(); Text("Reading…").font(.caption).foregroundStyle(BrandColor.textSecondary) }
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(BrandColor.warning)
                    }
                    if let result { resultCard(result) }

                    DisclaimerBanner(text: "Voice reading can mishear — always double-check every value before saving.")
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Speak the details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { voice.stop(); dismiss() } } }
            .onDisappear { voice.stop() }
        }
    }

    private var micButton: some View {
        Button {
            if voice.isListening { Task { await stopAndRead() } } else { Task { await startListening() } }
        } label: {
            Label(voice.isListening ? "Stop & read" : "Start speaking",
                  systemImage: voice.isListening ? "stop.fill" : "mic.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, Space.md)
                .background(voice.isListening ? BrandColor.accent : BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                .foregroundStyle(voice.isListening ? BrandColor.onAccent : BrandColor.accentText)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func resultCard(_ r: ScannedLabel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "From what you said")
                row("Compound", r.compoundName ?? "—")
                row("Strength", strengthText(r.strength))
                row("Vial size", r.volumeMl.map { fmt($0) + " mL" } ?? "—")
                row("Expires", r.expiration.map { $0.formatted(.dateTime.month().day().year()) } ?? "—")
                if r.isEmpty {
                    Text("Didn't catch the usual details. Try again — say the compound, the dose, and any volume or expiry clearly.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                } else {
                    PrimaryButton(title: "Use these details", systemImage: "checkmark") {
                        onApply(r); dismiss()
                    }
                }
            }
        }
    }

    private func strengthText(_ s: ScannedLabel.Strength?) -> String {
        switch s {
        case .concentrationMgPerMl(let c): return String(format: "%.2f mg/mL", c)
        case .massMilligrams(let m): return fmt(m) + " mg"
        case nil: return "—"
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(BrandColor.textSecondary)
            Spacer()
            Text(value).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    private func startListening() async {
        result = nil; error = nil
        guard await voice.authorize() else {
            error = "Microphone or speech access was denied. Enable it in Settings to use voice."
            return
        }
        voice.start()
    }

    private func stopAndRead() async {
        voice.stop()
        guard !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "Didn't catch anything — try again."
            return
        }
        isReading = true
        defer { isReading = false }
        result = await voice.scannedLabel(extraNames: extraCompoundNames)
    }
}
