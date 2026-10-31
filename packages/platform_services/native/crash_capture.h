#ifndef VP_CRASH_CAPTURE_H
#define VP_CRASH_CAPTURE_H
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
// tvOS has no sigaltstack: the handler runs on the faulting stack there (a stack-overflow
// crash is then not captured; every other fatal signal is).
#if defined(__APPLE__) && TARGET_OS_TV
#define VP_ALTSTACK 0
#else
#define VP_ALTSTACK 1
#endif
#if defined(__APPLE__)
#include <sys/ucontext.h>
#else
#include <ucontext.h>
#endif

static const int vp_signals[] = {SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV};
static struct sigaction vp_previous[5];
static volatile sig_atomic_t vp_fd = -1;
static int vp_pipe[2] = {-1, -1};
static unsigned char vp_alt_memory[65536];
static stack_t vp_old_stack;
static int vp_installed = 0;
static atomic_flag vp_recording = ATOMIC_FLAG_INIT;

static void vp_redeliver(int number) {
  for (int i = 0; i < 5; ++i) {
    if (vp_signals[i] != number) continue;
    struct sigaction previous = vp_previous[i];
    if (previous.sa_handler == SIG_IGN) previous.sa_handler = SIG_DFL;
    (void)sigaction(number, &previous, NULL);
    break;
  }
  (void)raise(number);
}

static void vp_hex(uintptr_t value, off_t *offset) {
  char line[2 + sizeof(uintptr_t) * 2 + 1];
  const char digits[] = "0123456789abcdef";
  line[0] = '0'; line[1] = 'x';
  for (unsigned i = 0; i < sizeof(uintptr_t) * 2; ++i)
    line[2 + i] = digits[(value >> ((sizeof(uintptr_t) * 2 - 1 - i) * 4)) & 15];
  line[sizeof(line) - 1] = '\n';
  (void)pwrite(vp_fd, line, sizeof(line), *offset);
  *offset += sizeof(line);
}

static void vp_signal(int number, siginfo_t *info, void *context) {
  (void)info;
  // atomic_flag is guaranteed lock-free; only one fatal thread owns the record.
  if (atomic_flag_test_and_set_explicit(&vp_recording, memory_order_relaxed)) {
    vp_redeliver(number);
    return;
  }
  uintptr_t pc = 0, fp = 0;
  ucontext_t *uc = (ucontext_t *)context;
#if defined(__APPLE__) && defined(__aarch64__)
  pc = uc->uc_mcontext->__ss.__pc; fp = uc->uc_mcontext->__ss.__fp;
#elif defined(__APPLE__) && defined(__x86_64__)
  pc = uc->uc_mcontext->__ss.__rip; fp = uc->uc_mcontext->__ss.__rbp;
#elif defined(__aarch64__)
  pc = uc->uc_mcontext.pc; fp = uc->uc_mcontext.regs[29];
#elif defined(__arm__)
  pc = uc->uc_mcontext.arm_pc; fp = uc->uc_mcontext.arm_fp;
#elif defined(__x86_64__)
  pc = uc->uc_mcontext.gregs[REG_RIP]; fp = uc->uc_mcontext.gregs[REG_RBP];
#endif
  off_t offset = 0;
  const char title[] = "native fatal signal\n";
  (void)pwrite(vp_fd, title, sizeof(title) - 1, offset); offset += sizeof(title) - 1;
  vp_hex((uintptr_t)number, &offset);
  const char label[] = "stack (raw addresses)\n";
  (void)pwrite(vp_fd, label, sizeof(label) - 1, offset); offset += sizeof(label) - 1;
  vp_hex(pc, &offset);
  for (int i = 0; i < 31 && fp != 0; ++i) {
    uintptr_t frame[2];
    // The kernel validates frame memory; corrupt pointers never get dereferenced here.
    if (write(vp_pipe[1], (void *)fp, sizeof(frame)) != sizeof(frame)) break;
    if (read(vp_pipe[0], frame, sizeof(frame)) != sizeof(frame)) break;
    vp_hex(frame[1], &offset);
    if (frame[0] <= fp || frame[0] - fp > 1024 * 1024) break;
    fp = frame[0];
  }
  (void)fsync(vp_fd);
  // Re-delivery runs the original fatal action after our handler returns.
  vp_redeliver(number);
}

void vp_crash_uninstall(void) {
  if (!vp_installed) return;
  for (int i = 0; i < 5; ++i) (void)sigaction(vp_signals[i], &vp_previous[i], NULL);
#if VP_ALTSTACK
  (void)sigaltstack(&vp_old_stack, NULL);
#endif
  close(vp_fd); close(vp_pipe[0]); close(vp_pipe[1]);
  vp_fd = -1; vp_installed = 0;
}

int vp_crash_install(const char *path) {
  if (!path || path[0] != '/') return EINVAL;
  vp_crash_uninstall();
  int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0) return errno;
  if (pipe(vp_pipe) != 0) { int code = errno; close(fd); return code; }
  if (fcntl(vp_pipe[0], F_SETFL, O_NONBLOCK) == -1 ||
      fcntl(vp_pipe[1], F_SETFL, O_NONBLOCK) == -1 ||
      fcntl(vp_pipe[0], F_SETFD, FD_CLOEXEC) == -1 ||
      fcntl(vp_pipe[1], F_SETFD, FD_CLOEXEC) == -1) {
    int code = errno; close(fd); close(vp_pipe[0]); close(vp_pipe[1]); return code;
  }
#if VP_ALTSTACK
  stack_t stack = {0}; stack.ss_sp = vp_alt_memory; stack.ss_size = sizeof(vp_alt_memory);
  if (sigaltstack(&stack, &vp_old_stack) != 0) {
    int code = errno; close(fd); close(vp_pipe[0]); close(vp_pipe[1]); return code;
  }
#endif
  atomic_flag_clear_explicit(&vp_recording, memory_order_relaxed);
  vp_fd = fd;
  struct sigaction action = {0};
  action.sa_sigaction = vp_signal;
  action.sa_flags = SA_SIGINFO | (VP_ALTSTACK ? SA_ONSTACK : 0);
  sigfillset(&action.sa_mask);
  for (int i = 0; i < 5; ++i) {
    if (sigaction(vp_signals[i], &action, &vp_previous[i]) != 0) {
      int code = errno;
      while (i-- > 0) sigaction(vp_signals[i], &vp_previous[i], NULL);
#if VP_ALTSTACK
      sigaltstack(&vp_old_stack, NULL);
#endif
      close(fd); close(vp_pipe[0]); close(vp_pipe[1]); vp_fd = -1;
      return code;
    }
  }
  vp_installed = 1;
  return 0;
}

void vp_crash_abort(void) { abort(); }
#endif
