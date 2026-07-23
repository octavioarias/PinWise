import SwiftUI
import PhotosUI
import Vision
import UIKit
import PeptideKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What we could pull off a vial / pharmacy label. All optional — the user confirms/edits before
/// it's used. Nothing here is auto-committed to a vial.
struct ScannedLabel {
    /// The vial's stated strength. The two cases are NOT interchangeable and drive whether the vial
    /// is treated as pre-mixed liquid or reconstitutable powder:
    /// - `concentrationMgPerMl`: a literal per-volume strength ("2.5 mg/mL") — a pre-mixed vial.
    /// - `massMilligrams`: a bare total mass ("10 mg") with no "/mL" — lyophilized powder.
    /// A bare mass is NEVER read as a concentration (that would be a 10×+ dosing error).
    enum Strength: Equatable {
        case massMilligrams(Double)
        case concentrationMgPerMl(Double)
    }

    /// Fields the reader flags as uncertain, so the UI can tell the user what to double-check.
    enum Field: Hashable { case name, strength, volume, expiration }

    var compoundName: String?
    var strength: Strength?
    var volumeMl: Double?
    var lotNumber: String?
    var expiration: Date?
    var lowConfidenceFields: Set<Field> = []
    var rawText: String

    var isEmpty: Bool { compoundName == nil && strength == nil && volumeMl == nil && expiration == nil }
}

