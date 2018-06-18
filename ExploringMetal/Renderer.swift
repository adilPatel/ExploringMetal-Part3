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
    var normalMatrix: matrix_float4x4
}

class Renderer: NSObject, MTKViewDelegate {

    // A handle to our device (which is the GPU)
    public let device: MTLDevice
    
    // The Metal render pipeline state
    var pipelineState: MTLRenderPipelineState!
    
    // The Metal depth stencil state
    var depthState: MTLDepthStencilState!
    
    // The Metal command queue
    var commandQueue: MTLCommandQueue!
    
    // Moves our shape to camera space
    var modelViewMatrix = matrix_float4x4()
    
    // As the name suggests, our projection matrix
    var projectionMatrix = matrix_float4x4()
    
    // Holds the uniforms
    var uniforms: Uniforms
    
    // The box information
    let vertexArray: [Float] = [
        
        1.0, -2.0, 0.5, 1.0,      0.0, -1.0, 0.0, 0.0,
        -1.0, -2.0, 0.5, 1.0,     0.0, -1.0, 0.0, 0.0,
        -1.0, -2.0, -0.5, 1.0,    0.0, -1.0, 0.0, 0.0,
        
        1.0, -2.0, -0.5, 1.0,     0.0, -1.0, 0.0, 0.0,
        1.0, -2.0, 0.5, 1.0,      0.0, -1.0, 0.0, 0.0,
        -1.0, -2.0, -0.5, 1.0,    0.0, -1.0, 0.0, 0.0,
        
        1.0, 2.0, 0.5, 1.0,       1.0, 0.0, 0.0, 0.0,
        1.0, -2.0, 0.5, 1.0,      1.0, 0.0, 0.0, 0.0,
        1.0, -2.0, -0.5, 1.0,     1.0, 0.0, 0.0, 0.0,
        
        1.0, 2.0, -0.5, 1.0,      1.0, 0.0, 0.0, 0.0,
        1.0, 2.0, 0.5, 1.0,       1.0, 0.0, 0.0, 0.0,
        1.0, -2.0, -0.5, 1.0,     1.0, 0.0, 0.0, 0.0,
        
        -1.0, 2.0, 0.5, 1.0,      0.0, 1.0, 0.0, 0.0,
        1.0, 2.0, 0.5, 1.0,       0.0, 1.0, 0.0, 0.0,
        1.0, 2.0, -0.5, 1.0,      0.0, 1.0, 0.0, 0.0,
        
        -1.0, 2.0, -0.5, 1.0,     0.0, 1.0, 0.0, 0.0,
        -1.0, 2.0, 0.5, 1.0,      0.0, 1.0, 0.0, 0.0,
        1.0, 2.0, -0.5, 1.0,      0.0, 1.0, 0.0, 0.0,
        
        -1.0, -2.0, 0.5, 1.0,     -1.0, 0.0, 0.0, 0.0,
        -1.0, 2.0, 0.5, 1.0,      -1.0, 0.0, 0.0, 0.0,
        -1.0, 2.0, -0.5, 1.0,     -1.0, 0.0, 0.0, 0.0,
        
        -1.0, -2.0, -0.5, 1.0,    -1.0, 0.0, 0.0, 0.0,
        -1.0, -2.0, 0.5, 1.0,     -1.0, 0.0, 0.0, 0.0,
        -1.0, 2.0, -0.5, 1.0,     -1.0, 0.0, 0.0, 0.0,
        
        1.0, 2.0, 0.5, 1.0,       0.0, 0.0, 1.0, 0.0,
        -1.0, 2.0, 0.5, 1.0,      0.0, 0.0, 1.0, 0.0,
        -1.0, -2.0, 0.5, 1.0,     0.0, 0.0, 1.0, 0.0,
        
        -1.0, -2.0, 0.5, 1.0,     0.0, 0.0, 1.0, 0.0,
        1.0, -2.0, 0.5, 1.0,      0.0, 0.0, 1.0, 0.0,
        1.0, 2.0, 0.5, 1.0,       0.0, 0.0, 1.0, 0.0,
        
        1.0, -2.0, -0.5, 1.0,     0.0, 0.0, -1.0, 0.0,
        -1.0, -2.0, -0.5, 1.0,    0.0, 0.0, -1.0, 0.0,
        -1.0, 2.0, -0.5, 1.0,     0.0, 0.0, -1.0, 0.0,
        
        1.0, 2.0, -0.5, 1.0,      0.0, 0.0, -1.0, 0.0,
        1.0, -2.0, -0.5, 1.0,     0.0, 0.0, -1.0, 0.0,
        -1.0, 2.0, -0.5, 1.0,     0.0, 0.0, -1.0, 0.0
        
    ]
    
    // Will send our vertex array to Metal
    var vertexBuffer: MTLBuffer!
    
    init?(metalKitView: MTKView) {
        
        self.device = metalKitView.device!
        
        metalKitView.depthStencilPixelFormat = .depth32Float_stencil8
        
        let size = metalKitView.bounds.size
        
        // Create the modelview matrix, which is a simple series of translations and rotations
        let translationMatrix = matrix4x4_translation(0.0, 0.0, -5.0)
        
        let rotationMatrix1 = matrix4x4_rotation(radians: .pi / 4.0, axis: vector_float3(1.0, 0.0, 0.0))
        let rotationMatrix2 = matrix4x4_rotation(radians: .pi / 4.0, axis: vector_float3(0.0, 1.0, 0.0))
        let rotationMatrix = rotationMatrix1 * rotationMatrix2

        modelViewMatrix = translationMatrix * rotationMatrix

        let normalMatrix = (modelViewMatrix.inverse).transpose
        
        // Now create the projection matrix
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65),
                                                         aspectRatio:aspect,
                                                         nearZ: 0.1, farZ: 100.0)
        
        
        uniforms = Uniforms(modelViewMatrix: modelViewMatrix,
                            projectionMatrix: projectionMatrix,
                            normalMatrix: normalMatrix)

        // We'll package all our vertices in a vertex buffer
        vertexBuffer = device.makeBuffer(bytes: vertexArray,
                                         length: MemoryLayout<Float>.size*vertexArray.count,
                                         options: .cpuCacheModeWriteCombined)
        
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
        
        do {
            try pipelineState = device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            print("ERROR: Failed to create the render pipeline state with error:\n\(error)")
        }
        
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = .less
        depthStateDesciptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor:depthStateDesciptor) else { return nil }
        depthState = state
        
        // And of course... a command queue
        commandQueue = device.makeCommandQueue()
        
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
            
            // So first we take care of the vertex buffer
            
            // Copy the data into a buffer and set the render pipeline state
            renderEncoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder?.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: 1)
            renderEncoder?.setRenderPipelineState(pipelineState)
            renderEncoder?.setDepthStencilState(depthState)
            
            // Draw
            let vertexCount = vertexArray.count / 8
            renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
            
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


