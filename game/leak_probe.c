/* leak_probe.c - allocation counter for the headless runner.
 *
 * Interposed with `-Wl,--wrap=malloc,--wrap=free,--wrap=calloc,--wrap=realloc`.
 * It deliberately does NOT rewrite pointers or store headers: it only counts
 * live blocks, so a pointer allocated inside the C runtime and freed there is
 * unaffected. A leak shows up as live_blocks growing between the baseline taken
 * after startup and the count at exit.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *__real_malloc(size_t);
void  __real_free(void *);
void *__real_calloc(size_t, size_t);
void *__real_realloc(void *, size_t);

static long s_live_blocks = 0;
static long s_live_peak = 0;
static long s_total_allocs = 0;

static void note_alloc(void)
{
    s_total_allocs++;
    if (++s_live_blocks > s_live_peak) s_live_peak = s_live_blocks;
}

/* DSH_POISON_HEAP=1 fills fresh allocations with 0xFE, so a read of memory the
 * program never wrote shows up as garbage instead of a lucky zero. */
static int poison_on(void)
{
    static int cached = -1;
    if (cached < 0) cached = getenv("DSH_POISON_HEAP") ? 1 : 0;
    return cached;
}

void *__wrap_malloc(size_t n)
{
    void *p = __real_malloc(n);
    if (p) {
        note_alloc();
        if (poison_on()) memset(p, 0xFE, n);
    }
    return p;
}

void *__wrap_calloc(size_t a, size_t b)
{
    void *p = __real_calloc(a, b);
    if (p) note_alloc();
    return p;
}

void *__wrap_realloc(void *p, size_t n)
{
    void *q = __real_realloc(p, n);
    if (q && !p) note_alloc();
    return q;
}

void __wrap_free(void *p)
{
    if (p && s_live_blocks > 0) s_live_blocks--;
    __real_free(p);
}

long dsh_leak_live_blocks(void) { return s_live_blocks; }
long dsh_leak_peak_blocks(void) { return s_live_peak; }
long dsh_leak_total_allocs(void) { return s_total_allocs; }

void dsh_leak_report(const char *tag)
{
    fprintf(stderr, "[leak] %-10s live=%ld peak=%ld total=%ld\n",
            tag, s_live_blocks, s_live_peak, s_total_allocs);
}

/* Called by the host after the loop: returns the growth since `baseline`. */
long dsh_leak_delta(long baseline) { return s_live_blocks - baseline; }
