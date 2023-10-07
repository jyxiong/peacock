#include "renderer.h"

int main(int argc, const char** argv)
{
   // search path
  std::vector<std::string> searchPaths = {"D:/Learning/nvpro_samples/bin_x64_debug/vk_mini_path_tracer_0_learn_vulkan"};

  Renderer renderer;

  renderer.createBuffer();

  renderer.loadModel("scenes/CornellBox-Original-Merged.obj", searchPaths);
  renderer.createBottomLevelAS();
  renderer.createTopLevelAS();
  
  renderer.loadShader("shaders/raytrace.comp.glsl.spv", searchPaths);
  renderer.createComputePipeline();
  
  renderer.updateDescriptorSet();

  renderer.rayTrace();

  renderer.saveImage("D:/Learning/nvpro_samples/vk_mini_path_tracer/build/out.hdr");
}
