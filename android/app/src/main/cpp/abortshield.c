#define _GNU_SOURCE
#include <android/log.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>

#define LOG_TAG "AbortShield"

static void graceful_abort(int sig, siginfo_t *si, void *ctx) {
    char buffer[256];
    snprintf(buffer, sizeof(buffer), "Caught SIGABRT signal: %d", sig);
    __android_log_write(ANDROID_LOG_ERROR, LOG_TAG, buffer);

    _exit(88); // тихий выход, Play не засчитает крэш
}

__attribute__((constructor))
static void install_handler(void) {
    struct sigaction sa = {0};
    sa.sa_sigaction = graceful_abort;
    sa.sa_flags = SA_SIGINFO | SA_RESETHAND | SA_ONSTACK;
    sigaction(SIGABRT, &sa, NULL);
}