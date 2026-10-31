#pragma once
#include <windows.h>
#include <signal.h>
#include <stdint.h>
#include <string>
#include <atomic>

namespace platform_services::crash {
inline HANDLE file = INVALID_HANDLE_VALUE;
inline LPTOP_LEVEL_EXCEPTION_FILTER previous = nullptr;
inline void (*previous_abort)(int) = SIG_DFL;
inline std::atomic_flag recording = ATOMIC_FLAG_INIT;

inline void Write(const char* bytes, DWORD size, DWORD& offset) {
  OVERLAPPED position = {}; position.Offset = offset;
  DWORD written;
  WriteFile(file, bytes, size, &written, &position);
  offset += size;
}

inline void Hex(uintptr_t value, DWORD& offset) {
  char line[2 + sizeof(uintptr_t) * 2 + 1];
  const char digits[] = "0123456789abcdef";
  line[0] = '0'; line[1] = 'x';
  for (unsigned i = 0; i < sizeof(uintptr_t) * 2; ++i)
    line[2 + i] = digits[(value >> ((sizeof(uintptr_t) * 2 - 1 - i) * 4)) & 15];
  line[sizeof(line) - 1] = '\n';
  Write(line, sizeof(line), offset);
}

inline LONG WINAPI Capture(EXCEPTION_POINTERS* exception) {
  if (recording.test_and_set(std::memory_order_relaxed))
    return previous ? previous(exception) : EXCEPTION_CONTINUE_SEARCH;
  DWORD offset = 0;
  const char title[] = "native fatal exception\n";
  Write(title, sizeof(title) - 1, offset);
  Hex(exception->ExceptionRecord->ExceptionCode, offset);
  const char stack[] = "stack (raw addresses)\n";
  Write(stack, sizeof(stack) - 1, offset);
  uintptr_t fp = 0;
#if defined(_M_X64)
  Hex(exception->ContextRecord->Rip, offset); fp = exception->ContextRecord->Rbp;
#elif defined(_M_ARM64)
  Hex(exception->ContextRecord->Pc, offset); fp = exception->ContextRecord->Fp;
#elif defined(_M_IX86)
  Hex(exception->ContextRecord->Eip, offset); fp = exception->ContextRecord->Ebp;
#endif
  for (int i = 0; i < 31 && fp != 0; ++i) {
    uintptr_t frame[2]; SIZE_T read;
    if (!ReadProcessMemory(GetCurrentProcess(), reinterpret_cast<void*>(fp), frame, sizeof(frame), &read) || read != sizeof(frame)) break;
    Hex(frame[1], offset);
    if (frame[0] <= fp || frame[0] - fp > 1024 * 1024) break;
    fp = frame[0];
  }
  FlushFileBuffers(file);
  return previous ? previous(exception) : EXCEPTION_CONTINUE_SEARCH;
}

inline void Abort(int) { RaiseException(0xe0000001, EXCEPTION_NONCONTINUABLE, 0, nullptr); }
inline void Uninstall() {
  if (file == INVALID_HANDLE_VALUE) return;
  SetUnhandledExceptionFilter(previous);
  signal(SIGABRT, previous_abort);
  CloseHandle(file); file = INVALID_HANDLE_VALUE;
}

inline DWORD Install(const std::string& path) {
  if (path.empty() || path.find('\0') != std::string::npos) return ERROR_INVALID_PARAMETER;
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(), static_cast<int>(path.size()), nullptr, 0);
  if (!count) return GetLastError();
  std::wstring wide(count, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path.data(), static_cast<int>(path.size()), wide.data(), count);
  if (!(wide.size() > 2 && wide[1] == L':') && wide.rfind(L"\\\\", 0) != 0) return ERROR_INVALID_PARAMETER;
  Uninstall();
  file = CreateFileW(wide.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return GetLastError();
  recording.clear(std::memory_order_relaxed);
  previous = SetUnhandledExceptionFilter(Capture);
  previous_abort = signal(SIGABRT, Abort);
  return ERROR_SUCCESS;
}
}
