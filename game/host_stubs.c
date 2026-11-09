/* host_stubs.c - headless replacements for the runner's host-thread helpers. */
#include <stddef.h>

const char *exe_relative(const char *name) { return name; }

typedef struct GenesisWorker GenesisWorker;
GenesisWorker *genesis_worker_create(void) { return (GenesisWorker *)0; }
int  genesis_worker_start(GenesisWorker *w, void (*fn)(void *), void *arg) {
    (void)w; (void)fn; (void)arg; return 0;
}
void genesis_worker_join(GenesisWorker *w) { (void)w; }
void genesis_worker_destroy(GenesisWorker *w) { (void)w; }

/* --- headless input: nothing is pressed, nothing is connected ------------- */
unsigned short gamepad_player_mask(int player) { (void)player; return 0; }
int gamepad_player_connected(int player) { (void)player; return 0; }
const unsigned char *SDL_GetKeyboardState(int *numkeys) {
    static const unsigned char none[512];
    if (numkeys) *numkeys = 512;
    return none;
}
void SDL_Delay(unsigned int ms) { (void)ms; }



/* --- ROM accessors expected by the decoder core ---------------------------- */
extern unsigned char g_rom[0x400000];
unsigned int rom_read16(unsigned int a) {
    return ((unsigned int)g_rom[a & 0x3FFFFF] << 8) | g_rom[(a + 1) & 0x3FFFFF];
}
unsigned int rom_read32(unsigned int a) {
    return ((unsigned int)rom_read16(a) << 16) | rom_read16(a + 2);
}

/* --- misc framework helpers not built in the headless runner ------------- */
int genesis_worker_busy(void) { return 0; }
int genesis_replay_end(void) { return 1; }
