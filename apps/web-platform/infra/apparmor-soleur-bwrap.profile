#include <tunables/global>

profile soleur-bwrap flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Docker default abstractions
  network,
  capability,
  file,

  # Allow mount operations for bwrap/user namespaces
  mount,
  umount,
  pivot_root,

  # Deny dangerous operations
  deny @{PROC}/sys/kernel/{?,??,[^s][^h][^m]*} w,
  deny @{PROC}/sysrq-trigger rwklx,
  deny @{PROC}/kcore rwklx,
}
