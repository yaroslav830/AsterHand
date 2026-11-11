#pragma once
#ifdef PC_ROOTHIDE
#include <roothide.h>
#define PC_JB_EXEC(path) path
#define PC_PRIVILEGED_DIRECTORY "/var/pr"
#define PC_PROCESS_PATH "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
#else
// Rootful and ordinary rootless keep user data on the original filesystem.
static inline const char *jbroot(const char *path) { return path; }
static inline const char *rootfs(const char *path) { return path; }
#ifdef PC_ROOTFUL
#define PC_JB_EXEC(path) path
#define PC_PRIVILEGED_DIRECTORY "/var/lib/asterhand"
#define PC_PROCESS_PATH "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
#else
#define PC_JB_EXEC(path) "/var/jb" path
#define PC_PRIVILEGED_DIRECTORY "/var/jb/var/agentgo"
#define PC_PROCESS_PATH "PATH=/var/jb/usr/bin:/var/jb/bin:/var/jb/usr/sbin:/var/jb/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
#endif
#endif
