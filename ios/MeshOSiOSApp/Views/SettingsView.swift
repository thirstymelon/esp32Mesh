import SwiftUI
import Charts
import UniformTypeIdentifiers
import Combine

struct SettingsView: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var showingConnectionSheet: Bool
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("messageHaptics") private var messageHaptics = true
    
    // Bindings mapped directly to root meshManager state to persist across tab views
    @State private var showingFileImporter = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Connection card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CONNECTION")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        Toggle(isOn: $autoConnect) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-connect on launch")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Automatically scans and connects to the last used BLE node.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                        }
                        .tint(AppPalette.appleGreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .meshGlass(cornerRadius: 16)

                    // Notifications card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NOTIFICATIONS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        Toggle(isOn: $showNotifications) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Show notifications")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Receive alerts for new incoming mesh messages.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                        }
                        .tint(AppPalette.appleGreen)
                        
                        Toggle(isOn: $messageHaptics) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Message haptics")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("Vibrate on send and receive for new mesh messages.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                        }
                        .tint(AppPalette.appleGreen)
                        
                        Divider()
                            .overlay(.white.opacity(0.08))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PERMISSION STATUS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(1)
                                .padding(.horizontal, 4)
                            
                            HStack {
                                switch meshManager.notificationStatus {
                                case .authorized, .provisional, .ephemeral:
                                    Label("Authorized", systemImage: "checkmark.seal.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppPalette.ok)
                                case .denied:
                                    HStack {
                                        Label("Denied (Disabled)", systemImage: "exclamationmark.octagon.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppPalette.error)
                                        
                                        Spacer()
                                        
                                        Button("Open Settings") {
                                            meshManager.openNotificationSettings()
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(AppPalette.cyan)
                                    }
                                case .notDetermined:
                                    HStack {
                                        Label("Not Requested", systemImage: "questionmark.circle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppPalette.dimText)
                                        
                                        Spacer()
                                        
                                        Button("Request Access") {
                                            meshManager.requestNotificationPermission()
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(AppPalette.cyan)
                                    }
                                @unknown default:
                                    Text("Unknown Status")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppPalette.dimText)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .meshGlass(cornerRadius: 16)

                    // Security card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SECURITY")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(AppPalette.ok)
                                .font(.system(size: 24))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("AES-128-GCM + P-256 ECDH")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                
                                Text("Encryption key derived dynamically per BLE session. Broadcasts secured via rotated group keys.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppPalette.dimText)
                                    .lineLimit(nil)
                                
                                HStack(spacing: 4) {
                                    Text("Group Key Epoch:")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(AppPalette.dimText)
                                    Text("\(meshManager.groupKeyEpoch)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(AppPalette.appleGreen)
                                }
                                .padding(.top, 4)
                            }
                        }

                        if meshManager.isConnected {
                            Button(action: {
                                meshManager.rotateGroupKey()
                                Haptics.impact(.medium)
                            }) {
                                Label("Rotate Group Key", systemImage: "key.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(AppPalette.appleGreen, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .meshGlass(cornerRadius: 16)

                    // OTA card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FIRMWARE UPDATE (OTA)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        if meshManager.isConnected {
                            Text("Flash a precompiled firmware binary directly to the connected node over BLE.")
                                .font(.system(size: 13))
                                .foregroundStyle(AppPalette.dimText)
                                .lineLimit(nil)
                            
                            HStack {
                                Button(action: {
                                    showingFileImporter = true
                                    Haptics.impact(.light)
                                }) {
                                    HStack {
                                        Image(systemName: "doc.badge.plus")
                                    Text(meshManager.selectedBinURL == nil ? "Select Firmware Binary..." : "Change Binary...")
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(meshManager.isUpdatingOTA)
                                
                                Spacer()
                                
                                if let selectedBinURL = meshManager.selectedBinURL, let selectedBinData = meshManager.selectedBinData {
                                    VStack(alignment: .trailing, spacing: 2) {
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
                                } else {
                                    Button(action: {
                                        guard let data = meshManager.selectedBinData else { return }
                                        Haptics.impact(.medium)
                                        meshManager.startFirmwareOTA(data: data)
                                    }) {
                                        HStack {
                                            Image(systemName: "arrow.up.circle.fill")
                                            Text("Start OTA Flash")
                                        }
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(AppPalette.appleGreen, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            Text("Connect to a node to enable OTA firmware updates.")
                                .font(.system(size: 13))
                                .foregroundStyle(AppPalette.dimText)
                                .italic()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .meshGlass(cornerRadius: 16)

                    // About card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ABOUT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppPalette.dimText)
                            .tracking(1)
                            .padding(.horizontal, 4)
                        
                        HStack {
                            Text("Version")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Text(appVersion)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(AppPalette.dimText)
                        }
                        
                        Divider()
                            .overlay(.white.opacity(0.08))
                        
                        HStack {
                            Text("Build")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Text(appBuild)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(AppPalette.dimText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .meshGlass(cornerRadius: 16)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ConnectionBadgeButton(showingConnectionSheet: $showingConnectionSheet)
                    .environmentObject(meshManager)
            }
        }
        .onAppear {
            meshManager.checkNotificationPermission()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    meshManager.errorMessage = "Failed to access file security context."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
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
            case .failure(let error):
                meshManager.errorMessage = "File import failed: \(error.localizedDescription)"
            }
        }
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
            HStack(spacing: 10) {
                if !isComplete && !isError {
                    ProgressView()
                        .scaleEffect(0.65)
                        .tint(progressColor)
                } else if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppPalette.appleGreen)
                        .symbolEffect(.bounce, options: .speed(0.5))
                } else if isError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppPalette.error)
                }
                
                Text(statusMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isError ? AppPalette.error : .white)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(progressColor)
                    .contentTransition(.numericText(value: Double(progress)))
            }
            
            // Animated gradient progress bar with glow
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 12)
                    
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
                                    .frame(width: 24, height: 24)
                                
                                if isPassed {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if isActive {
                                    Image(systemName: phase.icon)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white)
                                } else {
                                    Image(systemName: phase.icon)
                                        .font(.system(size: 11))
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
                                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
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

#Preview {
    NavigationStack {
        SettingsView(showingConnectionSheet: .constant(false))
            .environmentObject(MeshManager())
    }
    .preferredColorScheme(.dark)
}
