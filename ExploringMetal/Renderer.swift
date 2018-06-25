//
//  Renderer.swift
//  ExploringMetal
//
//  Created by Adil Patel on 31/05/2018.
//  Copyright © 2018 Adil Patel. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

enum RendererError: Error {
    case badVertexDescriptor
}

struct Uniforms {
    var modelViewMatrix: matrix_float4x4
    var projectionMatrix: matrix_float4x4
    var normalMatrix: matrix_float3x3
}

class Renderer: NSObject, MTKViewDelegate {

    // A handle to our device (which is the GPU)
    public let device: MTLDevice
    
    // The Metal render pipeline state
    var pipelineState: MTLRenderPipelineState
    
    // The Metal depth stencil state
    var depthState: MTLDepthStencilState
    
    // The Metal command queue
    let commandQueue: MTLCommandQueue
    
    // Moves our shape to camera space
    var modelViewMatrix = matrix_float4x4()
    
    // As the name suggests, our projection matrix
    var projectionMatrix = matrix_float4x4()
    
    // Holds the uniforms
    var uniforms: Uniforms
    
    // Will send our vertex array to Metal
    var vertexBuffer: MTLBuffer!
    
    // Will use to describe the polygons
    var indexBuffer: MTLBuffer!
    
    // Contains data of the geometry
    var subMesh: MTKSubmesh!
    
    // Self-explanatory
    var sphereTexture: MTLTexture!
    
    // The texture sampler which will be passed on to Metal
    var samplerState: MTLSamplerState?
    
    init?(metalKitView: MTKView) {
        
        self.device = metalKitView.device!
        
        metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
        
        let size = metalKitView.bounds.size
        
        // Create the modelview matrix, which is a simple series of translations and rotations
        let translationMatrix = matrix4x4_translation(0.0, 0.0, -5.0)
        let rotationMatrix = matrix4x4_rotation(radians: .pi / 2.0, axis: vector_float3(0.0, 1.0, 0.0))
        self.modelViewMatrix = translationMatrix * rotationMatrix
        
        let normalMatrix = makeNormalMatrix(inMatrix: modelViewMatrix)
        
        // Now create the projection matrix
        let aspect = Float(size.width) / Float(size.height)
        self.projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65),
                                                         aspectRatio:aspect,
                                                         nearZ: 0.1, farZ: 100.0)
        
        
        uniforms = Uniforms(modelViewMatrix: modelViewMatrix,
                            projectionMatrix: projectionMatrix,
                            normalMatrix: normalMatrix)
        
        let vertexDescriptor = makeVertexDescriptor()
        
        // Create the box in a more elegant and procedural manner
        let mesh: MTKMesh
        
        do {
            mesh = try makeMesh(device: self.device, vertexDescriptor: vertexDescriptor)
            self.vertexBuffer = mesh.vertexBuffers[0].buffer
            self.subMesh = mesh.submeshes[0]
            self.indexBuffer = subMesh.indexBuffer.buffer
        } catch {
            print("ERROR: Unable to create mesh.  Error info: \(error)")
        }
        

        
        // We're creating handles to the shaders...
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "helloVertexShader")
        let fragmentFunction = library?.makeFunction(name: "helloFragmentShader")
        
        // Here we create the render pipeline state. However, Metal doesn't allow
        // us to create one directly; we must use a descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = metalKitView.depthStencilPixelFormat
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            try self.pipelineState = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            print("ERROR: Failed to create the render pipeline state with error:\n\(error)")
            return nil
        }
        
        // Depth testing
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = .less
        depthStateDesciptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor:depthStateDesciptor) else { return nil }
        self.depthState = state
        
        do {
            self.sphereTexture = try createTexture(device: device, assetName: "Atlas", assetExtension: "jpg")
        } catch {
            print("ERROR: Failed to load texture with error:\n\(error)")
        }
        
       self.samplerState = createSampler(device: device)
        
        // And of course... a command queue
        self.commandQueue = self.device.makeCommandQueue()!
        
        super.init()

        
    }



    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        // So now we need a command buffer...
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        // We'll encode render commands into the command buffer using a render command encoder. However, like the
        // render pipeline state, we'll use a descriptor. This is known as the render pass descriptor
        let tempRenderPassDescriptor = view.currentRenderPassDescriptor // Note that we're using one suppplied by MTKView
        
        if let renderPassDescriptor = tempRenderPassDescriptor {
            
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
            // When loading the colour buffer, we clear it to the above-mentioned colour, which is black
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            
            
            // Copy the data into a buffer and set the render pipeline state
            renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            renderEncoder?.setRenderPipelineState(pipelineState)
            renderEncoder?.setDepthStencilState(depthState)
            renderEncoder?.setFragmentTexture(sphereTexture, index: 0)
            renderEncoder?.setFragmentSamplerState(samplerState, index: 0)
            
            let primitiveType = self.subMesh.primitiveType
            let indexCount = self.subMesh.indexCount
            let indexType  = self.subMesh.indexType
            
            renderEncoder?.drawIndexedPrimitives(type: primitiveType,
                                                 indexCount: indexCount,
                                                 indexType: indexType,
                                                 indexBuffer: self.indexBuffer,
                                                 indexBufferOffset: 0)
            
            renderEncoder?.endEncoding()
            
            // We'll render to the screen. MetalKit gives us drawables which we use for that
            commandBuffer?.present(view.currentDrawable!)
            
        }
        
        // Send it to the command queue
        commandBuffer?.commit()
        
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65), aspectRatio:aspect, nearZ: 0.1, farZ: 100.0)
        uniforms.projectionMatrix = projectionMatrix
        
    }
    
    
}

