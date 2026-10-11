param(
  [string]$VisualStudio = 'C:\BuildTools',
  [string]$Msys = 'C:\msys64',
  [string]$Cache = '/c/transport-native/ffmpeg'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$vcvars = Join-Path $VisualStudio 'VC\Auxiliary\Build\vcvars64.bat'
cmd /c "call `"$vcvars`" >nul && set" | ForEach-Object {
  if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
if ($LASTEXITCODE) { throw 'MSVC environment setup failed' }
$env:MSYS2_PATH_TYPE = 'inherit'
$env:CAST_WINDOWS_TOOLCHAIN = 'msvc'
$env:CAST_FFMPEG_CACHE = $Cache
$env:CAST_WINDOWS_ROOT = $root
$buildScript = Join-Path $env:TEMP 'cast-build-ffmpeg.sh'
$scriptText = @'
export PATH="$(dirname "$(command -v cl)"):$PATH"
bash "$(cygpath -u "$CAST_WINDOWS_ROOT")/tool/build_ffmpeg.sh" windows x86_64
'@
[IO.File]::WriteAllText($buildScript, $scriptText.Replace("`r`n", "`n") + "`n", [Text.Encoding]::ASCII)
try {
  $shellScript = & "$Msys\usr\bin\cygpath.exe" -u $buildScript
  & "$Msys\usr\bin\bash.exe" -l $shellScript
  if ($LASTEXITCODE) { throw "FFmpeg build failed ($LASTEXITCODE)" }
} finally {
  Remove-Item $buildScript -ErrorAction SilentlyContinue
}
$prefix = "$root/native/ffmpeg/windows-x86_64"
$compat = & "$Msys\usr\bin\cygpath.exe" -w "$Cache/ffmpeg-8.0.1/compat/atomics/win32"
if ($LASTEXITCODE) { throw 'Cannot locate FFmpeg MSVC atomics compatibility header' }
$out = "$root/windows/native"
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
  & cl /nologo /std:c11 /O2 /MT /LD /W4 /D_CRT_SECURE_NO_WARNINGS "/I$prefix/include" "/I$compat" `
    "$root/native/remux/remux.c" /link "/OUT:$out/cast_remux.dll" "/LIBPATH:$prefix/lib" `
    libavformat.a libavcodec.a libavutil.a ws2_32.lib secur32.lib bcrypt.lib
  if ($LASTEXITCODE) { throw "Remux DLL build failed ($LASTEXITCODE)" }
  & cl /nologo /std:c11 /O2 /MT "/I$prefix/include" "$root/tool/check_ffmpeg.c" `
    /link /OUT:check_ffmpeg.exe "/LIBPATH:$prefix/lib" libavformat.a libavcodec.a libavutil.a ws2_32.lib secur32.lib bcrypt.lib
  if ($LASTEXITCODE) { throw 'FFmpeg registry proof build failed' }
  & .\check_ffmpeg.exe
  if ($LASTEXITCODE) { throw 'FFmpeg registry proof failed' }
  & dumpbin /dependents cast_remux.dll
  if ($LASTEXITCODE) { throw 'Remux dependency inspection failed' }
  Get-FileHash cast_remux.dll -Algorithm SHA256
} finally {
  Remove-Item remux.obj,remux.lib,remux.exp,cast_remux.lib,cast_remux.exp,check_ffmpeg.obj,check_ffmpeg.exe -ErrorAction SilentlyContinue
  Pop-Location
}
