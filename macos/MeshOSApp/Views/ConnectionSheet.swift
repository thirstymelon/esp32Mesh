//
//  ConnectionSheet.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var isPresented: Bool
    @State private var isConnecting = false
    @State private var showError = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.cyan)
                    .frame(width: 36, height: 36)
                    .meshGlass(cornerRadius: 13)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to Mesh")
                        .font(.title2.weight(.semibold))
                    Text("Select a nearby ESP32 Mesh Node over BLE.")
                        .font(.caption)
                        .foregroundStyle(AppPalette.dimText)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Discovered Nodes")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AppPalette.dimText)
                    Spacer()
                    if meshManager.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if meshManager.discoveredNodes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 28))
                            .foregroundStyle(AppPalette.dimText)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                        
                        Text("Searching for MeshOS nodes...")
                            .font(.system(size: 13))
                            .foregroundStyle(AppPalette.dimText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .meshGlass(cornerRadius: 16)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(meshManager.discoveredNodes) { node in
                                DiscoveredNodeRow(node: node) {
                                    connect(to: node)
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    .padding(6)
                    .meshGlass(cornerRadius: 16)
                }
            }

            if let error = meshManager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .meshGlass(cornerRadius: 14)
            }

            HStack {
                Button(action: {
                    meshManager.startScanning()
                }) {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isConnecting)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(22)
        .frame(width: 480, height: 400)
        .background(AppBackground())
        .onAppear {
            meshManager.errorMessage = nil
            meshManager.startScanning()
        }
        .onDisappear {
            // Always stop scanning when the sheet goes away to conserve Bluetooth resources
            meshManager.stopScanning()
        }
        .onChange(of: meshManager.isConnected) { _, connected in
            if connected {
                isConnecting = false
                isPresented = false
            }
        }
        .onChange(of: meshManager.errorMessage) { _, error in
            if error != nil && isConnecting {
                isConnecting = false
                showError = true
            }
        }
    }

    private func connect(to node: DiscoveredNode) {
        isConnecting = true
        showError = false
        meshManager.connect(to: node)
        // Connection result is handled by onChange(of: meshManager.isConnected)
        // and onChange(of: meshManager.errorMessage) above — no polling needed.
    }
}

struct DiscoveredNodeRow: View {
    let node: DiscoveredNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(NodeColor.color(for: node.name))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: "cpu")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    Text(node.id.uuidString.prefix(12) + "...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppPalette.dimText)
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.dimText)
                    Text("\(node.rssi) dBm")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppPalette.dimText)
                }
            }
            .padding(10)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
