import module.shaderio;
import module.math;
import module.random;
import module.camera;
import module.volume;
import module.phase;
import module.medium;
import module.sampler;
import module.light;

// ── Resource bindings ─────────────────────────────────────────────────────────
[[vk::binding(BindingIndex::eOutImage)]]   RWTexture2D<float4>          outImage;
[[vk::binding(BindingIndex::eSceneDesc)]]  ConstantBuffer<SceneInfo>    sceneInfo;
[[vk::binding(BindingIndex::eVolumeGrid)]] StructuredBuffer<uint>       volumeGrid;
[[vk::binding(BindingIndex::eVolumeDesc)]] ConstantBuffer<VolumeDesc>   volumeDesc;
[[vk::binding(BindingIndex::eHdrImage)]]   Sampler2D<float4>            hdrImage;

// ── Power heuristic (beta = 2) ────────────────────────────────────────────────
func evalMISWeight(float pA, float pB) -> float
{
    float qA = pA * pA;
    float qB = pB * pB;
    return qA / max(qA + qB, 1e-8f);
}

// ── Type aliases for the active medium ───────────────────────────────────────
typealias MedParam = HeterogeneousParam<NanovdbVolume>;
typealias Med      = HeterogeneousMedium<NanovdbVolume>;

// ── Next-Event Estimation via environment light, weighted with MIS ────────────
// Samples a random direction from the envmap and weights against the phase PDF.
// `wo` is the current path direction (ray.d pointing away from the origin).
func evalNEE(
    float3                  scatterPos,
    float3                  wo,
    HGParam                 hgParam,
    MedParam                medParam,
    BoundingBox             bbox,
    light::EnvironmentLight envLight,
    inout random::RandomSampler rng
) -> float3
{
    // Sample the environment (uniform sphere, pdf = 1/4π).
    light::Interaction ls = envLight.sample(scatterPos, rng.next_float2());
    float pLight = ls.pdf;

    // Phase value and PDF for the sampled light direction.
    float fPhase = HGPhaseFunction::p(wo, ls.wi, hgParam);
    float pPhase = HGPhaseFunction::pdf(wo, ls.wi, hgParam);

    // Ratio-tracking transmittance to the light through the volume.
    float3 Tr = float3(1.0f);
    Ray shadowRay = { scatterPos, ls.wi };
    Optional<float2> shadowHit = rayBoxIntersect(shadowRay, bbox);
    if (shadowHit.hasValue)
    {
        float t0 = max(shadowHit.value.x, 1e-4f);
        float t1 = shadowHit.value.y;
        if (t1 > t0)
            Tr = sampler::eval_transmittance<Med>(shadowRay, t0, t1, medParam, rng);
    }

    float wMIS = evalMISWeight(pLight, pPhase);
    return fPhase * ls.L.rgb * Tr * (wMIS / max(pLight, 1e-8f));
}

// ── Trace a single volume-scattering path from a jittered pixel sample ────────
func traceVolumePath(
    uint2                   pixel,
    inout random::RandomSampler rng,
    MedParam                medParam,
    BoundingBox             bbox,
    int                     maxDepth,
    light::EnvironmentLight envLight,
    Film                    film,
    Camera                  cam
) -> float3
{
    float2 clipCoords = film.sample(pixel, rng.next_float2());
    Ray    ray        = cam.sample_ray(clipCoords);

    float3 L            = float3(0.0f);
    float3 thp          = float3(1.0f);
    float  prevPhasePdf = 0.0f;   // 0 → first bounce, no prior phase sample

    for (int depth = 0; depth < maxDepth; ++depth)
    {
        Optional<float2> boxHit = rayBoxIntersect(ray, bbox);

        // ── Miss: ray bypasses or exits the volume ────────────────────────────
        if (!boxHit.hasValue)
        {
            float3 Le = envLight.eval(ray.d);
            // Apply MIS weight if we arrived here via a phase sample (not first bounce).
            if (prevPhasePdf > 0.0f)
                Le *= evalMISWeight(prevPhasePdf, M_INV_4PI);
            L += thp * Le;
            break;
        }

        float tNear = max(boxHit.value.x, 0.0f);
        float tFar  = boxHit.value.y;

        // Delta-tracking: sample the next scatter position.
        Optional<sampler::DistanceSample> ds =
            sampler::sample_distance<Med>(ray, tNear, tFar, medParam, rng);

        // ── No scatter: ray transmitted through the entire volume ─────────────
        if (!ds.hasValue)
        {
            float3 Le = envLight.eval(ray.d);
            if (prevPhasePdf > 0.0f)
                Le *= evalMISWeight(prevPhasePdf, M_INV_4PI);
            L += thp * Le;
            break;
        }

        HGParam hgParam = HGParam(ds.value.g);

        // ── Direct lighting: NEE with phase–light power-heuristic MIS ─────────
        L += thp * evalNEE(ds.value.pos, ray.d, hgParam, medParam, bbox, envLight, rng);

        // ── Indirect: sample a new direction from the phase function ──────────
        phase::SampleResult scatter =
            HGPhaseFunction::sample_p(ray.d, rng.next_float2(), hgParam);
        thp          *= scatter.p / max(scatter.pdf, 1e-8f);
        prevPhasePdf  = scatter.pdf;

        // ── Russian Roulette early termination (after depth 2) ────────────────
        if (depth >= 2)
        {
            float q = saturate(max(thp.r, max(thp.g, thp.b)));
            if (rng.next_float() > q) break;
            thp /= max(q, 1e-3f);
        }

        ray = { ds.value.pos, scatter.wi };
    }

    return L;
}

// ── Progressive temporal running-average accumulation ─────────────────────────
func accumulate(uint2 launchID, float3 newSample) -> float3
{
    if (sceneInfo.frameIndex <= 1u)
        return newSample;
    float3 prev  = outImage[int2(launchID)].rgb;
    float  alpha = 1.0f / float(sceneInfo.frameIndex);
    return lerp(prev, newSample, alpha);
}

// ── Entry point ───────────────────────────────────────────────────────────────
[shader("raygeneration")]
void rgenMain()
{
    uint2 launchID   = DispatchRaysIndex().xy;
    uint2 launchSize = DispatchRaysDimensions().xy;

    MedParam medParam = MedParam(
        NanovdbVolume(volumeGrid),
        volumeDesc.sigma_a,
        volumeDesc.sigma_s,
        volumeDesc.Le,
        volumeDesc.majorant,
        volumeDesc.densityScale,
        volumeDesc.g
    );
    BoundingBox             bbox     = volumeDesc.boundingBox();
    int                     maxDepth = sceneInfo.maxScatterDepth;
    uint                    sppCount = sceneInfo.sampleCount;
    light::EnvironmentLight envLight = { hdrImage };
    Film                    film     = { launchSize };
    Camera                  cam      = { sceneInfo.projInvMatrix, sceneInfo.viewInvMatrix };

    // ── Per-pixel multi-sample loop ───────────────────────────────────────────
    float3 accumColor = float3(0.0f);
    for (uint s = 0; s < sppCount; ++s)
    {
        random::RandomSampler rng = random::init_random_sampler(launchID,
                                                                 sceneInfo.frameIndex, s);
        accumColor += traceVolumePath(launchID, rng, medParam, bbox, maxDepth,
                                      envLight, film, cam);
    }

    float3 newSample = accumColor / float(sppCount);
    outImage[int2(launchID)] = float4(accumulate(launchID, newSample), 1.0f);
}
