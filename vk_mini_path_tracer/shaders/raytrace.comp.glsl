#version 460 
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_ray_query : require
#extension GL_GOOGLE_include_directive : require
#include "../common.h"

layout(local_size_x = WORKGROUP_WIDTH, local_size_y = WORKGROUP_HEIGHT, local_size_z = 1) in;

layout(binding = BINDING_IMAGEDATA, set = 0, scalar) buffer storageBuffer
{
  vec3 imageData[];
};

layout(binding = BINDING_TLAS, set = 0) uniform accelerationStructureEXT tlas;

layout(binding = BINDING_VERTICES, set = 0, scalar) buffer Vertices
{
  vec3 vertices[];
};

layout(binding = BINDING_INDICES, set = 0, scalar) buffer Indices
{
  uint indices[];
};

layout(push_constant) uniform PushConsts
{
  PushConstants pushConstants;
};

float stepAndOutputRNGFloat(inout uint rngState)
{
  // Condensed version of pcg_output_rxs_m_xs_32_32, with simple conversion to floating-point [0,1].
  rngState  = rngState * 747796405 + 1;
  uint word = ((rngState >> ((rngState >> 28) + 4)) ^ rngState) * 277803737;
  word      = (word >> 22) ^ word;
  return float(word) / 4294967295.0f;
}

const float k_pi = 3.14159265;

// Uses the Box-Muller transform to return a normally distributed (centered
// at 0, standard deviation 1) 2D point.
vec2 randomGaussian(inout uint rngState)
{
  // Almost uniform in (0, 1] - make sure the value is never 0:
  const float u1    = max(1e-38, stepAndOutputRNGFloat(rngState));
  const float u2    = stepAndOutputRNGFloat(rngState);  // In [0, 1]
  const float r     = sqrt(-2.0 * log(u1));
  const float theta = 2 * k_pi * u2;  // Random in [0, 2pi]
  return r * vec2(cos(theta), sin(theta));
}

vec3 skyColor(vec3 direction)
{
  if(direction.y > 0.0f)
  {
    return mix(vec3(1.0f), vec3(0.25f, 0.5f, 1.0f), direction.y);
  }
  else
  {
    return vec3(0.03f);
  }
}

struct HitInfo
{
  vec3 color;
  vec3 worldPosition;
  vec3 worldNormal;
};

HitInfo getObjectHitInfo(rayQueryEXT rayQuery)
{
  HitInfo result;

  // Get the ID of the triangle
  const int primitiveID = rayQueryGetIntersectionPrimitiveIndexEXT(rayQuery, true);

  // Get the indices of the vertices of the triangle
  const uint i0 = indices[3 * primitiveID + 0];
  const uint i1 = indices[3 * primitiveID + 1];
  const uint i2 = indices[3 * primitiveID + 2];

  // Get the vertices of the triangle
  const vec3 v0 = vertices[i0];
  const vec3 v1 = vertices[i1];
  const vec3 v2 = vertices[i2];

  // barycentric coordinates of the intersection
  vec3 barycentrics = vec3(0.0, rayQueryGetIntersectionBarycentricsEXT(rayQuery, true));
  barycentrics.x = 1.0 - barycentrics.y - barycentrics.z;

  // Compute the world position of the intersection
  result.worldPosition = barycentrics.x * v0 + barycentrics.y * v1 + barycentrics.z * v2;
  
  // Compute the normal of the triangle in object space
  result.worldNormal = normalize(cross(v1 - v0, v2 - v0));

  result.color = vec3(0.7);

  return result;
}

void main()
{
  const uvec2 resolution = uvec2(pushConstants.render_width, pushConstants.render_height);

  const uvec2 pixel = gl_GlobalInvocationID.xy;

  if (pixel.x >= resolution.x || pixel.y >= resolution.y)
  {
    return;
  }

  // State of the random number generator.
  uint rngState = resolution.x * (pushConstants.sample_batch * resolution.y + pixel.y) + pixel.x;  // Initial seed

  const vec3 cameraPosition = vec3(-0.001, 1.0, 6.0);
  const float fovVerticalSlope = 1.0 / 5.0;
  const float aspectRatio = float(resolution.x) / float(resolution.y);

  // The sum of the colors of all of the samples.
  vec3 summedPixelColor = vec3(0.0);
  // Limit the kernel to trace at most 64 samples.
  const int NUM_SAMPLES = 64;
  for(int sampleIdx = 0; sampleIdx < NUM_SAMPLES; sampleIdx++)
  {

    vec3 rayOrigin = cameraPosition;

    // Use a Gaussian with standard deviation 0.375 centered at the center of the pixel:
    const vec2 randomPixelCenter = vec2(pixel) + 0.5 + 0.375 * randomGaussian(rngState);
    const vec2 screenUV = 2.0 * randomPixelCenter / vec2(resolution) - 1.0;
    vec3 rayDirection = vec3(fovVerticalSlope * screenUV * vec2(aspectRatio, 1), -1.0);

    vec3 accumulatedRayColor = vec3(1.0);
    vec3 pixelColor          = vec3(0.0);

    // trace the ray
    for (int tracedSegments = 0; tracedSegments < 32; tracedSegments++)
    {
      rayQueryEXT rayQuery;
      rayQueryInitializeEXT(rayQuery, tlas, gl_RayFlagsNoneEXT, 0xFF, rayOrigin, 0.0, rayDirection, 10000.0);

      // get closet hit
      while (rayQueryProceedEXT(rayQuery))
      {
      }

      // check if the ray hit something
      if(rayQueryGetIntersectionTypeEXT(rayQuery, true) == gl_RayQueryCommittedIntersectionTriangleEXT)
      {
        HitInfo hitInfo = getObjectHitInfo(rayQuery);

        hitInfo.worldNormal = faceforward(hitInfo.worldNormal, rayDirection, hitInfo.worldNormal);

        accumulatedRayColor *= hitInfo.color;

        rayOrigin = hitInfo.worldPosition + 0.0001 * hitInfo.worldNormal;

        const float theta = 2.0 * k_pi * stepAndOutputRNGFloat(rngState);  // Random in [0, 2pi]
        const float u     = 2.0 * stepAndOutputRNGFloat(rngState) - 1.0;  // Random in [-1, 1]
        const float r     = sqrt(1.0 - u * u);
        rayDirection      = hitInfo.worldNormal + vec3(r * cos(theta), r * sin(theta), u);
        // Then normalize the ray direction:
        rayDirection = normalize(rayDirection);
      }
      else
      {
        // Ray hit the sky
        accumulatedRayColor *= skyColor(rayDirection);

        // Sum this with the pixel's other samples.
        summedPixelColor += accumulatedRayColor;

        break;
      }

    }
  }

  uint index = resolution.x * pixel.y + pixel.x;
  vec3 averageColor = summedPixelColor / float(NUM_SAMPLES);
  if (pushConstants.sample_batch != 0)
  {
    averageColor = (imageData[index] * float(pushConstants.sample_batch) + averageColor) / float(pushConstants.sample_batch + 1);
  }
  imageData[index] = averageColor;
}