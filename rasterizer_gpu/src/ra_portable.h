//
//  What the core and ra_frame.hpp need on platforms other than Apple's: always_inline, alloca, sincos, the processor count,
//  and a parallel for. The parallel for uses GCD's dispatch_apply_f on Apple platforms, as the original core does, and
//  std::thread elsewhere. Also bzero for MSVC, and raNonZero in place of GNU's x ?: 1, which MSVC lacks.
//

#pragma once
#include <atomic>
#include <exception>
#include <math.h>
#include <stddef.h>
#include <type_traits>

#ifdef _MSC_VER
#include <malloc.h>
#include <string.h>
#define RA_ALWAYS_INLINE __forceinline
#define RA_ALLOCA _alloca
static inline void bzero(void *s, size_t n) {
    memset(s, 0, n);
}
#else
#include <alloca.h>
#define RA_ALWAYS_INLINE __attribute__((always_inline))
#define RA_ALLOCA alloca
#endif

static inline size_t raNonZero(size_t x) {
    return x ? x : 1;
}

#ifdef __APPLE__
#include <dispatch/dispatch.h>
#include <unistd.h>

static inline size_t raProcessorCount() {
    long online = sysconf(_SC_NPROCESSORS_ONLN);
    return online < 1 ? 1 : size_t(online);
}
static inline void raDispatch(size_t count, void *context, void (*function)(void *, size_t)) {
    dispatch_apply_f(count, DISPATCH_APPLY_AUTO, context, function);
}
static inline void raSinCos(double x, double *sine, double *cosine) {
    __sincos(x, sine, cosine);
}
#else
#include <thread>
#include <vector>

static inline size_t raProcessorCount() {
    unsigned count = std::thread::hardware_concurrency();
    return count < 1 ? 1 : size_t(count);
}
// Threads are created for each call, not pooled, as callers make only a few calls a frame, each over at most one thread per
// processor. The iterations whose threads can't be created run on the caller's thread.
static inline void raDispatch(size_t count, void *context, void (*function)(void *, size_t)) {
    struct Threads {
        ~Threads() {
            for (std::thread& thread : threads)
                thread.join();
        }
        std::vector<std::thread> threads;
    } threads;
    threads.threads.reserve(count > 0 ? count - 1 : 0);
    size_t i = 1;
    try {
        for (; i < count; i++)
            threads.threads.emplace_back(function, context, i);
    } catch (...) {
        // Out of threads: the rest run here
    }
    if (count > 0)
        function(context, 0);
    for (; i < count; i++)
        function(context, i);
}
static inline void raSinCos(double x, double *sine, double *cosine) {
    *sine = sin(x), *cosine = cos(x);
}
#endif

// Calls function(context, i) for each i below count, in parallel. If a call throws, the first exception is rethrown on the
// caller's thread once all calls have returned, as an exception escaping a worker thread would end the process.
static inline void raParallelFor(size_t count, void *context, void (*function)(void *, size_t)) {
    struct Guarded {
        void *context;
        void (*function)(void *, size_t);
        std::atomic_flag thrown = ATOMIC_FLAG_INIT;
        std::exception_ptr exception;
    } guarded{ context, function };
    raDispatch(count, & guarded, [](void *context, size_t i) {
        Guarded& g = *(Guarded *)context;
        try {
            g.function(g.context, i);
        } catch (...) {
            if (!g.thrown.test_and_set())
                g.exception = std::current_exception();
        }
    });
    if (guarded.exception)
        std::rethrow_exception(guarded.exception);
}

template<typename F>
static inline void raParallelFor(size_t count, F&& f) {
    raParallelFor(count, & f, [](void *context, size_t i) { (*(std::remove_reference_t<F> *)context)(i); });
}
