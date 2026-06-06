import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var isPresented: Bool
    @State private var isConnecting = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Select a nearby ESP32 Mesh Node over BLE.")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.dimText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Discovered Nodes")
                                .font(.headline)
                                .foregroundStyle(AppPalette.dimText)
                            Spacer()
                            if meshManager.isScanning {
                                ProgressView()
                            }
                        }
                        .padding(.horizontal)
                        
                        if meshManager.bluetoothState != .poweredOn {
                            VStack(spacing: 16) {
                                Image(systemName: "wifi.slash")
                                    .font(.system(size: 40))
                                    .foregroundStyle(AppPalette.dimText)
                                
                                Text("Bluetooth not turned ON")
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.dimText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            }
                            .padding(.horizontal)
                        } else if meshManager.discoveredNodes.isEmpty && meshManager.scanDidTimeout {
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundStyle(AppPalette.dimText)
                                
                                Text("No MeshOS nodes found nearby.")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                
                                Button {
                                    meshManager.startScanning()
                                } label: {
                                    Label("Scan Again", systemImage: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isConnecting)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            }
                            .padding(.horizontal)
                        } else if meshManager.discoveredNodes.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 40))
                                    .foregroundStyle(AppPalette.dimText)
                                    .symbolEffect(.variableColor.iterative, options: .repeating)
                                
                                Text("Searching for MeshOS nodes...")
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.dimText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            }
                            .padding(.horizontal)
                        } else {
                            ScrollView {
                                VStack(spacing: 10) {
                                    ForEach(meshManager.discoveredNodes) { node in
                                        Button {
                                            connect(to: node)
                                        } label: {
                                            HStack(spacing: 14) {
                                                Circle()
                                                    .fill(NodeColor.color(for: node.name))
                                                    .frame(width: 38, height: 38)
                                                    .overlay {
                                                        Image(systemName: "cpu")
                                                            .font(.system(size: 14, weight: .bold))
                                                            .foregroundStyle(.black)
                                                    }
                                                
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(node.name)
                                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                                        .foregroundStyle(.white)
                                                    
                                                    Text(node.id.uuidString.prefix(12) + "...")
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundStyle(AppPalette.dimText)
                                                }
                                                
                                                Spacer()
                                                
                                                HStack(spacing: 4) {
                                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(AppPalette.dimText)
                                                    Text("\(node.rssi) dBm")
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundStyle(AppPalette.dimText)
                                                }
                                            }
                                            .padding(.all, 12)
                                            .meshGlass(cornerRadius: 16)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    if let error = meshManager.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.footnote)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
                        }
                        .padding(.horizontal)
                    }
                    
                    Button(action: {
                        meshManager.startScanning()
                    }) {
                        Label("Rescan", systemImage: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppPalette.cyan, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding()
                    .disabled(isConnecting)
                }
            }
            .navigationTitle("Connect to Mesh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                meshManager.errorMessage = nil
                meshManager.startScanning()
            }
            .onDisappear {
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
                }
            }
        }
        .interactiveDismissDisabled(isConnecting)
    }

    private func connect(to node: DiscoveredNode) {
        isConnecting = true
        meshManager.connect(to: node)
    }
}

#Preview {
    ConnectionSheet(isPresented: .constant(true))
        .environmentObject(MeshManager())
        .preferredColorScheme(.dark)
}
