//
//  SettingsView.swift
//  Mesh OS - macOS Client
//

import SwiftUI
import Charts
import UniformTypeIdentifiers
import Combine

struct SettingsView: View {
    @EnvironmentObject var meshManager: MeshManager
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("showNotifications") private var showNotifications = true
    
    // Bindings mapped directly to root meshManager state to persist across tab views

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("App configuration, encryption controls, and debug logs")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.dimText)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
            
            ScrollView {
                Grid(horizontalSpacing: 20, verticalSpacing: 20) {
                    GridRow {
                        preferencesCard
                        securityCard
                    }
                    GridRow {
                        protocolCard
                        diagnosticsCard
                    }
                    GridRow {
                        otaCard
                            .gridCellColumns(2)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            meshManager.checkNotificationPermission()
        }
    }

    // MARK: - Bento Cards

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.cyan)
                
                Text("APP PREFERENCES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppPalette.dimText)
                    .tracking(0.8)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-connect to last node on launch", isOn: $autoConnect)
                    .font(.system(size: 13, weight: .medium))
                    .help("Automatically reconnect to the most recently paired Mesh node when the app starts.")
                
                Toggle("Show system notifications for new messages", isOn: $showNotifications)
                    .font(.system(size: 13, weight: .medium))
                    .help("Post a macOS notification when a new message arrives while the app is not focused.")
            }
            
            Divider()
                .overlay(.white.opacity(0.08))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("SYSTEM NOTIFICATIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppPalette.dimText)
                
                HStack {
                    switch meshManager.notificationStatus {
                    case .authorized, .provisional, .ephemeral:
                        Label("Authorized", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppPalette.ok)
                    case .denied:
                        HStack(spacing: 12) {
                            Label("Denied (Disabled)", systemImage: "exclamationmark.octagon.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppPalette.error)
                            
                            Spacer()
                            
                            Button("Open Settings") {
                                meshManager.openNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                        }
                    case .notDetermined:
                        HStack(spacing: 12) {
                            Label("Not Requested", systemImage: "questionmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppPalette.dimText)
                            
                            Spacer()
                            
                            Button("Request Access") {
                                meshManager.requestNotificationPermission()
                            }
                            .buttonStyle(.bordered)
                        }
                    @unknown default:
                        Text("Unknown Status")
                            .font(.system(size: 13))
                            .foregroundStyle(AppPalette.dimText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .bentoStyle(
            gradient: LinearGradient(
                colors: [Color(red: 0.00, green: 0.48, blue: 1.00), Color(red: 0.35, green: 0.34, blue: 0.84)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.appleGreen)
                
                Text("SECURITY CONTROLS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppPalette.dimText)
                    .tracking(0.8)
            }
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "key.shield.fill")
                    .foregroundStyle(AppPalette.amber)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AES-128-GCM & ECDH P-256")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Text("Session key derived dynamically. Group keys rotated regularly to protect broad-mesh broadcasts.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.dimText)
                        .lineLimit(nil)
                }
            }
            
            if meshManager.isConnected {
                Divider()
                    .overlay(.white.opacity(0.08))
                
                HStack {
                    Text("Group Key Epoch:")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text("Epoch \(meshManager.groupKeyEpoch)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppPalette.cyan)
                }
                
                Button(action: {
                    meshManager.rotateGroupKey()
                }) {
                    Label("Rotate Group Key", systemImage: "key.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppPalette.appleGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                Spacer()
                Text("Connect to a node to enable session rotation controls.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.dimText)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .bentoStyle(
            gradient: LinearGradient(
                colors: [Color(red: 0.20, green: 0.78, blue: 0.35), Color(red: 0.00, green: 0.64, blue: 0.80)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.violet)
                
                Text("PROTOCOL DETAILS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppPalette.dimText)
                    .tracking(0.8)
            }
            
            VStack(spacing: 10) {
                ProtocolDetailRow(label: "Transport", value: "BLE GATT + ESP-NOW")
                Divider().overlay(.white.opacity(0.08))
                ProtocolDetailRow(label: "Encryption", value: "AES-128-GCM")
                Divider().overlay(.white.opacity(0.08))
                ProtocolDetailRow(label: "ATT MTU Size", value: "512 bytes")
                Divider().overlay(.white.opacity(0.08))
                ProtocolDetailRow(label: "Max Plaintext Payload", value: "172 bytes")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .bentoStyle(
            gradient: LinearGradient(
                colors: [Color(red: 0.00, green: 0.64, blue: 0.80), Color(red: 0.10, green: 0.70, blue: 0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.amber)
                
                Text("DIAGNOSTICS & SYSTEM INFO")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppPalette.dimText)
                    .tracking(0.8)
            }
            
            HStack(spacing: 12) {
                Button("Clear Cache") {
                    meshManager.clearCache()
                }
                .buttonStyle(.bordered)
                
                Button("Export Logs") {
                    // future export utility
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            Divider()
                .overlay(.white.opacity(0.08))
            
            HStack {
                Text("Client Version")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(appVersion) (Build \(appBuild))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppPalette.dimText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .bentoStyle(
            gradient: LinearGradient(
                colors: [Color(red: 0.86, green: 0.19, blue: 0.51), Color(red: 1.00, green: 0.62, blue: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    // MARK: - OTA Firmware Updates
    
    private func selectFile() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType.data]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if url.pathExtension.lowercased() == "bin" {
                    do {
                        let data = try Data(contentsOf: url)
                        meshManager.selectedBinURL = url
                        meshManager.selectedBinData = data
                    } catch {
                        meshManager.errorMessage = "Failed to read binary file: \(error.localizedDescription)"
                    }
                } else {
                    meshManager.errorMessage = "Invalid file type. Please select a .bin firmware file."
                }
            }
        }
    }
    
    private var otaCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line.alt")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppPalette.magenta)
                
                Text("FIRMWARE UPDATE (OTA)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppPalette.dimText)
                    .tracking(0.8)
            }
            
            if meshManager.isConnected {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Flash a precompiled firmware binary directly to the connected node over BLE. Make sure the node is in range and has stable power.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.dimText)
                        .lineLimit(nil)
                    
                    HStack(spacing: 12) {
                        Button(action: selectFile) {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text(meshManager.selectedBinURL == nil ? "Select Firmware Binary..." : "Change Binary...")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(meshManager.isUpdatingOTA)
                        
                        if let selectedBinURL = meshManager.selectedBinURL, let selectedBinData = meshManager.selectedBinData {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedBinURL.lastPathComponent)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(selectedBinData.count) bytes")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                        }
                    }
                    
                    if meshManager.selectedBinData != nil {
                        Divider()
                            .overlay(.white.opacity(0.08))
                        
                        if meshManager.isUpdatingOTA {
                            OTAProgressView(
                                progress: meshManager.otaProgress,
                                statusMessage: meshManager.otaStatusMessage,
                                speedHistory: meshManager.otaSpeedHistory
                            )
                            .padding(.top, 4)
                        } else {
                            Button(action: {
                                guard let data = meshManager.selectedBinData else { return }
                                meshManager.startFirmwareOTA(data: data)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                    Text("Start OTA Flash")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(AppPalette.appleGreen, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                }
            } else {
                Spacer()
                Text("Connect to a node via the connection panel to enable OTA firmware updates.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.dimText)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bentoStyle(
            gradient: LinearGradient(
                colors: [Color(red: 0.55, green: 0.17, blue: 0.89), Color(red: 0.89, green: 0.17, blue: 0.44)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - OTA Progress View

private struct OTAProgressView: View {
    let progress: Float
    let statusMessage: String
    let speedHistory: [MeshManager.OTASpeedDataPoint]
    
    @State private var lastProgress: Float = 0
    @State private var lastUpdateTime: Date = .now
    @State private var speedPercentPerSec: Double = 0
    @State private var isGlowing = false
    @State private var stripePhase: CGFloat = 0
    private let stripeTimer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()
    
    private let phases: [(label: String, icon: String)] = [
        ("Prepare", "antenna.radiowaves.left.and.right"),
        ("Upload", "arrow.up.doc"),
        ("Flash", "memorychip"),
        ("Verify", "checkmark.shield"),
        ("Done", "sparkles")
    ]
    
    private var currentPhase: Int {
        if statusMessage.contains("Preparing") { return 0 }
        if statusMessage.contains("Uploading") { return 1 }
        if statusMessage.contains("Verifying") || statusMessage.contains("Flashed") { return 3 }
        if statusMessage.contains("Succeeded") || statusMessage.contains("Rebooting") { return 4 }
        if statusMessage.contains("Error") { return -1 }
        // "Writing" is the firmware's status update during flash
        return 2
    }
    
    private var isError: Bool { statusMessage.contains("Error") }
    private var isComplete: Bool { statusMessage.contains("Succeeded") || statusMessage.contains("Rebooting") }
    
    private var progressColor: Color {
        if isError { return AppPalette.error }
        if isComplete { return AppPalette.appleGreen }
        return progress < 0.3 ? AppPalette.cyan : (progress < 0.7 ? AppPalette.violet : AppPalette.appleGreen)
    }
    
    private var gradientColors: [Color] {
        if isError { return [AppPalette.error, AppPalette.amber] }
        if isComplete { return [AppPalette.appleGreen, AppPalette.cyan] }
        return [AppPalette.cyan, AppPalette.violet, AppPalette.magenta, AppPalette.appleGreen]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Status header with live percentage
            HStack(spacing: 12) {
                // Pulsing activity indicator
                if !isComplete && !isError {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(progressColor)
                } else if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppPalette.appleGreen)
                        .symbolEffect(.bounce, options: .speed(0.5))
                } else if isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppPalette.error)
                }
                
                Text(statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isError ? AppPalette.error : .white)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(progressColor)
                    .contentTransition(.numericText(value: Double(progress)))
            }
            
            // Animated gradient progress bar with glow
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 12)
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(progress)), height: 12)
                        .overlay(
                            Group {
                                if !isComplete && !isError {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0),
                                                    .white.opacity(0.2),
                                                    .white.opacity(0)
                                                ],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: geo.size.width * 0.4)
                                        .offset(x: (stripePhase * geo.size.width * 1.4) - (geo.size.width * 0.4))
                                }
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .shadow(color: progressColor.opacity(isGlowing ? 0.5 : 0.15), radius: isGlowing ? 8 : 3, y: 0)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: 12)
            
            // Speed / ETA row
            if !isComplete && !isError && progress > 0.01 && progress < 0.99 {
                HStack(spacing: 16) {
                    if speedPercentPerSec > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.dimText)
                            Text("\(Int(speedPercentPerSec * 100))%/s")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppPalette.dimText)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundStyle(AppPalette.dimText)
                            Text(etaString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppPalette.dimText)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top, -4)
            }
            
            // Speed graph
            if !isComplete && !isError, speedHistory.count >= 2 {
                speedChart
            }
            
            // Phase stage indicators
            if !isComplete {
                HStack(spacing: 0) {
                    ForEach(phases.indices, id: \.self) { idx in
                        let phase = phases[idx]
                        let isActive = idx == currentPhase
                        let isPassed = idx < currentPhase
                        
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(
                                        isPassed ? AppPalette.appleGreen :
                                        isActive ? progressColor :
                                        Color.white.opacity(0.08)
                                    )
                                    .frame(width: 22, height: 22)
                                
                                if isPassed {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if isActive {
                                    Image(systemName: phase.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white)
                                } else {
                                    Image(systemName: phase.icon)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.white.opacity(0.35))
                                }
                            }
                            .overlay(
                                isActive ?
                                Circle()
                                    .stroke(progressColor.opacity(isGlowing ? 0.7 : 0.3), lineWidth: 2)
                                    .scaleEffect(isGlowing ? 1.25 : 1.0)
                                : nil
                            )
                            
                            Text(phase.label)
                                .font(.system(size: 9, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isPassed ? AppPalette.appleGreen : (isActive ? .white : AppPalette.dimText))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 2)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
        .onReceive(stripeTimer) { _ in
            stripePhase = (stripePhase + 0.008).truncatingRemainder(dividingBy: 1.4)
        }
        .onChange(of: progress) { _, newProgress in
            let now = Date()
            let delta = Double(newProgress - lastProgress)
            let timeDelta = now.timeIntervalSince(lastUpdateTime)
            if timeDelta > 0.1 && delta > 0 {
                speedPercentPerSec = delta / timeDelta
            }
            lastProgress = newProgress
            lastUpdateTime = now
        }
    }
    
    private var etaString: String {
        let remaining = 1.0 - Double(progress)
        guard speedPercentPerSec > 0 else { return "--" }
        let seconds = remaining / speedPercentPerSec
        if seconds < 5 { return "<5s" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let mins = Int(seconds / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
        return "\(mins)m \(secs)s"
    }
    
    @ViewBuilder
    private var speedChart: some View {
        let start = speedHistory.first!.timestamp
        VStack(alignment: .leading, spacing: 6) {
            Text("UPLOAD SPEED")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppPalette.dimText)
                .tracking(0.8)
            
            Chart(speedHistory) { point in
                LineMark(
                    x: .value("Time", point.timestamp.timeIntervalSince(start)),
                    y: .value("Speed", point.speedBytesPerSec / 1024.0)
                )
                .foregroundStyle(AppPalette.cyan.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2))
                
                AreaMark(
                    x: .value("Time", point.timestamp.timeIntervalSince(start)),
                    y: .value("Speed", point.speedBytesPerSec / 1024.0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppPalette.cyan.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    if let seconds = value.as(Double.self) {
                        AxisValueLabel(String(format: "%.0f", seconds))
                            .font(.system(size: 8))
                            .foregroundStyle(AppPalette.dimText)
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.05))
                }
            }
            .chartXAxisLabel(position: .bottom, alignment: .center, spacing: 2) {
                Text("sec")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.dimText)
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    if let speed = value.as(Double.self) {
                        AxisValueLabel(String(format: "%.1f", speed))
                            .font(.system(size: 8))
                            .foregroundStyle(AppPalette.dimText)
                    }
                    AxisGridLine().foregroundStyle(.white.opacity(0.05))
                }
            }
            .chartYAxisLabel(position: .trailing, alignment: .center, spacing: 4) {
                Text("KB/s")
                    .font(.system(size: 8))
                    .foregroundStyle(AppPalette.dimText)
            }
            .frame(height: 80)
        }
    }
}

struct ProtocolDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppPalette.dimText)
        }
    }
}

extension View {
    fileprivate func bentoStyle(cornerRadius: CGFloat = 20, gradient: LinearGradient) -> some View {
        self
            .padding(20)
            .background(
                ZStack {
                    gradient
                        .opacity(0.08)
                    Color(red: 0.10, green: 0.11, blue: 0.14)
                        .opacity(0.75)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

#Preview {
    SettingsView()
        .environmentObject(MeshManager())
        .frame(width: 920, height: 640)
        .preferredColorScheme(.dark)
}
