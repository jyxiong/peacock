import module.shaderio;
import module.volume;
import module.math;

[[vk::binding(BindingIndex::eOutImage)]]  RWTexture2D<float4>         outImage;
[[vk::binding(BindingIndex::eSceneDesc)]] ConstantBuffer<SceneInfo>   sceneInfo;
[[vk::binding(BindingIndex::eVolumeGrid)]] StructuredBuffer<uint>     volumeGrid;
[[vk::binding(BindingIndex::eVolumeDesc)]] ConstantBuffer<VolumeDesc> volumeDesc;

[shader("raygeneration")]
void rgenMain()
{
    float2 launchID   = (float2)DispatchRaysIndex().xy;
    float2 launchSize = (float2)DispatchRaysDimensions().xy;

    float2 uv = ((launchID + 0.5) / launchSize) * 2.0 - 1.0;
    float3 worldOri = sceneInfo.cameraPositionUseSky.xyz;
    float3 forward = sceneInfo.cameraForwardTanHalfFov.xyz;
    float3 right = sceneInfo.cameraRightAspect.xyz;
    float3 up = sceneInfo.cameraUpPad.xyz;
    float tanHalfFov = sceneInfo.cameraForwardTanHalfFov.w;
    float aspect = sceneInfo.cameraRightAspect.w;

    float3 worldDir = normalize(forward
                                + uv.x * aspect * tanHalfFov * right
                                + uv.y * tanHalfFov * up);

    Ray ray = { worldOri, worldDir };
    BoundingBox bbox = volumeDesc.boundingBox();
    Optional<float2> hit = rayBoxIntersect(ray, bbox);
    float4 color = (hit != none) ? float4(1, 1, 1, 1) : float4(0, 0, 0, 1);

    outImage[int2(launchID)] = color;
}