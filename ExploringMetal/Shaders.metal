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
    float3x3 normalMatrix;
} Uniforms;

// The layout in the vertex array
typedef struct {
    packed_float3 position;
    packed_float3 normal;
    packed_float2 texCoord;
} Vertex;

// The output of the vertex shader, which will be fed into the fragment shader
typedef struct {
    float4 position [[position]];
    float4 normal;
    float4 worldSpaceCoordinate;
    float2 texCoord;
} RasteriserData;

// Light and material data
constant float3 lightPos = float3(4.0f, 4.0f, 0.0f);
constant half4 lightColour = half4(1.0f, 1.0f, 1.0f, 1.0f);
constant float lightPower = 50.0f;

constant half4 ambientColour =  half4(0.1f, 0.0f, 0.0f, 1.0f);
constant half4 specularColour = half4(1.0f, 1.0f, 1.0f, 1.0f);
constant float shininess = 50.0f;

vertex RasteriserData helloVertexShader(uint vertexID [[vertex_id]],
                                        device Vertex *vertices [[buffer(0)]],
                                        constant Uniforms &uniforms [[buffer(1)]]) {
    
    float4 position = float4(vertices[vertexID].position, 1.0f);
    float3 normal = float3(vertices[vertexID].normal);
    
    float4 transformedPos = uniforms.modelViewMatrix * position;
    
    RasteriserData out;
    
    out.position = uniforms.projectionMatrix * transformedPos;
    out.normal = float4(uniforms.normalMatrix * normal, 0.0f);
    out.worldSpaceCoordinate = transformedPos;
    out.texCoord = vertices[vertexID].texCoord;
    
    return out;
}

fragment half4 helloFragmentShader(RasteriserData in [[stage_in]],
                                    texture2d<float, access::sample> tex2d [[texture(0)]],
                                    sampler sampler2d [[sampler(0)]]) {
    
    // To start with, we need the light vector
    float3 pos = float3(in.worldSpaceCoordinate);
    float3 lightVec = lightPos - pos;
    float lightLength = length(lightVec);
    lightVec = normalize(lightVec);
    lightLength = lightLength * lightLength;
    
    float3 normal = normalize(float3(in.normal));
    
    half4 surfaceColour = half4(tex2d.sample(sampler2d, in.texCoord));
    
    // Now we calculate the Lambertian (diffuse) component
    half4 diffuse = saturate(dot(normal, lightVec)) * surfaceColour;
    
    // Then the specular component
    float3 viewVec = normalize(-pos);
    float3 halfVec = normalize(lightVec + viewVec);
    
    float specCosine = max(dot(halfVec, normal), 0.0f);
    half4 specular = pow(specCosine, shininess) * specularColour;
    
    half4 brightness = lightPower / lightLength * lightColour;
    
    return ambientColour + (diffuse + specular) * brightness;
}
