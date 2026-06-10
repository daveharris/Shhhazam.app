//
//  AudioMonitor.swift
//  Shhhazam
//
//  Taps the *current system default* input device, measures its level in
//  dBFS, and decides when we've been too loud for long enough to alert.
//
//  Following the default input across changes (e.g. plugging in AirPods mid-run)
//  is handled two ways:
//    1. A CoreAudio listener on kAudioHardwarePropertyDefaultInputDevice fires
//       when the system default input switches — we rebuild the engine, and a
//       fresh AVAudioEngine binds to whatever the current default device is.
//    2. AVAudioEngineConfigurationChange fires when the active device's format
//       (sample rate / channels) changes — we rebuild the tap to match.
//

import Foundation
import AVFoundation
import CoreAudio
import Combine

@MainActor
final class AudioMonitor: ObservableObject {
    /// Smoothed input level in dBFS (floorDB ... 0).
    @Published private(set) var levelDBFS: Double = floorDB
    /// True while the smoothed level is at/above the threshold right now.
    @Published private(set) var isOverThreshold = false
    /// True once we've been continuously over threshold for `sustainSeconds`.
    @Published private(set) var isAlerting = false
    /// True while the engine is actively monitoring.
    @Published private(set) var isRunning = false
    /// Human-readable name of the device currently being monitored.
    @Published private(set) var currentInputName = "—"
    /// Whether microphone access has been granted.
    @Published private(set) var micAuthorized = false

    /// dBFS floor so log10(0) doesn't blow up; also the meter's left edge.
    nonisolated static let floorDB: Double = -80
    /// Reset sits this far below the trigger so the state doesn't flap.
    private let hysteresisDB: Double = 3
    /// If you stay continuously over the threshold, re-alert every
    /// `sustainSeconds * reAlertMultiplier` so it keeps nagging.
    private let reAlertMultiplier: Double = 10
    /// Meter smoothing (0..1); higher reacts faster.
    private let smoothing: Double = 0.25

    private let settings: AppSettings
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    private var aboveSince: Date?
    private var lastAlertAt: Date?
    private var rebuildToken = 0

    /// Called when we cross from "fine" to "too loud, sustained".
    private var onAlert: (() -> Void)?

    init(settings: AppSettings) {
        self.settings = settings
        self.micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func setAlertHandler(_ handler: @escaping () -> Void) {
        onAlert = handler
    }

    // MARK: - Lifecycle

    /// Requests microphone access if needed, then begins monitoring.
    func requestMicAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micAuthorized = true
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.micAuthorized = granted
                    if granted { self.start() }
                }
            }
        default:
            micAuthorized = false
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        installDefaultDeviceListener()
        rebuildEngine()
    }

    func stop() {
        isRunning = false
        removeDefaultDeviceListener()
        teardownEngine()
        levelDBFS = AudioMonitor.floorDB
        isOverThreshold = false
        isAlerting = false
        aboveSince = nil
        lastAlertAt = nil
    }

    // MARK: - Engine

    private func rebuildEngine() {
        teardownEngine()
        guard isRunning else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Touching the input format binds the underlying audio unit to the
        // current default input device.
        let format = input.inputFormat(forBus: 0)

        // No usable input yet (0 Hz right after a device switch) — retry shortly.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            scheduleRebuild(after: 0.5)
            return
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            let db = AudioMonitor.dbFS(of: buffer)
            Task { @MainActor in self?.ingest(db) }
        }

        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
            currentInputName = AudioMonitor.defaultInputDeviceName() ?? "Unknown device"
        } catch {
            self.engine = nil
            scheduleRebuild(after: 1.0)
            return
        }

        // Rebuild the tap if the active device's format changes underneath us.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild(after: 0.2) }
        }
    }

    private func teardownEngine() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
    }

    /// Debounced rebuild — device/format change notifications can arrive in bursts.
    private func scheduleRebuild(after delay: TimeInterval) {
        rebuildToken += 1
        let token = rebuildToken
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard self.isRunning, token == self.rebuildToken else { return }
            self.rebuildEngine()
        }
    }

    // MARK: - Level handling

    private func ingest(_ rawDB: Double) {
        // Exponential smoothing for a calmer meter and steadier triggering.
        levelDBFS += (rawDB - levelDBFS) * smoothing

        let threshold = settings.thresholdDBFS
        let resetLevel = threshold - hysteresisDB
        let now = Date()

        if levelDBFS >= threshold {
            isOverThreshold = true
            if aboveSince == nil { aboveSince = now }

            // Must be sustained past the window before anything fires.
            guard now.timeIntervalSince(aboveSince!) >= settings.sustainSeconds else { return }

            // Fire on the first sustained breach, then again every cooldown for
            // as long as we stay over the threshold.
            let cooldown = settings.sustainSeconds * reAlertMultiplier
            let due = lastAlertAt.map { now.timeIntervalSince($0) >= cooldown } ?? true
            if due {
                lastAlertAt = now
                isAlerting = true
                onAlert?()
            }
        } else if levelDBFS < resetLevel {
            // Dropped clearly below threshold — re-arm so the next breach alerts
            // after the sustain window again.
            isOverThreshold = false
            isAlerting = false
            aboveSince = nil
            lastAlertAt = nil
        }
        // Between resetLevel and threshold: hold current state (hysteresis band).
    }

    // MARK: - Signal math

    /// RMS level of a buffer expressed in dBFS, floored at `floorDB`.
    nonisolated static func dbFS(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData else { return floorDB }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return floorDB }

        let channels = Int(buffer.format.channelCount)
        var sumSquares: Double = 0
        for c in 0..<channels {
            let samples = channelData[c]
            for i in 0..<frames {
                let s = Double(samples[i])
                sumSquares += s * s
            }
        }

        let meanSquare = sumSquares / Double(frames * channels)
        let rms = sqrt(meanSquare)
        guard rms > 0 else { return floorDB }
        return max(floorDB, 20 * log10(rms))
    }

    // MARK: - CoreAudio default-device tracking

    private func installDefaultDeviceListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Delivered on the main queue (below); rebuild to follow the new default.
            MainActor.assumeIsolated { self?.scheduleRebuild(after: 0.3) }
        }
        defaultDeviceListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
    }

    private func removeDefaultDeviceListener() {
        guard let block = defaultDeviceListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        defaultDeviceListener = nil
    }

    /// Name of the current default input device, via CoreAudio.
    nonisolated static func defaultInputDeviceName() -> String? {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = withUnsafeMutablePointer(to: &deviceID) {
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, $0)
        }
        guard status == noErr, deviceID != 0 else { return nil }

        var name: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let nameStatus = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, $0)
        }
        guard nameStatus == noErr else { return nil }
        return name as String?
    }
}
