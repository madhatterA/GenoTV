param(
  [string]$BuildDirectory = 'C:\transport-native\libtorrent',
  [string]$CMake = 'C:\transport-native\tools\cmake\bin\cmake.exe',
  [string]$VisualStudio = 'C:\BuildTools',
  [string]$Msys = 'C:\msys64'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if ($BuildDirectory.Contains(' ')) { throw 'Native build cache must have no spaces' }
if (!(Test-Path $CMake)) { throw "Missing CMake 3.24+: $CMake" }
$vcvars = Join-Path $VisualStudio 'VC\Auxiliary\Build\vcvars64.bat'
cmd /c "call `"$vcvars`" >nul && set" | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
if ($LASTEXITCODE) { throw 'MSVC environment setup failed' }
$env:PATH = "$Msys\mingw64\bin;$env:PATH"
function Run-CMake([string[]]$Arguments) {
  & $CMake @Arguments
  if ($LASTEXITCODE) { throw "CMake failed ($LASTEXITCODE)" }
}
Run-CMake @('-S', "$root/tool/windows_deps", '-B', "$BuildDirectory/deps", '-G', 'Ninja',
  "-DCMAKE_MAKE_PROGRAM=$VisualStudio/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe")
Run-CMake @('--build', "$BuildDirectory/deps", '--parallel', '2')
$prefix = "$BuildDirectory/deps/prefix"
$boost = "$BuildDirectory/deps/boost"
$trySignal = git -C "$BuildDirectory/deps/libtorrent-prefix/src/libtorrent/deps/try_signal" rev-parse HEAD
if ($LASTEXITCODE -or $trySignal -ne '105cce59972f925a33aa6b1c3109e4cd3caf583d') { throw 'try_signal source pin mismatch' }
Run-CMake @('-S', "$root/src/lt_shim", '-B', "$BuildDirectory/shim", '-G', 'Ninja',
  "-DCMAKE_MAKE_PROGRAM=$VisualStudio/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja/ninja.exe",
  '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_C_COMPILER=cl', '-DCMAKE_CXX_COMPILER=cl',
  '-DTRANSPORT_LT_LIBRARY_TYPE=SHARED', "-DTRANSPORT_LIBTORRENT_ROOT=$prefix",
  '-DBoost_NO_BOOST_CMAKE=ON', "-DBoost_INCLUDE_DIR=$boost",
  "-DOPENSSL_ROOT_DIR=$prefix", '-DOPENSSL_USE_STATIC_LIBS=TRUE',
  "-DOPENSSL_INCLUDE_DIR=$prefix/include", "-DOPENSSL_SSL_LIBRARY=$prefix/lib/libssl.lib",
  "-DOPENSSL_CRYPTO_LIBRARY=$prefix/lib/libcrypto.lib", '-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON')
Run-CMake @('--build', "$BuildDirectory/shim", '--parallel', '2')
$out = "$root/windows/native"
New-Item -ItemType Directory -Force $out | Out-Null
$artifact = "$out/transport_lt_shim.dll"
Copy-Item "$BuildDirectory/shim/transport_lt_shim.dll" $artifact -Force
$exports = (& dumpbin /exports $artifact) -join "`n"
if ($LASTEXITCODE) { throw 'DLL export inspection failed' }
$symbols = [regex]::Matches((Get-Content "$root/src/lt_shim/lt_shim.h" -Raw), 'transport_lt_\w+(?=\s*\()') |
  ForEach-Object { $_.Value } | Sort-Object -Unique
foreach ($symbol in $symbols) {
  if ($exports -notmatch "\b$symbol\b") { throw "Missing ABI symbol: $symbol" }
}
Write-Output "transport_lt ABI symbols: $($symbols.Count), all exported"
& dumpbin /dependents $artifact
if ($LASTEXITCODE) { throw 'DLL dependency inspection failed' }
Get-FileHash $artifact -Algorithm SHA256
