// 进入 /run/netns/uu，丢掉全部 capability，再以当前用户身份运行指定程序。
// 通过 security.wrappers 获得 cap_sys_admin；静态链接，不受 LD_PRELOAD 影响。
#define _GNU_SOURCE
#include <fcntl.h>
#include <linux/capability.h>
#include <sched.h>
#include <stdio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <program> [args...]\n", argv[0]);
    return 2;
  }

  int fd = open("/run/netns/uu", O_RDONLY | O_CLOEXEC);
  if (fd < 0 || setns(fd, CLONE_NEWNET) != 0) {
    perror("uu-netns: enter /run/netns/uu");
    return 1;
  }
  close(fd);

  struct __user_cap_header_struct header = {_LINUX_CAPABILITY_VERSION_3, 0};
  struct __user_cap_data_struct data[_LINUX_CAPABILITY_U32S_3] = {{0}};
  if (prctl(PR_CAP_AMBIENT, PR_CAP_AMBIENT_CLEAR_ALL, 0, 0, 0) != 0 ||
      syscall(SYS_capset, &header, data) != 0) {
    perror("uu-netns: drop capabilities");
    return 1;
  }

  execvp(argv[1], argv + 1);
  perror(argv[1]);
  return 127;
}
