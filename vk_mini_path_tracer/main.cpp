#include <cassert>
#include <nvvk/context_vk.hpp>
#include <nvvk/structs_vk.hpp>
#include <nvvk/resourceallocator_vk.hpp>

static const uint64_t render_width = 800;
static const uint64_t render_height = 600;

int main(int argc, const char** argv)
{
    // 上下文信息
    nvvk::ContextCreateInfo deviceInfo{};
    // 指定API版本
    deviceInfo.apiMajor = 1;
    deviceInfo.apiMinor = 2;
    // 加速结构的依赖
    deviceInfo.addDeviceExtension(VK_KHR_DEFERRED_HOST_OPERATIONS_EXTENSION_NAME);
    // 加速结构
    auto asFeatures = nvvk::make<VkPhysicalDeviceAccelerationStructureFeaturesKHR>();
    deviceInfo.addDeviceExtension(VK_KHR_ACCELERATION_STRUCTURE_EXTENSION_NAME, false, &asFeatures);
    // 射线查询
    auto rayQueryFeatures = nvvk::make<VkPhysicalDeviceRayQueryFeaturesKHR>();
    deviceInfo.addDeviceExtension(VK_KHR_RAY_QUERY_EXTENSION_NAME, false, &rayQueryFeatures);

    // 创建上下文
    nvvk::Context context;
    context.init(deviceInfo);

    // 必须包含加速结构和射线查询
    assert(asFeatures.accelerationStructure == VK_TRUE && rayQueryFeatures.rayQuery == VK_TRUE);

    // 创建资源分配器
    nvvk::ResourceAllocatorDedicated allocator;
    allocator.init(context, context.m_physicalDevice);

    // 创建framebuffer
    auto bufferSizeBytes = render_width * render_height * 3 * sizeof(float);
    auto bufferCreateInfo = nvvk::make<VkBufferCreateInfo>();
    bufferCreateInfo.size = bufferSizeBytes;
    bufferCreateInfo.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    // HOST_VISIBLE_BIT: cpu可以访问
    // HOST_CACHED_BIT: cpu可以缓存
    // HOST_COHERENT_BIT: cpu自动同步
    auto framebuffer = allocator.createBuffer(bufferCreateInfo, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
                                                                | VK_MEMORY_PROPERTY_HOST_CACHED_BIT
                                                                | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    
    // 从gpu获取内存
    void* data = allocator.map(framebuffer);
    float* fltData = reinterpret_cast<float*>(data);
    printf("first pixel: %f %f %f\n", fltData[0], fltData[1], fltData[2]);
    allocator.unmap(framebuffer);

    // 销毁framebuffer
    allocator.destroy(framebuffer);
    // 销毁资源分配器
    allocator.deinit();
    // 销毁上下文
    context.deinit();
}
