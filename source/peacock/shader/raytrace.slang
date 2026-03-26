import module.shaderio;
import module.volume;
import module.math;

[[vk::binding(BindingIndex::eOutImage)]]  RWTexture2D<float4>         outImage;
[[vk::binding(BindingIndex::eSceneDesc)]] ConstantBuffer<SceneInfo>   sceneInfo;
[[vk::binding(BindingIndex::eVolumeGrid)]] StructuredBuffer<uint>     volumeGrid;
[[vk::binding(BindingIndex::eVolumeDesc)]] ConstantBuffer<VolumeDesc> volumeDesc;
[[vk::binding(BindingIndex::eHdrImage)]]  Sampler2D<float4>           hdrImage;

static const float kPI = 3.14159265358979323846f;

// PCG hash — fast, high-quality 32-bit random numbers
uint pcgHash(uint seed)
{
    uint state = seed * 747796405u + 2891336453u;
    uint word  = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

// Returns a uniform float in [0, 1) and advances the seed
float randFloat(inout uint seed)
{
    seed = pcgHash(seed);
    return float(seed) * (1.0 / 4294967296.0);
}

// Map a world-space direction to equirectangular UV and sample the HDR map
float3 sampleEnvLight(float3 dir)
{
    float phi   = atan2(dir.z, dir.x);               // [-PI, PI]
    float theta = asin(clamp(dir.y, -1.0f, 1.0f));   // [-PI/2, PI/2]
    float2 uv   = float2(phi / (2.0f * kPI) + 0.5f,
                         0.5f - theta / kPI);
    return hdrImage.SampleLevel(uv, 0).rgb;
}

// Henyey-Greenstein phase function importance sampling.
// dir: current ray travel direction; g: anisotropy in [-1, 1].
// Returns a new scattered direction.
float3 sampleHG(float3 dir, float g, float u1, float u2)
{
    float cosTheta;
    if (abs(g) < 1e-3f)
    {
        cosTheta = 1.0f - 2.0f * u1;
    }
    else
    {
        float tmp = (1.0f - g * g) / (1.0f - g + 2.0f * g * u1);
        cosTheta = (1.0f + g * g - tmp * tmp) / (2.0f * g);
    }
    cosTheta = clamp(cosTheta, -1.0f, 1.0f);
    float sinTheta = sqrt(max(0.0f, 1.0f - cosTheta * cosTheta));
    float phi = 2.0f * kPI * u2;

    // Build orthonormal frame around dir
    float3 up = abs(dir.y) < 0.9f ? float3(0, 1, 0) : float3(1, 0, 0);
    float3 s  = normalize(cross(up, dir));
    float3 t  = cross(dir, s);
    return cosTheta * dir + sinTheta * (cos(phi) * s + sin(phi) * t);
}

[shader("raygeneration")]
void rgenMain()
{
    uint2 launchID   = DispatchRaysIndex().xy;
    uint2 launchSize = DispatchRaysDimensions().xy;

    BoundingBox   bbox         = volumeDesc.boundingBox();
    NanovdbVolume vol          = { volumeGrid };
    float         sigmaMax     = volumeDesc.sigmaMax();
    float         densityScale = volumeDesc.densityScale();
    float         g            = volumeDesc.hgG();
    int           maxDepth     = sceneInfo.maxScatterDepth;
    uint          sampleCount  = sceneInfo.sampleCount;

    float3 accumColor = float3(0.0);

    for (uint s = 0; s < sampleCount; ++s)
    {
        // Unique seed per pixel / sample / frame
        uint seed = pcgHash(pcgHash(launchID.x + launchID.y * launchSize.x)
                            ^ (sceneInfo.frameIndex * sampleCount + s));

        // Jitter within the pixel
        float2 jitter     = float2(randFloat(seed), randFloat(seed));
        float2 clipCoords = (float2(launchID) + jitter) / float2(launchSize) * 2.0 - 1.0;
        float4 viewCoords = mul(float4(clipCoords, 1.0, 1.0), sceneInfo.projInvMatrix);

        float3 worldOri = mul(float4(0.0, 0.0, 0.0, 1.0), sceneInfo.viewInvMatrix).xyz;
        float3 worldDir = mul(float4(normalize(viewCoords.xyz), 0.0), sceneInfo.viewInvMatrix).xyz;

        Ray    ray       = { worldOri, worldDir };
        float3 pathColor = float3(0.0);

        // Multiple-scattering path loop
        for (int depth = 0; depth < maxDepth; ++depth)
        {
            Optional<float2> hit = rayBoxIntersect(ray, bbox);

            if (hit == none)
            {
                // Ray escaped — sample environment light
                pathColor = sampleEnvLight(ray.d);
                break;
            }

            float tNear    = max(hit.value.x, 0.0);
            float tFar     = hit.value.y;
            float t        = tNear;
            bool  scattered = false;

            // Delta tracking: sample next collision using majorant
            while (true)
            {
                t -= log(max(randFloat(seed), 1e-6f)) / sigmaMax;
                if (t >= tFar) break;  // exited the volume

                float3 pos   = ray.o + t * ray.d;
                float  sigma = vol.sample(pos) * densityScale;

                // Accept real collision with probability sigma / sigmaMax
                if (randFloat(seed) < sigma / sigmaMax)
                {
                    // Sample new scatter direction via HG phase function
                    float3 newDir = sampleHG(ray.d, g, randFloat(seed), randFloat(seed));
                    ray      = { pos, newDir };
                    scattered = true;
                    break;
                }
                // else: null collision — continue free-flight
            }

            if (!scattered)
            {
                // Ray exited the volume without scattering — sample environment
                pathColor = sampleEnvLight(ray.d);
                break;
            }
            // else: continue to next scattering depth
        }
        // If maxDepth exhausted, pathColor stays 0 (path terminated)

        accumColor += pathColor;
    }

    float3 newSample = accumColor / float(sampleCount);

    // Progressive temporal accumulation (running average across frames)
    // frameIndex is already incremented before this shader runs:
    //   frameIndex == 1 → first frame, write directly
    //   frameIndex >  1 → blend: lerp(history, newSample, 1/frameIndex)
    float3 finalColor;
    if (sceneInfo.frameIndex <= 1u)
    {
        finalColor = newSample;
    }
    else
    {
        float3 prevColor = outImage[int2(launchID)].rgb;
        float  alpha     = 1.0f / float(sceneInfo.frameIndex);
        finalColor = lerp(prevColor, newSample, alpha);
    }

    outImage[int2(launchID)] = float4(finalColor, 1.0);
}
