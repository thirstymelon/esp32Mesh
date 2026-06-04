//
//  MetalTopologyView.swift
//  Mesh OS - macOS Client
//

import SwiftUI
import MetalKit

struct MetalTopologyView: NSViewRepresentable {
    let nodeLayouts: [NodeLayoutInfo]
    let activeNodes: [NodeEntry]
    let messages: [MeshData.Message]
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0) // transparent background
        mtkView.delegate = context.coordinator
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.updateData(nodeLayouts: nodeLayouts, activeNodes: activeNodes, messages: messages)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate {
        private var device: MTLDevice?
        private var commandQueue: MTLCommandQueue?
        private var pointPipelineState: MTLRenderPipelineState?
        private var linePipelineState: MTLRenderPipelineState?
        private var packetPipelineState: MTLRenderPipelineState?
        
        // Persistent buffers
        private var nodePosBuffer: MTLBuffer?
        private var nodeColBuffer: MTLBuffer?
        private var linePosBuffer: MTLBuffer?
        private var lineColBuffer: MTLBuffer?
        private var packetPosBuffer: MTLBuffer?
        private var packetColBuffer: MTLBuffer?
        
        // Data to render
        private var nodeLayouts: [NodeLayoutInfo] = []
        private var activeNodes: [NodeEntry] = []
        private var messages: [MeshData.Message] = []
        private let dataLock = NSLock()
        
        // Animation states
        struct PacketAnimation {
            let id = UUID()
            let senderId: String
            let receiverId: String
            var progress: Float = 0.0
            let speed: Float = 0.02
        }
        private var activeAnimations: [PacketAnimation] = []
        private var lastMessageCount = 0
        
        override init() {
            super.init()
            self.device = MTLCreateSystemDefaultDevice()
            self.commandQueue = device?.makeCommandQueue()
            setupPipelines()
        }
        
        func updateData(nodeLayouts: [NodeLayoutInfo], activeNodes: [NodeEntry], messages: [MeshData.Message]) {
            dataLock.lock()
            defer { dataLock.unlock() }
            self.nodeLayouts = nodeLayouts
            self.activeNodes = activeNodes
            self.messages = messages
            
            if lastMessageCount == 0 {
                lastMessageCount = messages.count
            } else if messages.count > lastMessageCount {
                let newMsgs = messages[lastMessageCount..<messages.count]
                for msg in newMsgs {
                    let sender = msg.sender
                    let dest = msg.dest
                    
                    if dest == "0" || dest == "" {
                        if let myNode = activeNodes.first(where: { String($0.id) == sender }) {
                            for neighborId in myNode.neighbors {
                                activeAnimations.append(PacketAnimation(senderId: sender, receiverId: String(neighborId)))
                            }
                        }
                    } else {
                        activeAnimations.append(PacketAnimation(senderId: sender, receiverId: dest))
                    }
                }
                lastMessageCount = messages.count
            }
        }
        
        private func setupPipelines() {
            guard let device = device else { return }
            
            do {
                guard let library = device.makeDefaultLibrary() else {
                    print("[MetalTopologyView] Error: Could not load default library")
                    return
                }
                
                let pointVert = library.makeFunction(name: "vertex_point")
                let pointFrag = library.makeFunction(name: "fragment_point")
                let lineVert = library.makeFunction(name: "vertex_line")
                let lineFrag = library.makeFunction(name: "fragment_line")
                let packetVert = library.makeFunction(name: "vertex_packet")
                
                let colorFormat = MTLPixelFormat.bgra8Unorm
                
                let pointDesc = MTLRenderPipelineDescriptor()
                pointDesc.vertexFunction = pointVert
                pointDesc.fragmentFunction = pointFrag
                pointDesc.colorAttachments[0].pixelFormat = colorFormat
                pointDesc.colorAttachments[0].isBlendingEnabled = true
                pointDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                pointDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                pointPipelineState = try device.makeRenderPipelineState(descriptor: pointDesc)
                
                let lineDesc = MTLRenderPipelineDescriptor()
                lineDesc.vertexFunction = lineVert
                lineDesc.fragmentFunction = lineFrag
                lineDesc.colorAttachments[0].pixelFormat = colorFormat
                lineDesc.colorAttachments[0].isBlendingEnabled = true
                lineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                lineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                linePipelineState = try device.makeRenderPipelineState(descriptor: lineDesc)
                
                let packetDesc = MTLRenderPipelineDescriptor()
                packetDesc.vertexFunction = packetVert
                packetDesc.fragmentFunction = pointFrag
                packetDesc.colorAttachments[0].pixelFormat = colorFormat
                packetDesc.colorAttachments[0].isBlendingEnabled = true
                packetDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                packetDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                packetPipelineState = try device.makeRenderPipelineState(descriptor: packetDesc)
                
            } catch {
                print("[MetalTopologyView] Error setup pipelines: \(error.localizedDescription)")
            }
        }
        
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
        
        func draw(in view: MTKView) {
            dataLock.lock()
            let currentLayouts = self.nodeLayouts
            let currentNodes = self.activeNodes
            
            // 1. Update packet animations
            var updatedAnims: [PacketAnimation] = []
            var packetPositions: [SIMD2<Float>] = []
            var packetColors: [SIMD4<Float>] = []
            
            for var anim in activeAnimations {
                anim.progress += anim.speed
                if anim.progress < 1.0 {
                    updatedAnims.append(anim)
                    
                    if let layoutA = currentLayouts.first(where: { $0.id == anim.senderId }),
                       let layoutB = currentLayouts.first(where: { $0.id == anim.receiverId }) {
                        let ax = Float(layoutA.position.x)
                        let ay = Float(layoutA.position.y)
                        let bx = Float(layoutB.position.x)
                        let by = Float(layoutB.position.y)
                        
                        let px = ax * (1.0 - anim.progress) + bx * anim.progress
                        let py = ay * (1.0 - anim.progress) + by * anim.progress
                        packetPositions.append(SIMD2<Float>(px, py))
                        
                        // glowing violet packets
                        packetColors.append(SIMD4<Float>(0.58, 0.42, 1.0, 1.0))
                    }
                }
            }
            activeAnimations = updatedAnims
            dataLock.unlock()
            
            guard let device = device,
                  let commandQueue = commandQueue,
                  let renderPassDescriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable else {
                return
            }
            
            view.colorPixelFormat = .bgra8Unorm
            
            // 2. Prepare Vertex Data
            var nodePositions: [SIMD2<Float>] = []
            var nodeColors: [SIMD4<Float>] = []
            
            for layout in currentLayouts {
                nodePositions.append(SIMD2<Float>(Float(layout.position.x), Float(layout.position.y)))
                let nsColor = NSColor(layout.color)
                let alpha: Float = layout.isOnline ? 1.0 : 0.4
                nodeColors.append(SIMD4<Float>(Float(nsColor.redComponent), Float(nsColor.greenComponent), Float(nsColor.blueComponent), alpha))
            }
            
            var linePositions: [SIMD2<Float>] = []
            var lineColors: [SIMD4<Float>] = []
            var drawnLinks = Set<String>()
            
            for node in currentNodes {
                guard let layoutA = currentLayouts.first(where: { $0.id == String(node.id) }) else { continue }
                for neighborId in node.neighbors {
                    guard let layoutB = currentLayouts.first(where: { $0.id == String(neighborId) }) else { continue }
                    
                    let minId = min(node.id, neighborId)
                    let maxId = max(node.id, neighborId)
                    let linkKey = "\(minId)-\(maxId)"
                    
                    if !drawnLinks.contains(linkKey) {
                        drawnLinks.insert(linkKey)
                        linePositions.append(SIMD2<Float>(Float(layoutA.position.x), Float(layoutA.position.y)))
                        linePositions.append(SIMD2<Float>(Float(layoutB.position.x), Float(layoutB.position.y)))
                        
                        let linkColor = SIMD4<Float>(0.25, 0.78, 1.0, 0.35)
                        lineColors.append(linkColor)
                        lineColors.append(linkColor)
                    }
                }
            }
            
            // 3. Update/Create buffers
            func updateBuffer<T>(_ buffer: inout MTLBuffer?, data: [T], device: MTLDevice) {
                let size = data.count * MemoryLayout<T>.stride
                guard size > 0 else { return }
                if buffer == nil || buffer!.length < size {
                    buffer = device.makeBuffer(length: size, options: .storageModeShared)
                }
                if let buffer = buffer {
                    memcpy(buffer.contents(), data, size)
                }
            }
            
            updateBuffer(&nodePosBuffer, data: nodePositions, device: device)
            updateBuffer(&nodeColBuffer, data: nodeColors, device: device)
            updateBuffer(&linePosBuffer, data: linePositions, device: device)
            updateBuffer(&lineColBuffer, data: lineColors, device: device)
            updateBuffer(&packetPosBuffer, data: packetPositions, device: device)
            updateBuffer(&packetColBuffer, data: packetColors, device: device)
            
            // 4. Render
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
            
            if let linePosBuffer = linePosBuffer, let lineColBuffer = lineColBuffer, let linePipeline = linePipelineState, !linePositions.isEmpty {
                renderEncoder.setRenderPipelineState(linePipeline)
                renderEncoder.setVertexBuffer(linePosBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(lineColBuffer, offset: 0, index: 1)
                renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: linePositions.count)
            }
            
            if let nodePosBuffer = nodePosBuffer, let nodeColBuffer = nodeColBuffer, let pointPipeline = pointPipelineState, !nodePositions.isEmpty {
                renderEncoder.setRenderPipelineState(pointPipeline)
                renderEncoder.setVertexBuffer(nodePosBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(nodeColBuffer, offset: 0, index: 1)
                renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: nodePositions.count)
            }
            
            if let packetPosBuffer = packetPosBuffer, let packetColBuffer = packetColBuffer, let packetPipeline = packetPipelineState, !packetPositions.isEmpty {
                renderEncoder.setRenderPipelineState(packetPipeline)
                renderEncoder.setVertexBuffer(packetPosBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(packetColBuffer, offset: 0, index: 1)
                renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: packetPositions.count)
            }
            
            renderEncoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
