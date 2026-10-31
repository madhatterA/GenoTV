#!/usr/bin/env bash
# Clean machine (CI): build the pinned macOS engine from source and install it into
# media_kit_libs_macos_video, the same steps a developer runs by hand:
# recipe prep, MoltenVK + libplacebo sources (same prep as build_libmpv_ios_metal.py),
# arm64 + amd64 engines, packaging over the upstream universal frameworks.
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
export LIBMPV_IOS_SIM_CACHE=${LIBMPV_IOS_SIM_CACHE:-/tmp/vp-libmpv-ios-recipe-v0.6.0}
LIBMPV_IOS_SIM_BUILD_ONLY=1 bash "$root/packages/playback/tool/build_libmpv_ios_sim.sh"
metal="$LIBMPV_IOS_SIM_CACHE/metal"
checkout() {
  [ -d "$metal/$1/.git" ] && return 0
  git init "$metal/$1"
  git -C "$metal/$1" remote add origin "$2"
  git -C "$metal/$1" fetch --depth 1 origin "$3"
  git -C "$metal/$1" checkout --detach "$3"
}
checkout MoltenVK https://github.com/KhronosGroup/MoltenVK.git 02a8c011a8ca077dfaa09f3b7ebf68be869dc26f
checkout libplacebo https://github.com/haasn/libplacebo.git ed29e541a55acf28022738440b2a925386292551
git -C "$metal/libplacebo" submodule update --init --recursive
git -C "$metal/libplacebo" checkout -- src/vulkan/utils_gen.py src/glsl/glslang.cc
git -C "$metal/MoltenVK" checkout -- MoltenVK/MoltenVK/Utility/MVKSmallVector.h MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm Common/MVKOSExtensions.mm
git -C "$metal/MoltenVK" apply --unidiff-zero --ignore-whitespace "$root/packages/playback/tool/ios_moltenvk_libcxx.patch"
python3 - "$metal/libplacebo" <<'PY'
import sys
from pathlib import Path
placebo = Path(sys.argv[1])
p = placebo / 'src/vulkan/utils_gen.py'
p.write_text(p.read_text().replace('VkXML(ET.parse(xmlfile))', 'VkXML(ET.parse(xmlfile).getroot())'))
p = placebo / 'src/glsl/glslang.cc'
p.write_text(p.read_text().replace('#if (GLSLANG_VERSION_MAJOR * 1000 + GLSLANG_VERSION_MINOR) >= 11013\n#include <glslang/Public/ResourceLimits.h>\n#define DefaultTBuiltInResource *GetDefaultResources()\n#endif\n', ''))
PY
MACOS_ARCH=arm64 python3 "$root/packages/playback/tool/build_libmpv_macos_metal.py"
MACOS_ARCH=amd64 python3 "$root/packages/playback/tool/build_libmpv_macos_metal.py"
flutter pub cache add media_kit_libs_macos_video --version 1.1.4
export MEDIA_KIT_MACOS_UPSTREAM="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/media_kit_libs_macos_video-1.1.4/macos/Frameworks"
make -C "$(dirname "$MEDIA_KIT_MACOS_UPSTREAM")"
python3 "$root/packages/playback/tool/package_macos_engine.py"
