import module.shaderio;
#include "module/PNanoVDB.slang"

[[vk::binding(BindingIndex::eOutImage)]]  RWTexture2D<float4>         outImage;
[[vk::binding(BindingIndex::eSceneDesc)]] ConstantBuffer<SceneInfo>   sceneInfo;
[[vk::binding(BindingIndex::eVolumeGrid)]] StructuredBuffer<uint>     volumeGrid;
[[vk::binding(BindingIndex::eVolumeDesc)]] ConstantBuffer<VolumeDesc> volumeDesc;

// PNanoVDB HLSL 模式，32-bit 地址（HLSL 默认）
// #include "nanovdb/PNanoVDB.h"

// ---- 工具函数 ----------------------------------------

/// 射线与 AABB 相交，返回 [tMin, tMax]；若不相交返回 tMin > tMax
float2 intersectAABB(float3 ro, float3 rd, float3 bmin, float3 bmax)
{
    float3 invD = 1.0 / rd;
    float3 t0   = (bmin - ro) * invD;
    float3 t1   = (bmax - ro) * invD;
    float3 tNear = min(t0, t1);
    float3 tFar  = max(t0, t1);
    return float2(max(tNear.x, max(tNear.y, tNear.z)),
                  min(tFar.x,  min(tFar.y,  tFar.z)));
}

/// 对一点（index space）采样 float 密度
float sampleDensity(pnanovdb_buf_t buf, pnanovdb_readaccessor_t acc, float3 p)
{
    pnanovdb_coord_t ijk;
    ijk.x = int(floor(p.x));
    ijk.y = int(floor(p.y));
    ijk.z = int(floor(p.z));
    // 取值并乘缩放系数
    return pnanovdb_readaccessor_get_value_float(buf, acc, ijk) * volumeDesc.densityScale;
}

// ---- Ray Generation Shader ----------------------------------------

[shader("raygeneration")]
void rgenMain()
{
    float2 launchID   = (float2)DispatchRaysIndex().xy;
    float2 launchSize = (float2)DispatchRaysDimensions().xy;

    // NDC 重建世界空间射线
    float2 uv = launchID / launchSize * 2.0 - 1.0;
    float4 viewDir4 = mul(float4(uv, 1.0, 1.0), sceneInfo.projInvMatrix);
    float3 worldDir = normalize(mul(float4(viewDir4.xyz / viewDir4.w, 0.0),
                                    sceneInfo.viewInvMatrix).xyz);
    float3 worldOri = sceneInfo.cameraPosition;

    // 世界 → index space
    float3 indexOri = mul(float4(worldOri, 1.0), volumeDesc.worldToIndex).xyz;
    float3 indexDir = mul(float4(worldDir,  0.0), volumeDesc.worldToIndex).xyz;

    float4 color = float4(0, 0, 0, 1);

    // 射线与 index-space AABB 相交
    float2 tRange = intersectAABB(indexOri, indexDir, volumeDesc.bboxMin, volumeDesc.bboxMax);
    if (tRange.x < tRange.y)
    {
        // 初始化 PNanoVDB 访问器（从 grid offset 0 开始）
        pnanovdb_buf_t           buf  = volumeGrid;
        pnanovdb_grid_handle_t   grid = { 0u };
        pnanovdb_tree_handle_t   tree = pnanovdb_grid_get_tree(buf, grid);
        pnanovdb_root_handle_t   root = pnanovdb_tree_get_root(buf, tree);
        pnanovdb_readaccessor_t  acc;
        pnanovdb_readaccessor_init(acc, root);

        // Beer-Lambert 积分
        float transmittance = 1.0;
        float dt = volumeDesc.stepSize;
        float t  = max(tRange.x, 0.0);

        while (t < tRange.y && transmittance > 0.01)
        {
            float3 p     = indexOri + t * indexDir;
            float sigma  = max(0.0, sampleDensity(buf, acc, p));
            transmittance *= exp(-sigma * dt);
            t += dt;
        }

        // 用白色简单合成（后续可加 phase function / 光照）
        float alpha = 1.0 - transmittance;
        color = float4(alpha, alpha, alpha, 1.0);
    }

    outImage[int2(launchID)] = color;
}