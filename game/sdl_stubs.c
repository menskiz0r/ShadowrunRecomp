/* sdl_stubs.c - minimal SDL2 surface for a headless runner.
 *
 * The framework's audio.c talks to SDL for the device stream. A headless build
 * only needs the simulation side (ymfm/PSG), so these stubs keep the audio
 * module linkable without a window or a sound card.
 */
#include <stddef.h>
#include <stdint.h>

uint64_t SDL_GetPerformanceCounter(void) { return 0; }
uint64_t SDL_GetPerformanceFrequency(void) { return 1000000; }
void    *SDL_memset(void *dst, int c, size_t n) {
    unsigned char *p = (unsigned char *)dst;
    while (n--) *p++ = (unsigned char)c;
    return dst;
}
const char *SDL_GetError(void) { return "headless"; }
const char *SDL_GetCurrentAudioDriver(void) { return "headless"; }
void *SDL_OpenAudioDevice(const char *name, int capture, const void *want, void *have, int changes) {
    (void)name; (void)capture; (void)want; (void)have; (void)changes;
    return (void *)0;
}
void SDL_PauseAudioDevice(void *dev, int pause_on) { (void)dev; (void)pause_on; }
void SDL_CloseAudioDevice(void *dev) { (void)dev; }
void SDL_LockAudioDevice(void *dev) { (void)dev; }
void SDL_UnlockAudioDevice(void *dev) { (void)dev; }

unsigned int SDL_GetQueuedAudioSize(void *dev) { (void)dev; return 0; }
