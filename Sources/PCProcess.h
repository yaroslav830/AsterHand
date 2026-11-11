#pragma once
#include <stddef.h>

typedef int (*PCCancelCheck)(void *context);
typedef struct {
    char *output;
    size_t output_length;
    int exit_code;
    int spawn_error;
    int timed_out;
    int cancelled;
    int truncated;
} PCProcessResult;

/* Runs a process group with stdin closed, combined stdout/stderr, bounded output. */
PCProcessResult PCRunShell(const char *shell, const char *command, const char *cwd,
                           double timeout, size_t limit, PCCancelCheck cancel, void *context);
void PCFreeProcessResult(PCProcessResult *result);
