implementing shape;

// ── Disk shape ─────────────────────────────────────────────────────────────────
// Local space: unit disk (radius = 1) at z = 0.
// World transform provided by o2w / w2o matrices.

public struct DiskParam : IShapeParameter {
    public float4x4 o2w;  // object-to-world
    public float4x4 w2o;  // world-to-object
};

public struct Disk : IShape {
    public typealias TParam = DiskParam;

    // Ray-disk intersection test.
    static func intersect(Ray ray, TParam param) -> shape::HitResult {
        float3 ro = mul(float4(ray.o, 1.f), param.w2o).xyz;
        float3 rd = mul(float4(ray.d, 0.f), param.w2o).xyz;
        if (abs(rd.z) < M_MACHINE_EPSILON)
            return shape::HitResult(false, 0.f, float3(0.f));
        float tval = -ro.z / rd.z;
        if (tval <= 0.f)
            return shape::HitResult(false, 0.f, float3(0.f));
        float3 p = ro + tval * rd;
        if (dot(p.xy, p.xy) > 1.f)
            return shape::HitResult(false, 0.f, float3(0.f));
        float3 n = normalize(mul(float4(0.f, 0.f, 1.f, 0.f), param.o2w).xyz);
        return shape::HitResult(true, tval, n);
    }

    // Uniform area sample using concentric disk mapping.
    // PDF is in solid-angle measure w.r.t. refPoint.
    static func sample(float3 refPoint, float2 u, TParam param) -> shape::Sample {
        float  r        = sqrt(u.x);
        float  theta    = M_2PI * u.y;
        float3 localPos = float3(r * cos(theta), r * sin(theta), 0.f);
        float3 worldPos = mul(float4(localPos, 1.f), param.o2w).xyz;
        float3 n        = normalize(mul(float4(0.f, 0.f, 1.f, 0.f), param.o2w).xyz);
        float3 dir      = worldPos - refPoint;
        float  dist2    = dot(dir, dir);
        float  cosTheta = abs(dot(n, -normalize(dir)));
        shape::Sample s;
        s.position = worldPos;
        s.normal   = n;
        s.pdf      = (cosTheta > 0.f) ? dist2 / (_area(param) * cosTheta) : 0.f;
        return s;
    }

    // PDF (solid-angle measure) for an already-found surface point.
    static func pdf(float3 refPoint, float3 surfacePoint, float3 surfaceNormal, TParam param) -> float {
        float3 dir      = surfacePoint - refPoint;
        float  dist2    = dot(dir, dir);
        float  cosTheta = abs(dot(surfaceNormal, -normalize(dir)));
        return (cosTheta > 0.f) ? dist2 / (_area(param) * cosTheta) : 0.f;
    }

    // World-space surface area of the disk: PI * |ex × ey|.
    static func _area(TParam param) -> float {
        float3 ex = mul(float4(1.f, 0.f, 0.f, 0.f), param.o2w).xyz;
        float3 ey = mul(float4(0.f, 1.f, 0.f, 0.f), param.o2w).xyz;
        return M_PI * length(cross(ex, ey));
    }
};

