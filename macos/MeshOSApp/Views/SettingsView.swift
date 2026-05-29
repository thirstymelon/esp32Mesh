//
//  SettingsView.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var meshManager: MeshManager
    @AppStorage("autoConnect") private var autoConnect = false
    @AppStorage("savedNodeIP") private var savedNodeIP = ""
    @AppStorage("pollInterval") private var pollInterval = 2.0
    @AppStorage("showNotifications") private var showNotifications = true
    
    var body: some View {
        TabView {
            // General settings
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mesh OS")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        
                        Text("macOS Client v1.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                
                Section("Connection") {
                    Toggle("Auto-connect on launch", isOn: $autoConnect)
                    
                    if autoConnect {
                        HStack {
                            Text("Default node IP:")
                                .foregroundStyle(.secondary)
                            
                            TextField("192.168.1.100", text: $savedNodeIP)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    HStack {
                        Text("Poll interval:")
                            .foregroundStyle(.secondary)
                        
                        Slider(value: $pollInterval, in: 1...10, step: 0.5)
                        
                        Text(String(format: "%.1fs", pollInterval))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                
                Section("Notifications") {
                    Toggle("Show notifications for new messages", isOn: $showNotifications)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("1.0.0")
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Build")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("2024.05")
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 400)
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            // Advanced settings
            Form {
                Section("Network") {
                    Toggle("Enable IPv6", isOn: .constant(false))
                        .disabled(true)
                    
                    Toggle("Use mDNS discovery", isOn: .constant(false))
                        .disabled(true)
                }
                
                Section("Debug") {
                    Button("Clear message cache") {
                        // Future implementation
                    }
                    
                    Button("Export logs") {
                        // Future implementation
                    }
                }
            }
            .formStyle(.grouped)
            .frame(width: 500, height: 400)
            .tabItem {
                Label("Advanced", systemImage: "wrench.and.screwdriver")
            }
        }
    }
}
