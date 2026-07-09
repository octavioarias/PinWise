import SwiftUI
import PeptideKit

// Shared atoms for the Tools suite — the components every dose calculator reuses. These
// reference PeptideKit types (MassUnit, SyringeScale), which keeps them out of the generic
// kit in PinWiseComponents.swift: tool instruments live here, app-wide chrome lives there.

/// A flat schematic syringe barrel that visualizes a computed draw — display-only (WHOOP
/// strain-bar register: an instrument readout, not a scrubber; the plunger marker is a
/// line, not a draggable circle).
///
/// Capacity assumption: a **1 mL barrel** — capacity = `syringe.unitsPerMilliliter` units
/// (U-100 → 100 u, U-50 → 50 u, U-40 → 40 u), the most common insulin-syringe size for
/// all three scales. PeptideKit does not model barrel size (`SyringeScale` exposes only
/// `unitsPerMilliliter`), so the assumption lives UI-side; 0.5/0.3 mL barrels exist, which
/// is why the over-capacity message says "a full syringe", never "your syringe".
///
/// Over-capacity (`units > fullScale`): the fill caps at 100%, fill + marker switch to
/// `BrandColor.danger` (a legitimate status use — "does not fit" IS a stop condition),
/// and a caption row below advises splitting into two draws.
struct SyringeGauge: View {
    let units: Double
    let syringe: SyringeScale
    var fill: Color = BrandColor.accentText

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fullScale: Double { syringe.unitsPerMilliliter }
    private var isOver: Bool { units > fullScale }

    // Fixed vertical metrics: 4pt marker overhang above the track, 14pt track, 2pt gap,
    // 6pt ticks, 2pt gap, ~12pt label row → 40pt total.
    private let trackHeight: CGFloat = 14
    private let markerOverhang: CGFloat = 4
    private let tickHeight: CGFloat = 6
    private let gaugeHeight: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geo in
                let width = geo.size.width
                // Fill sits inset 2pt inside the track; over-capacity caps at 100%.
                let fillWidth = max(0, (width - 4) * min(units / fullScale, 1))
                let tickY = markerOverhang + trackHeight + 2
                let labelY = tickY + tickHeight + 2

                ZStack(alignment: .topLeading) {
                    // Barrel track — the pinwiseField vocabulary: an instrument, not a card.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BrandColor.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(BrandColor.stroke, lineWidth: 1)
                        )
                        .frame(width: width, height: trackHeight)
                        .offset(y: markerOverhang)

                    // 11 major graduations at every fullScale/10 (U-100: 10 u, U-50: 5 u,
                    // U-40: 4 u) — exact computed offsets, never HStack spacing, so ticks
                    // stay aligned at any width. No minor ticks: they smear at card width.
                    ForEach(0..<11, id: \.self) { i in
                        let x = width * CGFloat(i) / 10
                        Rectangle()
                            .fill(BrandColor.stroke)
                            .frame(width: 1.5, height: tickHeight)
                            .offset(x: min(max(x - 0.75, 0), width - 1.5), y: tickY)
                    }

                    // Numerals at 0 / half / full only — always fits, never truncates.
                    // Text wears text tokens, never the series color.
                    tickLabel(0)
                        .frame(width: width, alignment: .leading)
                        .offset(y: labelY)
                    tickLabel(fullScale / 2)
                        .frame(width: width, alignment: .center)
                        .offset(y: labelY)
                    tickLabel(fullScale)
                        .frame(width: width, alignment: .trailing)
                        .offset(y: labelY)

                    // Flat fill — no gradient (there are no zones here; sequential = one hue).
                    if fillWidth > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isOver ? BrandColor.danger : fill)
                            .frame(width: fillWidth, height: trackHeight - 4)
                            .offset(x: 2, y: markerOverhang + 2)
                    }

                    // Plunger marker at the fill edge — a 2pt line with 4pt overhang each
                    // side. Hidden at zero: an empty barrel needs no plunger.
                    if units > 0 {
                        Rectangle()
                            .fill(isOver ? BrandColor.danger : BrandColor.textPrimary)
                            .frame(width: 2, height: trackHeight + markerOverhang * 2)
                            .offset(x: min(max(2 + fillWidth - 1, 0), width - 2), y: 0)
                    }
                }
                .animation(reduceMotion ? nil : Motion.emphasis, value: units)
            }
            .frame(height: gaugeHeight)

            if isOver {
                HStack(spacing: Space.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("More than one full syringe — split into two draws.")
                }
                .font(.caption)
                .foregroundStyle(BrandColor.danger)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Syringe draw")
        .accessibilityValue(
            "\(formatted(units)) of \(formatted(fullScale)) units on a \(syringe.rawValue) syringe"
                + (isOver ? ", more than one full syringe" : "")
        )
    }

    private func tickLabel(_ value: Double) -> some View {
        Text(formatted(value))
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(BrandColor.textSecondary)
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Segmented mcg/mg unit control shared by the dose calculators — the promoted form of
/// ToolsView's file-private `unitPicker` (identical behavior: fixed 120pt width so it
/// pairs with a flexible text field).
struct MassUnitPicker: View {
    @Binding var selection: MassUnit

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).frame(width: 120)
    }
}

/// Shared "Advanced — syringe type" disclosure (hidden by default; most people use U-100).
/// The promoted form of ToolsView's file-private `syringeAdvanced`.
struct SyringeAdvancedCard: View {
    @Binding var selection: SyringeScale

    var body: some View {
        Card {
            DisclosureGroup {
                Picker("Syringe type", selection: $selection) {
                    ForEach(SyringeScale.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Most insulin syringes are U-100. Only change this if yours says otherwise.")
                    .font(.caption).foregroundStyle(BrandColor.textSecondary).padding(.top, Space.xs)
            } label: {
                Text("Advanced — syringe type").font(.caption).foregroundStyle(BrandColor.textSecondary)
            }
            .tint(BrandColor.accentText)
        }
    }
}
