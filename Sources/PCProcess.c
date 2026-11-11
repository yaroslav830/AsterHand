#include "PCProcess.h"
#include "PCRuntimePaths.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static double now_seconds(void) {
    struct timespec value;
    clock_gettime(CLOCK_MONOTONIC, &value);
    return value.tv_sec + value.tv_nsec / 1e9;
}

PCProcessResult PCRunShell(const char *shell, const char *command, const char *cwd,
                           double timeout, size_t limit, PCCancelCheck cancel, void *context) {
    PCProcessResult r = {0};
    r.exit_code = -1;
    r.output = calloc(limit + 1, 1);
    if (!r.output) { r.spawn_error = ENOMEM; return r; }
    if (cancel && cancel(context)) { r.cancelled = 1; return r; }
    int p[2];
    if (pipe(p) != 0) { r.spawn_error = errno; return r; }
    fcntl(p[0], F_SETFD, FD_CLOEXEC);
    fcntl(p[1], F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&actions, p[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, p[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, p[0]);
    posix_spawn_file_actions_addclose(&actions, p[1]);
    /* cwd travels as $1, command as $2: neither is interpolated into shell syntax. */
    char *argv[] = {(char *)shell, "-c", "cd -- \"$1\" && eval \"$2\"", "pocketcodex",
                    (char *)cwd, (char *)command, NULL};
    /* Deliberately do not inherit the app environment or any credentials. */
    // Dopamine's system hook performs per-binary trust before child exec. The
    // app's clean environment must not remove that jailbreak runtime. Only use
    // the fixed, root-owned runtime; never inherit arbitrary injected libraries.
    char *jailbreak_hook = NULL;
#if !defined(PC_ROOTHIDE) && !defined(PC_ROOTFUL)
    struct stat hook_stat;
    if (stat("/var/jb/basebin/systemhook.dylib", &hook_stat) == 0 && S_ISREG(hook_stat.st_mode) && hook_stat.st_uid == 0 && !(hook_stat.st_mode & 0022))
        jailbreak_hook = "DYLD_INSERT_LIBRARIES=/var/jb/basebin/systemhook.dylib";
#endif
    char *mobile_env[] = {PC_PROCESS_PATH,
                          "HOME=/var/mobile", "USER=mobile", "LOGNAME=mobile",
                          "TMPDIR=/tmp", "LANG=en_US.UTF-8", jailbreak_hook, NULL};
    char *root_env[] = {PC_PROCESS_PATH,
                        "HOME=/var/root", "USER=root", "LOGNAME=root",
                        "TMPDIR=/tmp", "LANG=en_US.UTF-8", jailbreak_hook, NULL};
    char **env = geteuid() == 0 ? root_env : mobile_env;
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attr, 0);
    pid_t pid = 0;
    r.spawn_error = posix_spawn(&pid, shell, &actions, &attr, argv, env);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    close(p[1]);
    if (r.spawn_error) { close(p[0]); return r; }
    fcntl(p[0], F_SETFL, fcntl(p[0], F_GETFL) | O_NONBLOCK);
    double start = now_seconds();
    int exited = 0, eof = 0, status = 0, killed = 0;
    for (;;) {
        if (!killed && cancel && cancel(context)) { r.cancelled = 1; killed = 1; }
        if (!killed && now_seconds() - start >= timeout) { r.timed_out = 1; killed = 1; }
        if (killed) kill(-pid, SIGKILL);
        /* Bound each drain, so a noisy child cannot starve timeout/cancellation. */
        for (int i = 0; i < 16 && !eof; i++) {
            char chunk[4096];
            ssize_t n = read(p[0], chunk, sizeof(chunk));
            if (n > 0) {
                size_t available = limit - r.output_length;
                size_t copied = (size_t)n < available ? (size_t)n : available;
                memcpy(r.output + r.output_length, chunk, copied);
                r.output_length += copied;
                if (copied < (size_t)n) r.truncated = 1;
            } else if (!n) { eof = 1; }
            else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) { eof = 1; }
            else break;
        }
        if (!exited) {
            pid_t w = waitpid(pid, &status, WNOHANG);
            if (w == pid) exited = 1;
            else if (w < 0 && errno != EINTR) { exited = 1; status = 0; }
        }
        if (exited && eof) break;
        if (exited) {
            /* Clean up ordinary background jobs inherited from the command. */
            kill(-pid, SIGKILL);
            if (now_seconds() - start >= timeout + 1.0) break;
        }
        if (killed && exited) break;
        struct pollfd fd = {p[0], POLLIN | POLLHUP, 0};
        if (!eof) poll(&fd, 1, 50);
        else { struct timespec pause = {0, 50000000}; nanosleep(&pause, NULL); }
    }
    kill(-pid, SIGKILL);
    close(p[0]);
    if (!exited) while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status)) r.exit_code = WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) r.exit_code = 128 + WTERMSIG(status);
    return r;
}

void PCFreeProcessResult(PCProcessResult *r) {
    free(r->output);
    r->output = NULL;
}
