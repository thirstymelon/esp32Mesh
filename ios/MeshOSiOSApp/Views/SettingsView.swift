import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var showingConnectionSheet: Bool
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("showNotifications") private var showNotifications = true

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
                    // Nickname card
//                    VStack(alignment: .leading, spacing: 12) {
//                        Text("NICKNAME")
//                            .font(.system(size: 11, weight: .bold))
//                            .foregroundStyle(AppPalette.dimText)
//                            .tracking(1)
//                            .padding(.horizontal, 4)
//                        
//                        VStack(alignment: .leading, spacing: 4) {
//                            Text("Current Nickname")
//                                .font(.system(size: 12))
//                                .foregroundStyle(AppPalette.dimText)
//                            Text(meshManager.currentNodeNickname)
//                                .font(.system(size: 16, weight: .bold, design: .rounded))
//                                .foregroundStyle(.white)
//                        }
//                    }
//                    .padding()
//                    .meshGlass(cornerRadius: 16)

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
                        
                        Divider()
                            .overlay(.white.opacity(0.08))
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PERMISSION STATUS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(1)
                            
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
    }
}