/// On-device label reading via Apple's Vision text recognition — the photo never leaves the phone,
/// there's no network call and no cloud model. It only extracts text and pattern-matches known
/// values. This is the deterministic floor used directly on older devices and as the fallback when
/// Apple Intelligence isn't available.
enum LabelParser {
    static func recognizeText(_ cg: CGImage) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                let handler = VNImageRequestHandler(cgImage: cg, options: [:])
                try? handler.perform([request])
                let lines = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
        }
    }

    static func parse(_ text: String, extraNames: [String] = []) -> ScannedLabel {
        let lower = text.lowercased()
        var strength: ScannedLabel.Strength?

        // Concentration FIRST — a literal per-volume strength ("2.5 mg/mL", or mcg/mL → convert).
        if let v = number(#"([0-9]+(?:\.[0-9]+)?)\s*mg\s*/\s*ml"#, in: lower) {
            strength = .concentrationMgPerMl(v)
        } else if let v = number(#"([0-9]+(?:\.[0-9]+)?)\s*(?:mcg|µg|ug)\s*/\s*ml"#, in: lower) {
            strength = .concentrationMgPerMl(v / 1000)
        // Otherwise a BARE mass ("10 mg", "500 mcg") with no "/mL" is total powder mass — never a
        // concentration. The negative lookahead guards against matching the "mg" inside "mg/mL".
        } else if let v = number(#"([0-9]+(?:\.[0-9]+)?)\s*mg(?!\s*/\s*ml)"#, in: lower) {
            strength = .massMilligrams(v)
        } else if let v = number(#"([0-9]+(?:\.[0-9]+)?)\s*(?:mcg|µg|ug)(?!\s*/\s*ml)"#, in: lower) {
            strength = .massMilligrams(v / 1000)
        }

        // Volume: "3 mL"
        let volume = number(#"([0-9]+(?:\.[0-9]+)?)\s*ml\b"#, in: lower)
        // Lot / batch code (case-insensitive over the original text).
        let lot = firstMatch(#"(?:lot|batch)\s*(?:no\.?|number|#|:)?\s*([A-Za-z0-9][A-Za-z0-9\-]{1,})"#,
                             in: text, options: [.caseInsensitive])

        return ScannedLabel(
            compoundName: matchName(candidate: nil, rawText: text, extraNames: extraNames),
            strength: strength,
            volumeMl: volume,
            lotNumber: lot,
            expiration: date(in: text),   // expiry is usually the latest date printed
            rawText: text
        )
    }

    /// Resolve a compound name to catalog identity. Tries the model's candidate (when present),
    /// then a substring scan of the raw text — the user's own compounds first, then the catalog +
    /// aliases. Returns the candidate verbatim if nothing matches (may be a not-yet-added compound).
    static func matchName(candidate: String?, rawText: String, extraNames: [String]) -> String? {
        if let cand = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !cand.isEmpty {
            let cl = cand.lowercased()
            for name in extraNames where !name.isEmpty {
                let nl = name.lowercased()
                if cl.contains(nl) || nl.contains(cl) { return name }
            }
            for compound in CompoundCatalog.all {
                for n in [compound.name] + compound.aliases {
                    let nl = n.lowercased()
                    if cl.contains(nl) || nl.contains(cl) { return compound.name }
                }
            }
            return cand
        }
        let lower = rawText.lowercased()
        for name in extraNames where !name.isEmpty && lower.contains(name.lowercased()) { return name }
        for compound in CompoundCatalog.all {
            for n in [compound.name] + compound.aliases where lower.contains(n.lowercased()) {
                return compound.name
            }
        }
        return nil
    }

    /// Latest date the detector finds in the text (expiry is usually the latest date printed).
    static func date(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let dates = (detector?.matches(in: text, range: range) ?? []).compactMap { $0.date }
        return dates.max()
    }

    private static func number(_ pattern: String, in s: String) -> Double? {
        firstMatch(pattern, in: s).flatMap(Double.init)
    }

    private static func firstMatch(_ pattern: String, in s: String,
                                   options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}

/// On-device structured extraction. Where Apple Intelligence is available (iOS 26+ with a supported
/// device) it reads the OCR text with the on-device model — which handles vendor name variants and,
/// critically, the mass-vs-concentration distinction the regex parser can only approximate. Still
/// 100% on-device: no network, no API keys, no usage cost. Falls back to `LabelParser` everywhere
/// else, and on any model error. Accepts already-combined OCR text, so a caller may OCR one photo
/// or several and concatenate before extraction.
enum LabelAI {
    static func extract(from text: String, extraNames: [String]) async -> ScannedLabel {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability,
               let reading = await modelReading(text: text) {
                return reading.scannedLabel(rawText: text, extraNames: extraNames)
            }
        }
        #endif
        return LabelParser.parse(text, extraNames: extraNames)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func modelReading(text: String) async -> LabelReading? {
        let instructions = """
        You extract structured fields describing a peptide or medication vial. The text may be OCR \
        read from the label by camera, or a spoken description the user dictated. Return ONLY what \
        the text actually states — never guess, infer, or invent a value; when unsure, leave a \
        field null and list it in uncertainFields.

        CRITICAL SAFETY RULE about strength:
        - A bare mass such as "10 mg", "5mg", or "500 mcg" — with NO "/mL" or "per mL" — is the \
        TOTAL powder mass in the vial. Put it in totalMassMilligrams and leave concentrationMgPerMl \
        null.
        - Only a literal per-volume strength like "2.5 mg/mL" or "250 mcg/mL" is a concentration; \
        put it in concentrationMgPerMl.
        - NEVER convert a bare mass into a concentration, and never do the reverse.
        Convert micrograms (mcg / µg / ug) to milligrams when filling either field.
        """
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "OCR text from the vial label (may span multiple photos):\n\(text)",
                generating: LabelReading.self
            )
            return response.content
        } catch {
            return nil
        }
    }
    #endif
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct LabelReading {
    @Guide(description: "The peptide or compound name printed on the label, e.g. \"BPC-157\", \"Semaglutide\", \"GHK-Cu\". Null if none is clearly present.")
    var compoundName: String?
    @Guide(description: "TOTAL powder mass in the vial, in MILLIGRAMS, taken from a bare mass like \"10 mg\" or \"5mg\" that has NO \"/mL\". Convert mcg to mg. Null unless a bare total mass is printed.")
    var totalMassMilligrams: Double?
    @Guide(description: "Concentration in mg per mL — ONLY when the label literally shows a per-volume strength such as \"2.5 mg/mL\". Never derive this from a bare mass. Null otherwise.")
    var concentrationMgPerMl: Double?
    @Guide(description: "Total liquid volume of the vial in mL, e.g. from \"3 mL\". Null if not printed.")
    var volumeMl: Double?
    @Guide(description: "Lot or batch number/code if printed. Null otherwise.")
    var lotNumber: String?
    @Guide(description: "The expiration / beyond-use / discard date exactly as printed, in any format (e.g. \"2026-12-01\", \"12/2026\"). Null if none.")
    var expirationText: String?
    @Guide(description: "Names of fields you are UNSURE about. Use only these tokens: name, strength, volume, expiration. Include a field when the source text was ambiguous or low quality.")
    var uncertainFields: [String]

    func scannedLabel(rawText: String, extraNames: [String]) -> ScannedLabel {
        var strength: ScannedLabel.Strength?
        if let c = concentrationMgPerMl, c > 0 {
            strength = .concentrationMgPerMl(c)
        } else if let m = totalMassMilligrams, m > 0 {
            strength = .massMilligrams(m)
        }
        var flags: Set<ScannedLabel.Field> = []
        for f in uncertainFields {
            switch f.lowercased() {
            case "name", "compound": flags.insert(.name)
            case "strength", "concentration", "mass", "dose": flags.insert(.strength)
            case "volume": flags.insert(.volume)
            case "expiration", "expiry", "date": flags.insert(.expiration)
            default: break
            }
        }
        return ScannedLabel(
            compoundName: LabelParser.matchName(candidate: compoundName, rawText: rawText, extraNames: extraNames),
            strength: strength,
            volumeMl: (volumeMl ?? 0) > 0 ? volumeMl : nil,
            lotNumber: lotNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
            expiration: expirationText.flatMap { LabelParser.date(in: $0) },
            lowConfidenceFields: flags,
            rawText: rawText
        )
    }
}
#endif

