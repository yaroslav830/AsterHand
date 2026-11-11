package com.pocketagent;

/** Monotonic-time policy. Waiting for AI/read-aloud never consumes the user's reply window. */
final class VoiceIdlePolicy {
    private int timeout;
    private boolean waiting;
    private long since = -1;
    synchronized void configure(int seconds, long elapsed) {
        if (seconds < 0 || seconds > 3600) throw new IllegalArgumentException("无回应结束时间须为 1 至 3600 秒");
        timeout = seconds;
        since = waiting ? elapsed : -1;
    }
    synchronized int timeout() { return timeout; }
    static int productTimeout(int stored) { return stored < 1 || stored > 3600 ? 5 : stored; }
    static int requireProductTimeout(int seconds) { if(seconds < 1 || seconds > 3600)throw new IllegalArgumentException("无回应结束时间须为 1 至 3600 秒");return seconds; }
    synchronized void update(boolean waitingForUser, boolean userInput, long elapsed) {
        if (!waitingForUser) since = -1;
        else if (!waiting || userInput || since < 0) since = elapsed;
        waiting = waitingForUser;
    }
    synchronized boolean paused() { return !waiting; }
    synchronized int remaining(long elapsed) {
        if (timeout == 0 || !waiting || since < 0) return 0;
        long left = timeout * 1000L - Math.max(0, elapsed - since);
        return (int) Math.max(0, (left + 999) / 1000);
    }
    synchronized boolean expired(long elapsed) {
        return timeout > 0 && waiting && since >= 0 && Math.max(0, elapsed - since) >= timeout * 1000L;
    }
}
