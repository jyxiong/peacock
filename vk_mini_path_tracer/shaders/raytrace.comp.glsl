#version 460 
#extension GL_EXT_scalar_block_layout : require
#extension GL_EXT_ray_query : require
#extension GL_GOOGLE_include_directive : require
#include "../common.h"

layout(local_size_x = WORKGROUP_WIDTH, local_size_y = WORKGROUP_HEIGHT, local_size_z = 1) in;

layout(binding = BINDING_IMAGEDATA, set = 0, rgba32f) uniform image2D storageImage;

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

#include "shaderCommon.h"

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


void main()
{
  const ivec2 resolution = imageSize(storageImage);

  const ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

  if (pixel.x >= resolution.x || pixel.y >= resolution.y)
  {
    return;
  }

  // State of the random number generator.
  uint rngState = resolution.x * (pushConstants.sample_batch * resolution.y + pixel.y) + pixel.x;  // Initial seed

  const vec3 cameraPosition = vec3(-0.001, 1.0, 53.0);
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
        const int sbtOffset = int(rayQueryGetIntersectionInstanceShaderBindingTableRecordOffsetEXT(rayQuery, true));

        ReturnedInfo returnedInfo;
        switch(sbtOffset)
        {
          case 0:
            returnedInfo = material0(rayQuery, rngState);
            break;
          case 1:
            returnedInfo = material1(rayQuery, rngState);
            break;
          case 2:
            returnedInfo = material2(rayQuery, rngState);
            break;
          case 3:
            returnedInfo = material3(rayQuery, rngState);
            break;
          case 4:
            returnedInfo = material4(rayQuery, rngState);
            break;
          case 5:
            returnedInfo = material5(rayQuery, rngState);
            break;
          case 6:
            returnedInfo = material6(rayQuery, rngState);
            break;
          case 7:
            returnedInfo = material7(rayQuery, rngState);
            break;
          default:
            returnedInfo = material8(rayQuery, rngState);
            break;
        }

        accumulatedRayColor *= returnedInfo.color;

        rayOrigin = returnedInfo.rayOrigin;
        rayDirection = returnedInfo.rayDirection;
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
  vec3 averagePixelColor = summedPixelColor / float(NUM_SAMPLES);
  if (pushConstants.sample_batch != 0)
  {
    const vec3 previousAverageColor = imageLoad(storageImage, pixel).rgb;

    averagePixelColor = (previousAverageColor * pushConstants.sample_batch + averagePixelColor) / (pushConstants.sample_batch + 1);
  }
  imageStore(storageImage, pixel, vec4(averagePixelColor, 0.0));
}