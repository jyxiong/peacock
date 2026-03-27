import module.shaderio;
import module.math;
import module.random;
import module.volume;
import module.phase;
import module.medium;
import module.light;

// ── Resource bindings ─────────────────────────────────────────────────────────
[[vk::binding(BindingIndex::eOutImage)]]   RWTexture2D<float4>          outImage;
[[vk::binding(BindingIndex::eSceneDesc)]]  ConstantBuffer<SceneInfo>    sceneInfo;
[[vk::binding(BindingIndex::eVolumeGrid)]] StructuredBuffer<uint>       volumeGrid;
[[vk::binding(BindingIndex::eVolumeDesc)]] ConstantBuffer<VolumeDesc>   volumeDesc;
[[vk::binding(BindingIndex::eHdrImage)]]   Sampler2D<float4>            hdrImage;

// ── Entry point ───────────────────────────────────────────────────────────────
[shader("raygeneration")]
void rgenMain()
{
    uint2 launchID   = DispatchRaysIndex().xy;
    uint2 launchSize = DispatchRaysDimensions().xy;

    // Build the medium parameter from VolumeDesc / the NanoVDB grid buffer.
    NanovdbParam medParam = NanovdbParam(
        NanovdbVolume(volumeGrid),
        volumeDesc.sigmaMax(),
        volumeDesc.densityScale(),
        volumeDesc.hgG()
    );
    HGParam hgParam = HGParam(volumeDesc.hgG());

    BoundingBox bbox     = volumeDesc.boundingBox();
    int         maxDepth = sceneInfo.maxScatterDepth;
    uint        sppCount = sceneInfo.sampleCount;

    light::EnvironmentLight envLight = { hdrImage };

    // ── Per-pixel multi-sample accumulation ───────────────────────────────────
    float3 accumColor = float3(0.0f);

    for (uint s = 0; s < sppCount; ++s)
    {
        random::RandomSampler rng = random::init_random_sampler(launchID,
                                                                 sceneInfo.frameIndex,
                                                                 s);
        // Jitter within the pixel for anti-aliasing
        float2 jitter     = rng.next_float2();
        float2 clipCoords = (float2(launchID) + jitter) / float2(launchSize) * 2.0f - 1.0f;
        float4 viewCoords = mul(float4(clipCoords, 1.0f, 1.0f), sceneInfo.projInvMatrix);

        float3 worldOri = mul(float4(0.0f, 0.0f, 0.0f, 1.0f), sceneInfo.viewInvMatrix).xyz;
        float3 worldDir = mul(float4(normalize(viewCoords.xyz), 0.0f), sceneInfo.viewInvMatrix).xyz;

        Ray    ray       = { worldOri, worldDir };
        float3 pathColor = float3(0.0f);

        // ── Multiple-scattering path ──────────────────────────────────────────
        for (int depth = 0; depth < maxDepth; ++depth)
        {
            Optional<float2> boxHit = rayBoxIntersect(ray, bbox);
            if (!boxHit.hasValue)
            {
                pathColor = envLight.eval(ray.d);
                break;
            }

            float tNear = max(boxHit.value.x, 0.0f);
            float tFar  = boxHit.value.y;

            // Use IMedium::sample_ray to get the majorant iterator over [tNear, tFar].
            medium::HomogeneousMajorantIterator iter =
                NanovdbMedium::sample_ray(ray, tNear, tFar, medParam);

            bool scattered = false;

            // Walk through majorant segments (single segment for homogeneous majorant).
            medium::RayMajorantSegment seg = iter.next();
            while (seg.is_valid)
            {
                float sigma_maj = seg.sigma_maj.x; // scalar medium — channels are equal

                // Delta tracking inside this segment.
                float t = seg.tMin;
                while (true)
                {
                    t -= log(max(rng.next_float(), 1e-6f)) / sigma_maj;
                    if (t >= seg.tMax) break;

                    float3 pos = ray.o + t * ray.d;

                    // Query per-point medium properties via IMedium::sample_point.
                    medium::MediumProperties mp =
                        NanovdbMedium::sample_point(pos, medParam);

                    float sigma_s = mp.sigma_s.x;
                    float sigma_n = sigma_maj - sigma_s; // null scattering

                    float u = rng.next_float();
                    if (u < sigma_s / sigma_maj)
                    {
                        // Real scattering event: sample new direction via HG phase
                        phase::SampleResult scatter =
                            HGPhaseFunction::sample_p(ray.d, rng.next_float2(), hgParam);
                        ray       = { pos, scatter.wi };
                        scattered = true;
                        break;
                    }
                    else if (u < (sigma_s + sigma_n) / sigma_maj)
                    {
                        // Null collision — continue free-flight (no-op)
                    }
                    else
                    {
                        // Absorption — path terminates (pathColor stays 0)
                        scattered = true; // stop outer loop too
                        depth     = maxDepth;
                        break;
                    }
                }

                if (scattered) break;
                seg = iter.next();
            }

            if (!scattered)
            {
                // Ray exited the volume without scattering — evaluate environment
                pathColor = envLight.eval(ray.d);
                break;
            }
        }

        accumColor += pathColor;
    }

    float3 newSample = accumColor / float(sppCount);

    // ── Progressive temporal accumulation (running average across frames) ─────
    float3 finalColor;
    if (sceneInfo.frameIndex <= 1u)
    {
        finalColor = newSample;
    }
    else
    {
        float3 prevColor = outImage[int2(launchID)].rgb;
        float  alpha     = 1.0f / float(sceneInfo.frameIndex);
        finalColor       = lerp(prevColor, newSample, alpha);
    }

    outImage[int2(launchID)] = float4(finalColor, 1.0f);
}
