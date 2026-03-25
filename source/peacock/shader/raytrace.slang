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

    float2 clipCoords = launchID / launchSize * 2.0 - 1.0;
    float4 viewCoords = mul(float4(clipCoords, 1.0, 1.0), sceneInfo.projInvMatrix);

    float3 worldOri = mul(float4(0.0, 0.0, 0.0, 1.0), sceneInfo.viewInvMatrix).xyz;
    float3 worldDir = mul(float4(normalize(viewCoords.xyz), 0.0), sceneInfo.viewInvMatrix).xyz;

    Ray ray = { worldOri, worldDir };
    BoundingBox bbox = volumeDesc.boundingBox();
    Optional<float2> hit = rayBoxIntersect(ray, bbox);

    float4 color = float4(0, 0, 0, 1);
    if (hit != none)
    {
        NanovdbVolume vol = { volumeGrid };
        float tNear    = max(hit.value.x, 0.0);
        float tFar     = hit.value.y;
        float stepSize = volumeDesc.stepSize();

        const float dt = 0.5;
        float transmittance = 1.0;


        float t = tNear;
        while (t < tFar)
        {
            float3 pos    = ray.o + t * ray.d;
            float sigma = vol(pos) * 0.1f;
            transmittance *= 1.0 - sigma * dt;

            t += stepSize;
        }

        color = float4(float3(1.0 - transmittance), 1.0);
    }

    outImage[int2(launchID)] = color;
}