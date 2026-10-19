// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings for the volume keys driving a monitor's own speakers over DDC:
/// the switch, how far one press moves, and the range the keys stay in.
struct DDCVolumeSettingsCard: View {
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.ddcVolumeEnabled) private var enabled = false
    @AppStorage(DefaultsKey.ddcVolumeStep) private var step = DDCVolumeSupport.defaultStepPercent
    @AppStorage(DefaultsKey.ddcVolumeMinimum) private var minimum = 0
    @AppStorage(DefaultsKey.ddcVolumeMaximum) private var maximum = 100

    var body: some View {
        SettingsCard(title: "Monitor speakers") {
            SettingsRow(symbol: "hifispeaker.fill", title: "Volume keys control monitor speakers",
                        caption: "When sound plays through a monitor over DisplayPort or HDMI, the volume and mute keys set the monitor's own speaker volume over DDC. Needs display control above to be on.") {
                Toggle("Volume keys control monitor speakers", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) { _, isOn in
                        if isOn { permissions.requestAccessibility() }
                        DDCVolumeService.shared.syncWithPreferences()
                    }
            }
            if enabled {
                Divider()
                SettingsRow(symbol: "plusminus", title: "Volume step",
                            caption: "How much one press changes the volume. Hold Option-Shift for a quarter of this.") {
                    Picker("Volume step", selection: stepBinding) {
                        ForEach(DDCVolumeSupport.stepChoices, id: \.self) { choice in
                            Text(DDCVolumeSupport.stepLabel(choice)).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(symbol: "speaker.fill", title: "Minimum volume",
                            caption: "Volume down stops here. Mute still silences the monitor.") {
                    limitControl(title: "Minimum volume", value: minimumBinding, range: 0...95)
                }
                SettingsRow(symbol: "speaker.wave.3.fill", title: "Maximum volume",
                            caption: "Volume up stops here.") {
                    limitControl(title: "Maximum volume", value: maximumBinding, range: 5...100)
                }
                if !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
            }
        }
    }

    /// A step stored before the choices changed shows as the nearest choice
    /// instead of an empty menu.
    private var stepBinding: Binding<Double> {
        Binding {
            let current = DDCVolumeSupport.sanitizedStep(step)
            return DDCVolumeSupport.stepChoices.min { abs($0 - current) < abs($1 - current) }
                ?? DDCVolumeSupport.defaultStepPercent
        } set: { step = $0 }
    }

    /// The limits keep at least five points between them: dragging one into
    /// the other pushes the other along.
    private var minimumBinding: Binding<Int> {
        Binding { minimum } set: { value in
            minimum = value
            if maximum < value + 5 { maximum = min(100, value + 5) }
        }
    }

    private var maximumBinding: Binding<Int> {
        Binding { maximum } set: { value in
            maximum = value
            if minimum > value - 5 { minimum = max(0, value - 5) }
        }
    }

    private func limitControl(title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { Double(value.wrappedValue) },
                                  set: { value.wrappedValue = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 5)
                .frame(width: 150)
                .accessibilityLabel(title)
            Text("\(value.wrappedValue)%")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}
