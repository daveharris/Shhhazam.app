//
//  MenuContentView.swift
//  Shhhazam
//
//  The popover shown from the menu bar: live meter, threshold slider,
//  sustain control, toggles, and mic-permission status.
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var monitor: AudioMonitor
    @ObservedObject var loginItem: LoginItemManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            levelSection
            sustainSection
            Divider()
            togglesSection
            if !monitor.micAuthorized {
                Divider()
                micWarning
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(.tint)
            Text("Shhhazam").font(.headline)
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)
        }
    }

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Input level")
                    .foregroundStyle(.secondary)
                Text(levelText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Threshold")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f dBFS", settings.thresholdDBFS))
                    .monospacedDigit()
            }
            // Live level is the bar fill; the draggable knob is the threshold.
            LevelThresholdSlider(level: monitor.levelDBFS,
                                 threshold: $settings.thresholdDBFS,
                                 floor: AudioMonitor.floorDB)
            Label(monitor.currentInputName, systemImage: "mic")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var sustainSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sustain before alerting")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f s", settings.sustainSeconds))
                    .monospacedDigit()
            }
            Slider(value: $settings.sustainSeconds, in: 0.5...10, step: 0.5)
        }
    }

    private var togglesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggleRow("Notify me when too loud", isOn: $settings.notificationsEnabled)
            toggleRow("Launch at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }))
        }
    }

    /// A toggle row whose switch is pinned to the trailing edge, so switches
    /// line up regardless of label length.
    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .toggleStyle(.switch)
    }

    private var micWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Microphone access is needed to measure input level.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Button("Open Privacy Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit Shhhazam") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: - Derived display values

    private var statusColor: Color {
        if monitor.isAlerting { return .red }
        if monitor.isOverThreshold { return .orange }
        return monitor.isRunning ? .green : .secondary
    }

    private var levelText: String {
        monitor.levelDBFS <= AudioMonitor.floorDB
            ? "—"
            : String(format: "%.0f dBFS", monitor.levelDBFS)
    }
}

/// A slider whose track fill shows the live input level (green, red when over)
/// and whose draggable knob sets the alert threshold. Tap or drag anywhere on
/// the bar to move the threshold.
struct LevelThresholdSlider: View {
    let level: Double
    @Binding var threshold: Double
    let floor: Double

    private let knobSize: CGFloat = 18
    private let trackHeight: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(1, width - knobSize)
            let knobX = knobSize / 2 + usable * fraction(threshold)
            let fillWidth = knobSize / 2 + usable * fraction(level)
            let over = level >= threshold

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(over ? Color.red : Color.green)
                    .frame(width: min(width, max(trackHeight, fillWidth)), height: trackHeight)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(.black.opacity(0.18)))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: knobX - knobSize / 2)
            }
            .frame(height: knobSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clampedX = min(max(value.location.x, knobSize / 2), width - knobSize / 2)
                        let frac = (clampedX - knobSize / 2) / usable
                        threshold = (floor + frac * (0 - floor)).rounded()
                    }
            )
        }
        .frame(height: knobSize)
    }

    /// Maps a dBFS value to 0...1 across the track (floor → left, 0 → right).
    private func fraction(_ db: Double) -> Double {
        let clamped = min(0, max(floor, db))
        return (clamped - floor) / (0 - floor)
    }
}
