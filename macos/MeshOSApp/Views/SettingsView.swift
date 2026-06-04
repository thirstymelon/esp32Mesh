//
//  SettingsView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var meshManager: MeshManager
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("showNotifications") private var showNotifications = true

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
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("App configuration, encryption controls, and debug logs")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.dimText)
            }
            .padding(.top, 12)
            .padding(.bottom, 16)

            ScrollView {
                HStack(alignment: .top, spacing: 20) {
                    // Left Column
                    VStack(spacing: 20) {
                        // Preferences card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("APP PREFERENCES")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(0.8)
                            
                            Toggle("Auto-connect to last node on launch", isOn: $autoConnect)
                                .font(.system(size: 13, weight: .medium))
                                .help("Automatically reconnect to the most recently paired Mesh node when the app starts.")
                            
                            Toggle("Show system notifications for new messages", isOn: $showNotifications)
                                .font(.system(size: 13, weight: .medium))
                                .help("Post a macOS notification when a new message arrives while the app is not focused.")
                            
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
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .meshGlass(cornerRadius: 16)

                        // Protocol Settings card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("PROTOCOL DETAILS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(0.8)
                            
                            HStack {
                                Text("Transport")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("BLE GATT + ESP-NOW")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                            
                            Divider()
                                .overlay(.white.opacity(0.08))
                            
                            HStack {
                                Text("Encryption")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("AES-128-GCM")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                            
                            Divider()
                                .overlay(.white.opacity(0.08))
                            
                            HStack {
                                Text("ATT MTU Size")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("512 bytes")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                            
                            Divider()
                                .overlay(.white.opacity(0.08))
                            
                            HStack {
                                Text("Max Plaintext Payload")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Text("172 bytes")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(AppPalette.dimText)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .meshGlass(cornerRadius: 16)
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column
                    VStack(spacing: 20) {
                        // Security Section card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("SECURITY CONTROLS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(0.8)
                            
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(AppPalette.ok)
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
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .meshGlass(cornerRadius: 16)

                        // Debug Section card
                        VStack(alignment: .leading, spacing: 14) {
                            Text("DIAGNOSTICS & SYSTEM INFO")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppPalette.dimText)
                                .tracking(0.8)
                            
                            HStack {
                                Button("Clear Message Cache") {
                                    // wired to clean actions
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Export Logs") {
                                    // future export utility
                                }
                                .buttonStyle(.bordered)
                            }
                            
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
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .meshGlass(cornerRadius: 16)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            meshManager.checkNotificationPermission()
        }
    }
}
