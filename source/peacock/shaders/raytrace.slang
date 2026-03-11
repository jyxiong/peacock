import shaderio;

// Output image where the final rendered result will be stored
[[vk::binding(BindingIndex::eOutImage)]] RWTexture2D<float4> outImage;
[[vk::binding(BindingIndex::eSceneDesc)]] ConstantBuffer<SceneInfo> sceneInfo;

[shader("raygeneration")]
void rgenMain()
{
    // Get the current pixel coordinates and image dimensions
    float2 launchID = (float2)DispatchRaysIndex().xy;        // Current pixel (x,y)
    float2 launchSize = (float2)DispatchRaysDimensions().xy; // Image size (width,height)

    // Convert pixel coordinates to normalized device coordinates (NDC)
    // Range: [-1,1] for both x and y
    const float2 clipCoords = launchID / launchSize * 2.0 - 1.0;
    const float4 viewCoords = mul(float4(clipCoords, 1.0, 1.0), sceneInfo.projInvMatrix);

    // Get the final color from the ray tracing result
    float3 color = float3((clipCoords + 1.0) * 0.5, 0.0);

    // Write the result to the output image
    outImage[int2(launchID)] = float4(color, 1.0);
}