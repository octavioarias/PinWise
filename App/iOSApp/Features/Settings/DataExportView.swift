import SwiftUI
import SwiftData

/// Exports the user's PinWise data — plus, if Apple Health is connected, the on-device health
/// snapshots — to a single CSV the user saves or shares via the system share sheet. This is the
/// USER exporting their OWN data (not PinWise disclosing to a third party), so it's compliant to
/// include the read Health metrics. The file is written to a temporary location and handed to
/// ShareLink; nothing is uploaded anywhere by this screen.
struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \LoggedDose.timestamp, order: .reverse) private var doses: [LoggedDose]
    @Query(sort: \SavedProtocol.startDate, order: .reverse) private var protocols: [SavedProtocol]
    @Query(sort: \StoredVial.dateAcquired, order: .reverse) private var vials: [StoredVial]
    @Query(sort: \SymptomEntry.timestamp, order: .reverse) private var symptoms: [SymptomEntry]
    @Query(sort: \BiomarkerEntry.timestamp, order: .reverse) private var biomarkers: [BiomarkerEntry]
    @Query(sort: \HealthSnapshot.timestamp, order: .reverse) private var health: [HealthSnapshot]

    @State private var exportURL: URL?

    private var totalRows: Int {
        doses.count + protocols.count + vials.count + symptoms.count + biomarkers.count + health.count
    }

    var body: some View {
        MenuSheet(title: "Export data") {
            Card {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader(title: "Your data, as a CSV")
                    Text("Exports everything you've logged in PinWise — doses, protocols, vials, symptoms, and lab/metric entries — plus your Apple Health snapshots if you've connected Health. It stays yours: the file goes wherever you send it, and nothing is uploaded here.")
                        .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    countRow("Doses", doses.count)
                    countRow("Protocols", protocols.count)
                    countRow("Vials", vials.count)
                    countRow("Symptoms", symptoms.count)
                    countRow("Labs & metrics", biomarkers.count)
                    countRow("Apple Health days", health.count)
                }
            }

            if let url = exportURL {
                ShareLink(item: url) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(BrandColor.accent, in: Capsule())
                        .foregroundStyle(BrandColor.onAccent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Space.lg)
            } else {
                Text(totalRows == 0 ? "Nothing to export yet — log a dose or connect Health first."
                                    : "Preparing your file…")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: prepareFile)
    }

    private func countRow(_ label: String, _ n: Int) -> some View {
        HStack {
            Text(label).font(Typo.body).foregroundStyle(BrandColor.textPrimary)
            Spacer()
            Text("\(n)").font(.caption.weight(.semibold)).foregroundStyle(BrandColor.textSecondary)
        }
        .padding(.vertical, 1)
    }

    /// Build the CSV and write it to a temp file for ShareLink. No-op if there's nothing to export.
    private func prepareFile() {
        guard totalRows > 0 else { return }
        let csv = DataExportBuilder.csv(
            doses: doses, protocols: protocols, vials: vials,
            symptoms: symptoms, biomarkers: biomarkers, health: health)
        let name = "PinWise-export-\(Self.stamp.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportURL = nil
        }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Pure CSV assembly, kept out of the view so it's easy to reason about. Produces one file with a
/// titled section per data type (a "# Section" line, a header row, then data rows). Values are RFC-
/// 4180 quoted. Doses are exported in canonical micrograms (lossless); Health weight in kg.
enum DataExportBuilder {
    static func csv(doses: [LoggedDose], protocols: [SavedProtocol], vials: [StoredVial],
                    symptoms: [SymptomEntry], biomarkers: [BiomarkerEntry], health: [HealthSnapshot]) -> String {
        var out = "PinWise data export,generated,\(iso.string(from: Date()))\n"

        out += "\n# Doses\n"
        out += row(["timestamp", "compound", "dose_mcg", "site", "energy_0_10", "side_effect_0_10", "notes"])
        for d in doses {
            out += row([iso.string(from: d.timestamp), d.compoundName, num(d.doseMicrograms),
                        d.siteRaw ?? "", optNum(d.energy), optNum(d.sideEffectSeverity), d.notes])
        }

        out += "\n# Protocols\n"
        out += row(["name", "compounds", "cadence", "active", "start_date", "notes"])
        for p in protocols {
            out += row([p.name, p.compoundNames.joined(separator: " + "), p.cadenceText,
                        p.isActive ? "yes" : "no", iso.string(from: p.startDate), p.notes])
        }

        out += "\n# Vials\n"
        out += row(["name", "contents_mcg", "premixed", "doses_taken", "total_doses", "acquired", "expires", "notes"])
        for v in vials {
            let contents = v.apis.map { "\($0.name) \(num($0.massMicrograms)) mcg" }.joined(separator: " + ")
            out += row([v.displayName, contents, v.isPremixed ? "yes" : "no",
                        String(v.dosesTaken), String(v.totalDoses), iso.string(from: v.dateAcquired),
                        v.expirationDate.map { iso.string(from: $0) } ?? "", v.notes])
        }

        out += "\n# Symptoms\n"
        out += row(["timestamp", "symptom", "severity_0_10", "notes"])
        for s in symptoms {
            out += row([iso.string(from: s.timestamp), s.symptomRaw, String(s.severity), s.notes])
        }

        out += "\n# Labs and metrics\n"
        out += row(["timestamp", "type", "value", "unit", "notes"])
        for b in biomarkers {
            out += row([iso.string(from: b.timestamp), b.typeRaw, num(b.value), b.unitRaw ?? "", b.notes])
        }

        out += "\n# Apple Health (on-device snapshots)\n"
        out += row(["timestamp", "weight_kg", "resting_hr_bpm", "hrv_ms", "sleep_hours", "steps"])
        for h in health {
            out += row([iso.string(from: h.timestamp), optNum(h.weightKg), optNum(h.restingHeartRate),
                        optNum(h.hrvMilliseconds), optNum(h.sleepHoursLastNight), optNum(h.stepsToday)])
        }

        return out
    }

    private static let iso: ISO8601DateFormatter = ISO8601DateFormatter()

    private static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",") + "\n"
    }

    /// RFC-4180: wrap in quotes and double any embedded quotes when the value has a comma, quote,
    /// or newline; otherwise emit as-is.
    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Trim trailing zeros so 250.0 → "250" but 12.5 stays "12.5".
    private static func num(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%g", d)
    }
    private static func optNum(_ d: Double?) -> String { d.map(num) ?? "" }
}
