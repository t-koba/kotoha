cmake_minimum_required(VERSION 3.24)
project(kotoha_engine_probe LANGUAGES C CXX)

# Developer tooling only: no product target links this build.
if(ANDROID)
    if(NOT CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64" OR
       NOT CMAKE_SYSTEM_VERSION EQUAL 35 OR NOT ANDROID_STL STREQUAL "c++_static")
        message(FATAL_ERROR "Android probe requires API 35 x86_64 and c++_static")
    endif()
elseif(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8 OR
       NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(AMD64|amd64|x86_64)$")
    message(FATAL_ERROR "Probe selects Windows x64 or Android API 35 x86_64 only")
endif()

# Keep the selected closure CPU-only, static and independent of host ISA.
foreach(option IN ITEMS
    BUILD_SHARED_LIBS
    LLAMA_BUILD_COMMON LLAMA_BUILD_TESTS LLAMA_BUILD_TOOLS LLAMA_BUILD_EXAMPLES
    LLAMA_BUILD_SERVER LLAMA_BUILD_APP LLAMA_BUILD_UI LLAMA_BUILD_MTMD
    LLAMA_CONNECT LLAMA_OPENSSL LLAMA_SUBPROCESS LLAMA_USE_SYSTEM_GGML LLAMA_USE_PREBUILT_UI
    GGML_BUILD_TESTS GGML_BUILD_EXAMPLES
    GGML_BACKEND_DL GGML_NATIVE GGML_CPU_ALL_VARIANTS GGML_CCACHE
    GGML_SSE42 GGML_BMI2 GGML_AVX GGML_AVX_VNNI GGML_AVX2 GGML_AVX512 GGML_AVX512_VBMI
    GGML_AVX512_VNNI GGML_AVX512_BF16 GGML_AMX_TILE GGML_AMX_INT8
    GGML_AMX_BF16 GGML_FMA GGML_F16C
    GGML_OPENMP GGML_OPENMP_FETCH GGML_BLAS GGML_ACCELERATE GGML_METAL GGML_METAL_EMBED_LIBRARY
    GGML_LLAMAFILE GGML_CPU_HBM GGML_CPU_KLEIDIAI
    GGML_CUDA GGML_HIP GGML_VULKAN GGML_SYCL GGML_OPENCL
    GGML_CANN GGML_MUSA GGML_RPC GGML_ZDNN GGML_ZENDNN GGML_HEXAGON
    GGML_WEBGPU GGML_VIRTGPU GGML_VIRTGPU_BACKEND GGML_OPENVINO GGML_ET GGML_ET_SYSEMU)
    set(${option} OFF CACHE BOOL "Disabled for the static CPU probe" FORCE)
endforeach()
set(GGML_CPU ON CACHE BOOL "Selected probe backend" FORCE)

# The separately added example does not inherit upstream directory variables.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

include(FetchContent)
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/fixtures.json" fixture_manifest)
string(JSON source_url GET "${fixture_manifest}" files 0 url)
string(JSON source_sha256 GET "${fixture_manifest}" files 0 sha256)
FetchContent_Declare(llama_cpp
    URL "${source_url}"
    URL_HASH "SHA256=${source_sha256}"
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE)
FetchContent_MakeAvailable(llama_cpp)
# Reuse the pinned API consumer; do not enable the other upstream examples.
add_subdirectory("${llama_cpp_SOURCE_DIR}/examples/simple"
                 "${llama_cpp_BINARY_DIR}/examples/simple")
