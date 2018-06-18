//
//  Shaders.metal
//  ExploringMetal
//
//  Created by Adil Patel on 31/05/2018.
//  Copyright © 2018 Adil Patel. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// The uniforms... you can see a correspondence with the host side
typedef struct {
    float4x4 modelViewMatrix;
    float4x4 projectionMatrix;
    float4x4 normalMatrix;
} Uniforms;

// The layout in the vertex array
typedef struct {
    float4 position;
    float4 normal;
} Vertex;

// The output of the vertex shader, which will be fed into the fragment shader
typedef struct {
    float4 position [[position]];
    float4 normal;
    float4 worldSpaceCoordinate;
} RasteriserData;

vertex RasteriserData helloVertexShader(uint vertexID [[vertex_id]],
                                        device Vertex *vertices [[buffer(0)]],
                                        constant Uniforms &uniforms [[buffer(1)]]) {
    
    float4 position = vertices[vertexID].position;
    float4 normal = vertices[vertexID].normal;
    
    float4 transformedPos = uniforms.modelViewMatrix * position;
    
    RasteriserData out;
    
    out.position = uniforms.projectionMatrix * transformedPos;
    out.normal = uniforms.normalMatrix * normal;
    out.worldSpaceCoordinate = transformedPos;
    
    return out;
}

fragment float4 helloFragmentShader(RasteriserData in [[stage_in]]) {
    
    const float3 lightPos = float3(4.0f, 4.0f, 0.0f);
    const float4 lightColour = float4(1.0f, 1.0f, 1.0f, 1.0f);
    const float lightPower = 50.0f;
    
    const float4 ambientColour =  float4(0.2f, 0.0f, 0.0f, 1.0f);
    const float4 diffuseColour =  float4(0.5f, 0.0f, 0.0f, 1.0f);
    const float4 specularColour = float4(1.0f, 1.0f, 1.0f, 1.0f);
    const float shininess = 50.0f;
    
    // To start with, we need the light vector
    float3 pos = float3(in.worldSpaceCoordinate);
    float3 lightVec = lightPos - pos;
    float lightLength = length(lightVec);
    lightVec = normalize(lightVec);
    lightLength = lightLength * lightLength;
    
    float3 normal = normalize(float3(in.normal));
    
    // Now we calculate the Lambertian (diffuse) component
    float4 diffuse = max(dot(normal, lightVec), 0.0f) * diffuseColour;
    
    // Then the specular component
    float3 viewVec = normalize(-pos);
    float3 halfVec = normalize(lightVec + viewVec);
    
    float specCosine = max(dot(halfVec, normal), 0.0f);
    float4 specular = pow(specCosine, shininess) * specularColour;
    
    float4 brightness = lightPower / lightLength * lightColour;
    
    return ambientColour + (diffuse + specular) * brightness;
}
