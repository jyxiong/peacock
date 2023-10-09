#include "renderer.h"

int main(int argc, const char** argv)
{
   // search path
  std::vector<std::string> searchPaths = {"D:/Learning/peacock/vk_mini_path_tracer"};

  Renderer renderer;

  renderer.createImage();

  renderer.loadModel("scenes/CornellBox-Original-Merged.obj", searchPaths);
  renderer.createBottomLevelAS();
  renderer.createTopLevelAS();
  
  renderer.loadShader("shaders/raytrace.comp.glsl.spv", searchPaths);
  renderer.createComputePipeline();
  
  renderer.updateDescriptorSet();

  renderer.rayTrace();

  renderer.saveImage("D:/Learning/peacock/build/out.hdr");
}