/// Photo → on-device OCR → on-device extraction → parsed fields the user can apply to the vial.
struct LabelScannerView: View {
    /// Names beyond the catalog the reader should recognize (the user's own compounds).
    var extraCompoundNames: [String] = []
    let onApply: (ScannedLabel) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var isWorking = false
    @State private var result: ScannedLabel?
    @State private var error: String?
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("Choose a clear photo of the pharmacy label. PinWise reads it on your device — the photo isn't uploaded anywhere.")
                        .font(Typo.body).foregroundStyle(BrandColor.textSecondary)

                    HStack(spacing: Space.md) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { pickerButtonLabel("Take a photo", "camera.fill") }
                                .buttonStyle(.plain)
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            pickerButtonLabel(image == nil ? "Choose a photo" : "Choose another", "photo")
                        }
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
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(isPresented: $showCamera) { ui in Task { await handle(ui) } }
                    .ignoresSafeArea()
            }
        }
    }

    private func pickerButtonLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity).padding(.vertical, Space.md)
            .background(BrandColor.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(BrandColor.stroke, lineWidth: 1))
            .foregroundStyle(BrandColor.accentText)
    }

    @ViewBuilder private func resultCard(_ r: ScannedLabel) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionHeader(title: "Found on the label")
                row("Compound", r.compoundName ?? "—")
                row("Concentration", concentrationText(r.strength))
                row("Vial size", r.volumeMl.map { fmt($0) + " mL" } ?? "—")
                row("Expires", r.expiration.map { $0.formatted(.dateTime.month().day().year()) } ?? "—")
                if r.isEmpty {
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

    /// Original card shows a mg/mL concentration; a bare-mass (powder) reading has no concentration
    /// to display here, so it reads "—" (the mass still flows through to the form via `onApply`).
    private func concentrationText(_ s: ScannedLabel.Strength?) -> String {
        if case .concentrationMgPerMl(let c) = s { return String(format: "%.2f mg/mL", c) }
        return "—"
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
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else {
            error = "Couldn't load that image."; return
        }
        await handle(ui)
    }

    /// Shared pipeline for a captured or picked image: OCR on-device, then extract fields (on-device
    /// Apple Intelligence where available, else the regex parser).
    private func handle(_ ui: UIImage) async {
        image = ui; isWorking = true; error = nil; result = nil
        defer { isWorking = false }
        guard let cg = ui.cgImage else { error = "Couldn't read that image."; return }
        let text = await LabelParser.recognizeText(cg)
        guard !text.isEmpty else { error = "No text found. Try a clearer, closer photo."; return }
        result = await LabelAI.extract(from: text, extraNames: extraCompoundNames)
    }
}

/// Minimal camera capture (UIImagePickerController) for photographing a vial label.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.isPresented = false
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
