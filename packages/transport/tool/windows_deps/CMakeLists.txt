cmake_minimum_required(VERSION 3.24)
project(transport_windows_dependencies NONE)
include(ExternalProject)
find_program(PERL_EXECUTABLE perl REQUIRED)
find_program(NMAKE_EXECUTABLE nmake REQUIRED)
set(prefix "${CMAKE_BINARY_DIR}/prefix")
set(boost_source "${CMAKE_BINARY_DIR}/boost")

ExternalProject_Add(boost_headers
  URL https://archives.boost.io/release/1.92.0/source/boost_1_92_0.tar.bz2
  URL_HASH SHA256=5c1d40cb8e19adbf740a4ec2da35b3e58f3f5804b1dce44deb53df72193cbc6c
  SOURCE_DIR "${boost_source}"
  CONFIGURE_COMMAND "" BUILD_COMMAND "" INSTALL_COMMAND "")

ExternalProject_Add(openssl
  URL https://codeload.github.com/openssl/openssl/tar.gz/d3c1b1169b3569ff3069e5b399f47b2b28e03d79
  URL_HASH SHA256=f4e3080732a86b21e2220cf31c3c60026e923d6193bf371ba872e71fb13bb7c7
  CONFIGURE_COMMAND "${PERL_EXECUTABLE}" <SOURCE_DIR>/Configure VC-WIN64A
    no-shared no-tests no-module no-dso "--prefix=${prefix}" "--libdir=lib"
  BUILD_COMMAND "${NMAKE_EXECUTABLE}"
  INSTALL_COMMAND "${NMAKE_EXECUTABLE}" install_sw)

ExternalProject_Add(libtorrent
  GIT_REPOSITORY https://github.com/arvidn/libtorrent.git
  GIT_TAG 56ae8caba38bf154ffc210403cb23f91d0ecaa49
  GIT_SUBMODULES deps/try_signal
  UPDATE_COMMAND ""
  DEPENDS boost_headers openssl
  CMAKE_ARGS
    "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
    -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
    "-DCMAKE_INSTALL_PREFIX=${prefix}"
    -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF
    -DBoost_NO_BOOST_CMAKE=ON "-DBoost_INCLUDE_DIR=${boost_source}"
    "-DOPENSSL_ROOT_DIR=${prefix}" -DOPENSSL_USE_STATIC_LIBS=TRUE
    "-DOPENSSL_INCLUDE_DIR=${prefix}/include"
    "-DOPENSSL_SSL_LIBRARY=${prefix}/lib/libssl.lib"
    "-DOPENSSL_CRYPTO_LIBRARY=${prefix}/lib/libcrypto.lib"
    -Dwebtorrent=OFF -Ddht=ON -Dencryption=ON
    -Dbuild_tests=OFF -Dbuild_examples=OFF -Dbuild_tools=OFF -Dpython-bindings=OFF
  BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --parallel 2)
