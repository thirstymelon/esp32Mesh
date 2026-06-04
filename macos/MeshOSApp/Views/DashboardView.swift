//
//  DashboardView.swift
//  Mesh OS - macOS Client
//

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var meshManager: MeshManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mesh Telemetry")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Real-time network telemetry and performance logs")
                        .font(.subheadline)
                        .foregroundStyle(AppPalette.dimText)
                }
                .padding(.top, 12)
                .padding(.bottom, 6)
                
                if meshManager.isConnected {
                    // Charts Grid
                    let columns = [
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20)
                    ]
                    
                    LazyVGrid(columns: columns, spacing: 20) {
                        // Chart 1: Node count and direct peer count over time
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Mesh Node Population")
                                .font(.headline.weight(.semibold))
                            
                            if meshManager.networkHistory.isEmpty {
                                Text("Waiting for population data...")
                                    .font(.caption)
                                    .foregroundStyle(AppPalette.dimText)
                                    .frame(maxHeight: .infinity)
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
                                .frame(height: 200)
                            }
                        }
                        .padding()
                        .meshGlass(cornerRadius: 16)
                        
                        // Chart 2: Battery statuses
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Peer Battery Levels")
                                .font(.headline.weight(.semibold))
                            
                            if meshManager.telemetryHistory.isEmpty {
                                Text("Waiting for battery telemetry...")
                                    .font(.caption)
                                    .foregroundStyle(AppPalette.dimText)
                                    .frame(maxHeight: .infinity)
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
                                .frame(height: 200)
                            }
                        }
                        .padding()
                        .meshGlass(cornerRadius: 16)
                        
                        // Chart 3: Peer link quality / telemetry logs list
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent Telemetry Events")
                                .font(.headline.weight(.semibold))
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    if meshManager.telemetryHistory.isEmpty {
                                        Text("No telemetry events logged yet.")
                                            .font(.caption)
                                            .foregroundStyle(AppPalette.dimText)
                                            .padding(.top, 10)
                                    } else {
                                        ForEach(meshManager.telemetryHistory.reversed().prefix(6)) { point in
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
                                            .padding(6)
                                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                            .frame(height: 200)
                        }
                        .padding()
                        .meshGlass(cornerRadius: 16)
                        
                        // Chart 4: Group Key security status
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Security Status")
                                .font(.headline.weight(.semibold))
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Epoch Status:")
                                        .foregroundStyle(AppPalette.dimText)
                                    Spacer()
                                    Text("Epoch \(meshManager.groupKeyEpoch)")
                                        .fontWeight(.bold)
                                        .foregroundStyle(AppPalette.cyan)
                                }
                                
                                HStack {
                                    Text("Active Encryption:")
                                        .foregroundStyle(AppPalette.dimText)
                                    Spacer()
                                    Text("AES-128-GCM")
                                        .fontWeight(.semibold)
                                }
                                
                                Text("The broadcast/group key rotates when requested or upon peer epoch increment, preventing sniffing on broad-mesh transmissions.")
                                    .font(.caption2)
                                    .foregroundStyle(AppPalette.dimText)
                                    .lineLimit(nil)
                                    .padding(.top, 4)
                                
                                Spacer()
                                
                                Button(action: {
                                    meshManager.rotateGroupKey()
                                }) {
                                    Label("Rotate Group Key", systemImage: "key.fill")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(AppPalette.violet)
                            }
                            .frame(height: 200, alignment: .top)
                        }
                        .padding()
                        .meshGlass(cornerRadius: 16)
                    }
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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 80)
                    .meshGlass(cornerRadius: 16)
                }
            }
        }
    }
}