func createSampler(device: MTLDevice) -> MTLSamplerState? {
    
    // Configure the sampler
    let samplerDescriptor = MTLSamplerDescriptor()
    samplerDescriptor.sAddressMode = .repeat
    samplerDescriptor.tAddressMode = .repeat
    samplerDescriptor.minFilter = .nearest
    samplerDescriptor.magFilter = .linear
    
    // We could've used a bilinear filter for minification, but it fails when the pixel
    // covers more than 4 texels. This is because bilinear filters blend four texels
    
    return device.makeSamplerState(descriptor: samplerDescriptor)
    
}

func createTexture(device: MTLDevice, assetName: String, assetExtension: String) throws -> MTLTexture? {
    
    // Here we use MTKTextureLoader to handle our texture loading
    let textureLoader = MTKTextureLoader(device: device)
    let tempPath = Bundle.main.path(forResource: assetName, ofType: assetExtension)
    
    let textureOptions = [MTKTextureLoader.Option.origin : MTKTextureLoader.Origin.topLeft]
    if let path = tempPath {
        let url = URL(fileURLWithPath: path)
        return try textureLoader.newTexture(URL: url, options: textureOptions)
        
    } else {
        return nil
    }
    
}

func makeVertexDescriptor() -> MTLVertexDescriptor {
    // Create the vertex descriptor first...
    let vertexDescriptor = MTLVertexDescriptor()
    
    // Position
    vertexDescriptor.attributes[0].format = .float3
    vertexDescriptor.attributes[0].offset = 0 // Three floats causes 12 bytes of offset!
    vertexDescriptor.attributes[0].bufferIndex = 0
    
    // Normal
    vertexDescriptor.attributes[1].format = .float3
    vertexDescriptor.attributes[1].offset = 12 // This value is cumulative!
    vertexDescriptor.attributes[1].bufferIndex = 0
    
    // Texcoord
    vertexDescriptor.attributes[2].format = .float2
    vertexDescriptor.attributes[2].offset = 24
    vertexDescriptor.attributes[2].bufferIndex = 0
    
    // Interleave them
    vertexDescriptor.layouts[0].stride = 32
    vertexDescriptor.layouts[0].stepRate = 1
    vertexDescriptor.layouts[0].stepFunction = .perVertex
    
    return vertexDescriptor
}

func makeMesh(device: MTLDevice, vertexDescriptor: MTLVertexDescriptor) throws -> MTKMesh {
    
    let allocator = MTKMeshBufferAllocator(device: device)
    
    let mdlMesh = MDLMesh(sphereWithExtent: vector_float3(2.0, 2.0, 2.0),
                          segments: vector_uint2(50, 50),
                          inwardNormals: false,
                          geometryType: .triangles,
                          allocator: allocator)
    
    
    let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
    
    guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
        throw RendererError.badVertexDescriptor
    }
    attributes[0].name = MDLVertexAttributePosition
    attributes[1].name = MDLVertexAttributeNormal
    attributes[2].name = MDLVertexAttributeTextureCoordinate
    
    mdlMesh.vertexDescriptor = mdlVertexDescriptor
    
    return try MTKMesh(mesh: mdlMesh, device: device)
    
}

func makeNormalMatrix(inMatrix: matrix_float4x4) -> matrix_float3x3 {
    let (inCol1, inCol2, inCol3, _) = inMatrix.columns
    let row1 = vector_float3(inCol1[0], inCol2[0], inCol3[0])
    let row2 = vector_float3(inCol1[1], inCol2[1], inCol3[1])
    let row3 = vector_float3(inCol1[2], inCol2[2], inCol3[2])
    
    let upperLeft = matrix_from_rows(row1, row2, row3)
    return (upperLeft.inverse).transpose
}

// Generic matrix math utility functions

func matrix4x4_rotation(radians: Float, axis: float3) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}


