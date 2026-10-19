#!/usr/bin/env python3
"""Linux extraction boundary: no new privileges, no network, bounded resources.
The worker launches this without a shell; failures are closed, never unsandboxed.
"""
import ctypes
import ctypes.util
import errno
import os
import resource
import sys

resource.setrlimit(resource.RLIMIT_CPU, (90, 90))
resource.setrlimit(resource.RLIMIT_AS, (1536 * 1024 * 1024,) * 2)
resource.setrlimit(resource.RLIMIT_FSIZE, (64 * 1024 * 1024,) * 2)
resource.setrlimit(resource.RLIMIT_NOFILE, (128, 128))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(38, 1, 0, 0, 0) != 0:
    sys.exit(125)
try:
    sec = ctypes.CDLL(ctypes.util.find_library("seccomp") or "libseccomp.so.2")
    sec.seccomp_init.argtypes = [ctypes.c_uint32]
    sec.seccomp_init.restype = ctypes.c_void_p
    sec.seccomp_rule_add.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_int, ctypes.c_uint]
    sec.seccomp_load.argtypes = [ctypes.c_void_p]
    sec.seccomp_syscall_resolve_name.argtypes = [ctypes.c_char_p]
    ctx = sec.seccomp_init(0x7fff0000)  # SCMP_ACT_ALLOW
    if not ctx:
        sys.exit(125)
    # LibreOffice uses AF_UNIX IPC. Only local Unix sockets are permitted;
    # internet sockets cannot be created, and no descriptors are inherited.
    class ArgCompare(ctypes.Structure):
        _fields_ = [("arg", ctypes.c_uint), ("op", ctypes.c_int), ("datum_a", ctypes.c_uint64), ("datum_b", ctypes.c_uint64)]
    compare = ArgCompare(0, 1, 1, 0)  # arg 0 != AF_UNIX
    for syscall in ("socket", "socketpair"):
        number = sec.seccomp_syscall_resolve_name(syscall.encode())
        if sec.seccomp_rule_add(ctx, 0x50000 | errno.EPERM, number, 1, compare) != 0:
            sys.exit(125)
    for syscall in ("ptrace", "mount", "umount2", "bpf", "process_vm_readv", "process_vm_writev", "io_uring_setup"):
        number = sec.seccomp_syscall_resolve_name(syscall.encode())
        if number >= 0 and sec.seccomp_rule_add(ctx, 0x50000 | errno.EPERM, number, 0) != 0:
            sys.exit(125)
    if sec.seccomp_load(ctx) != 0:
        sys.exit(125)
except (OSError, AttributeError):
    sys.exit(125)
# Landlock limits filesystem access to runtime dependencies and this job's directory.
# Linux 5.13+ is required; unavailable isolation fails closed.
class Ruleset(ctypes.Structure):
    _fields_ = [("handled_access_fs", ctypes.c_uint64)]
class PathBeneath(ctypes.Structure):
    _pack_ = 1
    _fields_ = [("allowed_access", ctypes.c_uint64), ("parent_fd", ctypes.c_int32)]
abi = libc.syscall(444, 0, 0, 1)
if abi < 1:
    sys.exit(125)
mask = (1 << (15 if abi >= 3 else 14 if abi >= 2 else 13)) - 1
ruleset = Ruleset(mask)
fd = libc.syscall(444, ctypes.byref(ruleset), ctypes.sizeof(ruleset), 0)
if fd < 0:
    sys.exit(125)
read = (1 << 0) | (1 << 2) | (1 << 3)
paths = [(p, read) for p in ("/usr", "/lib", "/lib64", "/etc", "/proc/self", "/proc/meminfo", "/proc/cpuinfo", "/sys/devices/system/cpu", os.path.dirname(os.path.abspath(__file__)))]
paths += [("/tmp", 1 << 9), (os.getcwd(), mask), ("/dev/null", (1 << 1) | (1 << 2)), ("/dev/urandom", 1 << 2), ("/dev/random", 1 << 2)]
for path, access in paths:
    if not os.path.exists(path):
        continue
    parent = os.open(path, os.O_PATH | os.O_CLOEXEC)
    if not os.path.isdir(path):
        access &= (1 << 0) | (1 << 1) | (1 << 2) | (1 << 14)
    rule = PathBeneath(access, parent)
    if libc.syscall(445, fd, 1, ctypes.byref(rule), 0) != 0:
        sys.exit(125)
    os.close(parent)
if libc.syscall(446, fd, 0) != 0:
    sys.exit(125)
os.close(fd)
os.umask(0o077)
os.execvp(sys.argv[1], sys.argv[1:])
