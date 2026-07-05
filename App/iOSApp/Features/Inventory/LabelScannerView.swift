import SwiftUI
import PhotosUI
import Vision
import UIKit
import PeptideKit

/// What we could pull off a pharmacy label. All optional — the user confirms/edits before it's used.
struct ScannedLabel {
    var compoundName: String?
    var concentrationMgPerMl: Double?
    var volumeMl: Double?
    var expiration: Date?
    var rawText: String
}

/// On-device label reading. Uses Apple's Vision text recognition — the photo never leaves the
/// phone, there's no network call and no cloud model, so it's private by construction and can't
/// give advice. It only extracts text and pattern-matches known values.
enum LabelParser {
    static func recognizeText(_ cg: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([request])
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }

    static func parse(_ text: String) -> ScannedLabel {
        var result = ScannedLabel(rawText: text)
        let lower = text.lowercased()

        // Concentration: "2.5 mg/mL" (or mcg/mL → convert).
        if let v = number(#"([0-9]+(?:\.[0-9]+)?)\s*mg\s*/\s*ml"#, in: lower) {
            result.concentrationMgPerMl = v
        } else if let v = number(#"([0-9]+(?:\.[0-9]+)?)\s*(?:mcg|µg|ug)\s*/\s*ml"#, in: lower) {
            result.concentrationMgPerMl = v / 1000
        }
        // Volume: "3 mL"
        if let v = number(#"([0-9]+(?:\.[0-9]+)?)\s*ml\b"#, in: lower) {
            result.volumeMl = v
        }
        // Compound: match a catalog name or alias.
        outer: for compound in CompoundCatalog.all {
            for name in [compound.name] + compound.aliases where lower.contains(name.lowercased()) {
                result.compoundName = compound.name
                break outer
            }
        }
        // Expiration: pick the latest date the detector finds (expiry is usually the latest).
        result.expiration = latestDate(in: text)
        return result
    }

    private static func number(_ pattern: String, in s: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Double(s[r])
    }

    private static func latestDate(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let dates = (detector?.matches(in: text, range: range) ?? []).compactMap { $0.date }
        return dates.max()
    }
}

/// Photo → on-device OCR → parsed fields the user can apply to the vial.
struct LabelScannerView: View {
    let onApply: (ScannedLabel) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var isWorking = false
    @State private var result: ScannedLabel?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Choose a clear photo of the pharmacy label. PinWise reads it on your device — the photo isn't uploaded anywhere.")
                        .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(image == nil ? "Choose a photo" : "Choose a different photo", systemImage: "photo")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, Space.md)
                            .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
                            .foregroundStyle(BrandColor.accentText)
                    }

                    if let image {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 220).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }

                    if isWorking {
                        HStack(spacing: Space.sm) { ProgressView(); Text("Reading label…").font(.caption).foregroundStyle(BrandColor.textSecondary) }
                    }

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(BrandColor.warning)
                    }

                    if let result { resultCard(result) }

                    DisclaimerBanner(text: "Scanning reads text only and can misread — always double-check every value against the label.")
                }
                .padding(Space.lg)
            }
            .heroScreen()
            .navigationTitle("Scan label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in if let item { Task { await load(item) } } }
        }
    }

    @ViewBuilder private func resultCard(_ r: ScannedLabel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Found on the label")
                row("Compound", r.compoundName ?? "—")
                row("Concentration", r.concentrationMgPerMl.map { String(format: "%.2f mg/mL", $0) } ?? "—")
                row("Vial size", r.volumeMl.map { fmt($0) + " mL" } ?? "—")
                row("Expires", r.expiration.map { $0.formatted(.dateTime.month().day().year()) } ?? "—")
                if r.compoundName == nil && r.concentrationMgPerMl == nil && r.volumeMl == nil {
                    Text("Couldn't recognize the usual fields. Try a closer, straighter photo — or just enter them by hand.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                } else {
                    PrimaryButton(title: "Use these details", systemImage: "checkmark") {
                        onApply(r); dismiss()
                    }
                }
            }
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

    private func load(_ item: PhotosPickerItem) async {
        isWorking = true; error = nil; result = nil
        defer { isWorking = false }
        guard let outer = try? await item.loadTransferable(type: Data.self),
              let data = outer, let ui = UIImage(data: data) else {
            error = "Couldn't load that image."; return
        }
        image = ui
        guard let cg = ui.cgImage else { error = "Couldn't read that image."; return }
        let text = await LabelParser.recognizeText(cg)
        guard !text.isEmpty else { error = "No text found. Try a clearer, closer photo."; return }
        result = LabelParser.parse(text)
    }
}
