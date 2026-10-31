#!/usr/bin/env bash
# Source-pinned native iOS (default) or tvOS (LIBMPV_PLATFORM=tvos) Vulkan/Metal output, arm64 device and Simulator.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
cache=${LIBMPV_IOS_SIM_CACHE:-/tmp/vp-libmpv-ios-recipe-v0.6.0}
LIBMPV_IOS_SIM_BUILD_ONLY=1 LIBMPV_IOS_SIM_CACHE="$cache" bash "$root/packages/playback/tool/build_libmpv_ios_sim.sh"
if [ "${LIBMPV_PLATFORM:-ios}" != tvos ] && [ ! -d "$root/packages/media_kit_libs_ios_video/ios/Frameworks" ]; then
  LIBMPV_IOS_SIM_BUILD_ONLY=0 LIBMPV_IOS_SIM_CACHE="$cache" bash "$root/packages/playback/tool/build_libmpv_ios_sim.sh"
fi
export VP_IOS_ROOT="$root" VP_IOS_CACHE="$cache"
python3 "$root/packages/playback/tool/build_libmpv_ios_metal.py"
