cmake_minimum_required(VERSION 3.24)
project(transport_macos_dependencies NONE)
include(ExternalProject)
find_program(MAKE_EXECUTABLE make REQUIRED)
set(prefix "${CMAKE_BINARY_DIR}/prefix")
set(boost_source "${CMAKE_BINARY_DIR}/boost")

# Boost is header-only for libtorrent 2.1; no Boost binary libraries are built.
ExternalProject_Add(boost_headers
  URL https://archives.boost.io/release/1.92.0/source/boost_1_92_0.tar.bz2
  URL_HASH SHA256=5c1d40cb8e19adbf740a4ec2da35b3e58f3f5804b1dce44deb53df72193cbc6c
  SOURCE_DIR "${boost_source}"
  CONFIGURE_COMMAND "" BUILD_COMMAND "" INSTALL_COMMAND "")

ExternalProject_Add(openssl
  URL https://codeload.github.com/openssl/openssl/tar.gz/d3c1b1169b3569ff3069e5b399f47b2b28e03d79
  URL_HASH SHA256=f4e3080732a86b21e2220cf31c3c60026e923d6193bf371ba872e71fb13bb7c7
  CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=/usr/bin/clang
    MACOSX_DEPLOYMENT_TARGET=12.0
    <SOURCE_DIR>/Configure darwin64-arm64-cc no-shared no-tests no-module no-dso
    "--prefix=${prefix}" "--libdir=lib" -mmacosx-version-min=12.0
  BUILD_COMMAND "${MAKE_EXECUTABLE}" -j4
  INSTALL_COMMAND "${MAKE_EXECUTABLE}" install_sw)

# These are the same libtorrent/try_signal commits as the Android source build.
ExternalProject_Add(libtorrent
  GIT_REPOSITORY https://github.com/arvidn/libtorrent.git
  GIT_TAG 56ae8caba38bf154ffc210403cb23f91d0ecaa49
  GIT_SUBMODULES deps/try_signal
  UPDATE_COMMAND ""
  DEPENDS boost_headers openssl
  CMAKE_ARGS
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
    "-DCMAKE_INSTALL_PREFIX=${prefix}" -DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF
    -DBoost_NO_BOOST_CMAKE=ON "-DBoost_INCLUDE_DIR=${boost_source}"
    "-DOPENSSL_ROOT_DIR=${prefix}" -DOPENSSL_USE_STATIC_LIBS=TRUE
    "-DOPENSSL_INCLUDE_DIR=${prefix}/include"
    "-DOPENSSL_SSL_LIBRARY=${prefix}/lib/libssl.a"
    "-DOPENSSL_CRYPTO_LIBRARY=${prefix}/lib/libcrypto.a"
    -Dwebtorrent=OFF -Ddht=ON -Dencryption=ON
    -Dbuild_tests=OFF -Dbuild_examples=OFF -Dbuild_tools=OFF -Dpython-bindings=OFF
  BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --parallel 4)
