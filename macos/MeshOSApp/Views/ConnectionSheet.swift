//
//  ConnectionSheet.swift
//  Mesh OS - macOS Client
//

import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject var meshManager: MeshManager
    @Binding var isPresented: Bool
    @State private var ipAddress: String = "10.224.13.1"
    @State private var isConnecting = false
    @State private var showError = false

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .meshGlass(cornerRadius: 13)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to Mesh")
                        .font(.title2.weight(.semibold))
                    Text("Enter the address of any reachable node.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Node IP Address")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField("10.224.13.1", text: $ipAddress)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .meshGlass(cornerRadius: 14, interactive: true)
                    .onSubmit(connect)
            }

            if showError, let error = meshManager.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .meshGlass(cornerRadius: 14)
            }

            Button(action: connect) {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isConnecting ? "Connecting" : "Connect")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)

            VStack(alignment: .leading, spacing: 8) {
                Text("Common addresses")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    QuickConnectButton(ip: "10.224.13.1") { ipAddress = $0 }
                    QuickConnectButton(ip: "192.168.4.1") { ipAddress = $0 }
                    QuickConnectButton(ip: "10.0.0.1") { ipAddress = $0 }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 460, height: 360)
        .background(AppBackground())
    }

    private func connect() {
        let address = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }

        isConnecting = true
        showError = false

        Task {
            await meshManager.connect(to: address)

            await MainActor.run {
                isConnecting = false
                if meshManager.isConnected {
                    isPresented = false
                } else {
                    showError = true
                }
            }
        }
    }
}

// MARK: - Quick Connect Button
struct QuickConnectButton: View {
    let ip: String
    let action: (String) -> Void

    var body: some View {
        Button {
            action(ip)
        } label: {
            Text(ip)
                .font(.system(.caption, design: .monospaced))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
