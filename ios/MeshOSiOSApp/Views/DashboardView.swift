//
//  DashboardView.swift
//  Mesh OS - iOS Client
//

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var showingConnectionSheet: Bool
    
    var body: some View {
        ZStack {
            AppBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    Spacer()
                        .frame(height: 10)
                    
                    if meshManager.isConnected {
                        VStack(spacing: 16) {
                            // Chart 1: Node count and direct peer count over time
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Mesh Node Population")
                                    .font(.subheadline.weight(.semibold))
                                
                                if meshManager.networkHistory.isEmpty {
                                    Text("Waiting for population data...")
                                        .font(.caption)
                                        .foregroundStyle(AppPalette.dimText)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 40)
                                } else {
                                    Chart {
                                        ForEach(meshManager.networkHistory) { point in
                                            LineMark(
                                                x: .value("Time", point.timestamp),
                                                y: .value("Nodes", point.activeNodeCount)
                                            )
                                            .foregroundStyle(AppPalette.cyan)
                                            .interpolationMethod(.catmullRom)
                                            
                                            AreaMark(
                                                x: .value("Time", point.timestamp),
                                                y: .value("Nodes", point.activeNodeCount)
                                            )
                                            .foregroundStyle(AppPalette.cyan.opacity(0.1))
                                            .interpolationMethod(.catmullRom)
                                        }
                                    }
                                    .frame(height: 180)
                                }
                            }
                            .padding()
                            .meshGlass(cornerRadius: 16)
                            
                            // Chart 2: Battery statuses
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Peer Battery Levels")
                                    .font(.subheadline.weight(.semibold))
                                
                                if meshManager.telemetryHistory.isEmpty {
                                    Text("Waiting for battery telemetry...")
                                        .font(.caption)
                                        .foregroundStyle(AppPalette.dimText)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 40)
                                } else {
                                    Chart {
                                        ForEach(meshManager.telemetryHistory) { point in
                                            PointMark(
                                                x: .value("Time", point.timestamp),
                                                y: .value("Battery %", point.battery)
                                            )
                                            .foregroundStyle(by: .value("Node ID", point.nodeId))
                                        }
                                    }
                                    .frame(height: 180)
                                }
                            }
                            .padding()
                            .meshGlass(cornerRadius: 16)
                            
                            // List: Recent Telemetry Events
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Recent Telemetry Events")
                                    .font(.subheadline.weight(.semibold))
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    if meshManager.telemetryHistory.isEmpty {
                                        Text("No telemetry events logged yet.")
                                            .font(.caption)
                                            .foregroundStyle(AppPalette.dimText)
                                            .padding(.vertical, 10)
                                    } else {
                                        ForEach(meshManager.telemetryHistory.reversed().prefix(5)) { point in
                                            HStack {
                                                Text(point.timestamp, style: .time)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(AppPalette.dimText)
                                                Text("Node \(point.nodeId)")
                                                    .font(.caption.weight(.semibold))
                                                Spacer()
                                                Label("\(point.battery)%", systemImage: "battery.100")
                                                    .font(.caption)
                                                    .foregroundStyle(point.battery < 20 ? AppPalette.error : AppPalette.ok)
                                            }
                                            .padding(8)
                                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            .padding()
                            .meshGlass(cornerRadius: 16)
                            
                            // Status Card: Group Key Security
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Security Status")
                                    .font(.subheadline.weight(.semibold))
                                
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Epoch Status:")
                                            .font(.footnote)
                                            .foregroundStyle(AppPalette.dimText)
                                        Spacer()
                                        Text("Epoch \(meshManager.groupKeyEpoch)")
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(AppPalette.cyan)
                                    }
                                    
                                    HStack {
                                        Text("Active Encryption:")
                                            .font(.footnote)
                                            .foregroundStyle(AppPalette.dimText)
                                        Spacer()
                                        Text("AES-128-GCM")
                                            .font(.footnote.weight(.semibold))
                                    }
                                    
                                    Text("The broadcast/group key rotates when requested or upon peer epoch increment, preventing sniffing on broad-mesh transmissions.")
                                        .font(.caption2)
                                        .foregroundStyle(AppPalette.dimText)
                                        .lineLimit(nil)
                                        .padding(.top, 4)
                                    
                                    Button(action: {
                                        meshManager.rotateGroupKey()
                                    }) {
                                        Label("Rotate Group Key", systemImage: "key.fill")
                                            .font(.footnote.weight(.semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(AppPalette.violet, in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 6)
                                }
                            }
                            .padding()
                            .meshGlass(cornerRadius: 16)
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 48))
                                .foregroundStyle(AppPalette.dimText)
                            Text("No Dashboard Data")
                                .font(.headline)
                            Text("Connect to a BLE node to view telemetry logs.")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.dimText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                        .meshGlass(cornerRadius: 16)
                        .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable {
                await meshManager.fetchData()
            }
        }
        .navigationTitle("Mesh Telemetry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ConnectionBadgeButton(showingConnectionSheet: $showingConnectionSheet)
                    .environmentObject(meshManager)
            }
        }
    }
}
