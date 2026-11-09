/* adapter.c - headless host for the recompiled Shadowrun build.
 *
 * Uses the framework's own runtime: glue.c (scheduler, vblank service, dispatch
 * accounting), genesis_vdp/bus/machine (VDP, bus, scanline interleaving),
 * sim_step (one NTSC frame per tick) and the generated game code.
 *
 * Purpose: run the real game loop headlessly and dump frames as BMP so the
 * rendering can be validated against a reference emulator. No SDL involved.
 */
#include "genesis_runtime.h"
#include "video/genesis_bus.h"
#include <windows.h>
#include "glue.h"
#include "audio/ym2612.h"
#include "sim_step.h"
#include "game_spec.h"
#include "game_layout.h"
#include "video/genesis_machine.h"
#include "video/genesis_vdp.h"
#include "video/genesis_bus.h"
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* generated / runtime */
extern const GameRamLayout g_game_layout;

int vdp_save_bmp(const char *path, const uint32_t *fb, int width, int height);
void vdp_render_frame(uint32_t *framebuf);

/* The framework calls back into the game for the entry point and identity. */
extern uint32_t m68k_read32(uint32_t addr);
void recomp_call_addr(uint32_t addr);

static void shadowrun_entry_point(void) {
    uint32_t pc = m68k_read32(4) & 0xFFFFFFu;      /* 68K reset vector */
    recomp_call_addr(pc);                          /* runs the main loop */
}

/* The framework delivers interrupts by calling back into the game: the handler
   must be invoked at the vector the ROM installed. */
static void shadowrun_call_vblank(void) {
    uint32_t handler = m68k_read32(0x78) & 0xFFFFFFu;    /* level-6 autovector */
    if (handler) recomp_call_addr(handler);
}
static void shadowrun_call_hblank(void) {
    uint32_t handler = m68k_read32(0x70) & 0xFFFFFFu;    /* level-4 autovector */
    if (handler) recomp_call_addr(handler);
}

const GameSpec g_game_spec = {
    .display_name       = "Shadowrun",
    .short_name         = "Shadowrun",
    .expected_rom_crc32 = 0xFBB92909u,
    .expected_rom_size  = 2097152u,
    .call_entry_point   = shadowrun_entry_point,
    .call_vblank        = shadowrun_call_vblank,
    .call_hblank        = shadowrun_call_hblank,
};

/* STOP #imm: park the guest until the next interrupt (frame boundary). The
   framework declares this as game-owned, so the adapter provides it. */
void genesis_stop_until_interrupt(uint16_t sr_imm) {
    extern M68KState g_cpu;
    g_cpu.SR = sr_imm;
    glue_wait_vblank_done();
}

/* replay subsystem is not built in the headless runner */
int genesis_replay_begin(const void *sealed) { (void)sealed; return 1; }

/* scanline sink: the framework renders every line into this buffer */
static uint32_t s_fb[320 * 224];
static int s_fb_w = 320;

static unsigned long s_sink_calls = 0;
static unsigned long s_sink_nonblack = 0;

static void scanline_sink(void *ctx, int line, const uint32_t *argb, int width) {
    (void)ctx;
    s_sink_calls++;
    if (argb) for (int i = 0; i < width; i++) if (argb[i] & 0x00FFFFFFu) { s_sink_nonblack++; break; }
    if (line < 0 || line >= 224 || !argb) return;
    s_fb_w = width;
    for (int x = 0; x < width && x < 320; x++) s_fb[line * 320 + x] = argb[x];
}

static int load_rom(const char *path, uint32_t *size) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror("rom"); return 0; }
    size_t n = fread(g_rom, 1, 0x400000, f);
    fclose(f);
    *size = (uint32_t)n;
    printf("ROM: %s (%zu bytes)\n", path, n);
    return 1;
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    const char *rom_path = (argc > 1) ? argv[1] : "Shadowrun (U) [!].bin";
    int frames = (argc > 2) ? atoi(argv[2]) : 300;
    const char *shot = (argc > 3) ? argv[3] : NULL;

    uint32_t rom_size = 0;
    if (!load_rom(rom_path, &rom_size)) return 1;

    extern FILE *g_yield_log_file;
    if (getenv("DSH_YIELDS")) g_yield_log_file = fopen("yields.log", "w");

    machine_init();
    glue_init((const cc_u8l *)g_rom, (cc_u32l)rom_size);

    /* Battery-backed cartridge SRAM: the geometry comes from the ROM header
     * ($1B0 "RA"), and it must be mapped after glue_init has copied the ROM. */
    {
        extern GenesisBus g_machine_bus;
        extern GenesisMachine g_machine;
        extern void gbus_sram_setup(GenesisBus *);
        gbus_sram_setup(&g_machine.bus);
        /* A window beyond the ROM image cannot shadow it, so $A130F1 is
         * meaningless for such carts (Shadowrun never writes it). */
        if (g_machine.bus.sram_present && g_machine.bus.sram_base >= rom_size) {
            extern void gbus_sram_set_always_mapped(GenesisBus *, int);
            gbus_sram_set_always_mapped(&g_machine.bus, 1);
            printf("SRAM: window does not shadow ROM -> always mapped\n");
        }
        printf("SRAM: %s (%u bytes at $%06X)\n",
               g_machine.bus.sram_present ? "present" : "none",
               g_machine.bus.sram_size, g_machine.bus.sram_base);
        const char *sram_path = getenv("DSH_SRAM");
        if (sram_path && g_machine.bus.sram_present) {
            FILE *sf = fopen(sram_path, "rb");
            if (sf) {
                memset(g_machine.bus.sram, 0, g_machine.bus.sram_size);
                size_t got = fread(g_machine.bus.sram, 1, g_machine.bus.sram_size, sf);
                long extra = 0;
                if (got == g_machine.bus.sram_size) {
                    int c;
                    while ((c = fgetc(sf)) != EOF) extra++;
                }
                fclose(sf);
                printf("SRAM: loaded %zu of %u bytes from %s%s\n",
                       got, g_machine.bus.sram_size, sram_path,
                       got < g_machine.bus.sram_size ? " (short file, zero-filled)"
                                                     : (extra ? " (oversized, truncated)" : ""));
            } else {
                printf("SRAM: no save file yet (%s)\n", sram_path);
            }
        }
    }

    GenesisSimInput in;
    memset(&in, 0, sizeof(in));
    {
        int six = getenv("DSH_PAD3") ? 0 : 1;     /* DSH_PAD3=1 -> 3-button pad */
        in.pad_type[0] = in.pad_type[1] = (uint8_t)six;
        printf("pad type: %s\n", six ? "6-button" : "3-button");
    }
    in.human_mask = 0;

    /* Leak probe: baseline after all framework initialisation, report at exit. */
    extern void dsh_leak_report(const char *);
    extern long dsh_leak_live_blocks(void);
    extern long dsh_leak_delta(long);
    long leak_baseline = 0;

    GenesisSimHooks hooks;
    memset(&hooks, 0, sizeof(hooks));
    hooks.sink = scanline_sink;

    /* Audio: let the framework mix into our buffers so we can measure it. */
    static int16_t s_fm[4096 * 2];
    static int16_t s_psg[4096];
    static size_t s_fm_n = 0, s_psg_n = 0;
    GenesisSimAudio aud;
    memset(&aud, 0, sizeof(aud));
    aud.fm = s_fm; aud.fm_cap = 4096; aud.fm_count = &s_fm_n;
    aud.psg = s_psg; aud.psg_cap = 4096; aud.psg_count = &s_psg_n;
    int s_fm_peak = 0, s_psg_peak = 0;
    FILE *s_wav = NULL;
    if (getenv("DSH_WAV")) {
        s_wav = fopen(getenv("DSH_WAV"), "wb");
        {
        extern GenesisMachine g_machine;
        const char *sram_path = getenv("DSH_SRAM");
        if (sram_path && g_machine.bus.sram_present) {
            unsigned sum = 0;
            for (uint32_t k = 0; k < g_machine.bus.sram_size; k++)
                sum = (sum * 31u) + g_machine.bus.sram[k];
            char tmp_path[1024];
            snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", sram_path);
            FILE *sf = fopen(tmp_path, "wb");
            if (sf) {
                size_t wrote = fwrite(g_machine.bus.sram, 1, g_machine.bus.sram_size, sf);
                int flush_ok = (fflush(sf) == 0);
                fclose(sf);
                /* Atomic replace: a crash mid-write leaves the previous .srm whole. */
                if (wrote == g_machine.bus.sram_size && flush_ok
                        && MoveFileExA(tmp_path, sram_path, MOVEFILE_REPLACE_EXISTING)) {
                    printf("SRAM: saved %u bytes (checksum %08X) to %s\n",
                           g_machine.bus.sram_size, sum, sram_path);
                } else {
                    printf("SRAM: WRITE FAILED for %s (previous file kept)\n", sram_path);
                    DeleteFileA(tmp_path);
                }
            }
        }
    }
    if (s_wav) {
            unsigned char hdr[44] = {0};
            fwrite(hdr, 1, 44, s_wav);   /* patched at close */
        }
    }
    unsigned long s_sound_frames = 0, s_frames_with_audio = 0;
unsigned long s_wav_out_frames = 0;
unsigned s_wav_out_rate = 0;

    int dsh_dbg_spritelist = getenv("DSH_SPRITELIST") != NULL;
    int last_count = -1;
    int dsh_padprobe = getenv("DSH_PADPROBE") != NULL;
    unsigned last22 = 0xFFFFFFFFu, last26 = 0xFFFFFFFFu;
    int dsh_kick = getenv("DSH_KICK") != NULL;
    (void)dsh_kick;

    if (getenv("DSH_LEAK")) { dsh_leak_report("baseline"); leak_baseline = dsh_leak_live_blocks(); }

    for (int i = 0; i < frames; i++) {
    in.pad[0] = 0;   /* release everything each frame; scripted presses set bits */
    /* Scripted input: DSH_PRESSES="frame:BTN,frame:BTN,..." where BTN is
       S(tart), A, B, C, U(p), D(own), L(eft), R(ight). Each press is held for
       6 frames so the game sees a fresh-press edge. */
    {
        static int parsed = 0;
        static int parsed_hold = 0;
        static int n_presses = 0;
        static int press_frame[64];
        static unsigned press_mask[64];
        if (!parsed) {
            parsed = 1;
            const char *s = getenv("DSH_PRESSES");
            if (s && *s) {
                char buf[512];
                snprintf(buf, sizeof(buf), "%s", s);
                char *save = NULL;
                for (char *tok = strtok_r(buf, ",", &save); tok && n_presses < 64;
                     tok = strtok_r(NULL, ",", &save)) {
                    char *colon = strchr(tok, ':');
                    if (!colon) continue;
                    *colon = 0;
                    press_frame[n_presses] = atoi(tok);
                    unsigned mask = 0;
                    for (const char *c = colon + 1; *c; c++) {
                        switch (*c) {
                        case 'S': case 's': mask |= 0x80; break;
                        case 'A': case 'a': mask |= 0x40; break;
                        case 'B': case 'b': mask |= 0x10; break;
                        case 'C': case 'c': mask |= 0x20; break;
                        case 'U': case 'u': mask |= 0x01; break;
                        case 'D': case 'd': mask |= 0x02; break;
                        case 'L': case 'l': mask |= 0x04; break;
                        case 'R': case 'r': mask |= 0x08; break;
                        default: break;
                        }
                    }
                    press_mask[n_presses++] = mask;
                }
            }
            /* legacy single-press env vars */
            const char *f1 = getenv("DSH_PRESS_START");
            const char *f2 = getenv("DSH_PRESS_START2");
            const char *fa = getenv("DSH_PRESS_A2");
            if (f1) { press_frame[n_presses] = atoi(f1); press_mask[n_presses++] = 0x80; }
            if (f2) { press_frame[n_presses] = atoi(f2); press_mask[n_presses++] = 0x80; }
            if (fa) { press_frame[n_presses] = atoi(fa); press_mask[n_presses++] = 0x40; }
        }
        static int hold = 6;
        if (!parsed_hold) { parsed_hold = 1;
            hold = getenv("DSH_HOLD") ? atoi(getenv("DSH_HOLD")) : 6;
            if (hold < 1) hold = 1; }
        for (int k = 0; k < n_presses; k++) {
            if (i >= press_frame[k] && i < press_frame[k] + hold)
                in.pad[0] |= (uint16_t)press_mask[k];
        }
    }
        genesis_sim_step(&in, &aud, &hooks);
        if (s_fm_n) {
            /* DC blocker: the YM2612 DAC sits at a constant bias (~480 LSB idle),
             * which would be a speaker offset and wastes headroom. One-pole
             * high-pass at ~20 Hz; DSH_NO_DC=1 disables it for raw comparisons. */
            static double dc_x1[2], dc_y1[2];
            static int dc_ready = -1;
            if (dc_ready < 0) dc_ready = getenv("DSH_NO_DC") ? 0 : 1;
            if (dc_ready) {
                const double r = 0.99764;   /* 1 - 2*pi*20/53267 */
                for (size_t f = 0; f < s_fm_n; f++) {
                    for (int c = 0; c < 2; c++) {
                        double x = (double)s_fm[f * 2 + c];
                        double y = x - dc_x1[c] + r * dc_y1[c];
                        dc_x1[c] = x; dc_y1[c] = y;
                        s_fm[f * 2 + c] = (int16_t)(y > 32767.0 ? 32767
                                                  : y < -32768.0 ? -32768
                                                  : (y >= 0.0 ? y + 0.5 : y - 0.5));
                    }
                }
            }
            s_frames_with_audio++;
            for (size_t k = 0; k < s_fm_n * 2; k++) {
                int v = s_fm[k] < 0 ? -s_fm[k] : s_fm[k];
                if (v > s_fm_peak) s_fm_peak = v;
            }
        }
        for (size_t k = 0; k < s_psg_n; k++) {
            int v = s_psg[k] < 0 ? -s_psg[k] : s_psg[k];
            if (v > s_psg_peak) s_psg_peak = v;
        }
        if (s_fm_peak || s_psg_peak) s_sound_frames++;
        if (s_wav && s_fm_n) {
            /* Optional resample to a device-friendly rate (DSH_WAV_RATE=48000).
             * Streaming linear interpolation; the native rate is 53267 Hz. */
            static unsigned out_rate = 0;
            static int rs_init = -1;
            if (rs_init < 0) {
                rs_init = 1;
                const char *r = getenv("DSH_WAV_RATE");
                out_rate = r ? (unsigned)atoi(r) : 0;
                s_wav_out_rate = out_rate;
            }
            if (out_rate) {
                static double pos = 0.0;
                static int16_t prev[2];
                static int have = 0;
                const double ratio = 53267.0 / (double)out_rate;
                for (size_t f = 0; f < s_fm_n; f++) {
                    int16_t cur[2] = { s_fm[f * 2], s_fm[f * 2 + 1] };
                    if (!have) { prev[0] = cur[0]; prev[1] = cur[1]; have = 1; continue; }
                    while (pos < 1.0) {
                        int16_t o[2];
                        for (int c = 0; c < 2; c++) {
                            double v = (double)prev[c] + ((double)cur[c] - (double)prev[c]) * pos;
                            o[c] = (int16_t)(v >= 0.0 ? v + 0.5 : v - 0.5);
                        }
                        fwrite(o, sizeof(int16_t), 2, s_wav);
                        s_wav_out_frames++;
                        pos += ratio;
                    }
                    pos -= 1.0;
                    prev[0] = cur[0]; prev[1] = cur[1];
                }
            } else {
                fwrite(s_fm, sizeof(int16_t), s_fm_n * 2, s_wav);
                s_wav_out_frames += s_fm_n;
            }
        }
        if (dsh_dbg_spritelist) {
            unsigned cnt = ((unsigned)g_ram[0xDF2A] << 8) | g_ram[0xDF2B];
            unsigned base = ((unsigned)g_ram[0xDF2C] << 24) | ((unsigned)g_ram[0xDF2D] << 16) |
                            ((unsigned)g_ram[0xDF2E] << 8) | g_ram[0xDF2F];
            if ((int)cnt != last_count) {
                printf("  [spr] frame %4d count=%u base=%08X\n", i, cnt, base);
                last_count = (int)cnt;
            }
        }
        if (getenv("DSH_BUSPAD") && (i % 120) == 0) {
            extern uint8_t m68k_read8(uint32_t);
            extern GenesisMachine g_machine;
            printf("  [bus] frame %d pad0=%04X type=%u A10003=%02X A10005=%02X\n",
                   i, g_machine.bus.pad[0], g_machine.bus.pad_type[0],
                   m68k_read8(0xA10003u), m68k_read8(0xA10005u));
        }
        if (getenv("DSH_PADPROBE") && atoi(getenv("DSH_PADPROBE")) >= 2
                && i >= 8900 && i <= 9060) {
            unsigned p22 = ((unsigned)g_ram[0xDD22] << 8) | g_ram[0xDD23];
            unsigned p20 = ((unsigned)g_ram[0xDD20] << 8) | g_ram[0xDD21];
            printf("  [pad+] frame %4d dd20=%04X dd22=%04X pad=%04X\n", i, p20, p22, in.pad[0]);
        }
        if (getenv("DSH_SRAMTRACE") && (((i % 200) == 0) || (i >= 22750 && i <= 23200))) {
            extern GenesisMachine g_machine;
            unsigned sum = 0, nz = 0;
            for (uint32_t k = 0; k < g_machine.bus.sram_size; k++) {
                unsigned char v = g_machine.bus.sram[k];
                sum = (sum * 31u) + v;
                if (v) nz++;
            }
            extern unsigned g_sram_reads, g_sram_writes;
            printf("  [sram] frame %5d en=%d nz=%u sum=%08X r=%u w=%u\n",
                   i, g_machine.bus.sram_enabled, nz, sum, g_sram_reads, g_sram_writes);
        }
        if (getenv("DSH_SEL")) {
            static int last_sel = -99;
            int sel = g_ram[0xF0DC];
            if (sel != last_sel) {
                printf("  [sel] frame %4d fff0dc=%02X d0=%02X d1=%02X b9=%02X\n",
                       i, sel, g_ram[0xF0D0], g_ram[0xF0D1], g_ram[0xF0B9]);
                last_sel = sel;
            }
        }
        if (dsh_padprobe) {
            unsigned p22 = ((unsigned)g_ram[0xDD22] << 8) | g_ram[0xDD23];
            unsigned p24 = ((unsigned)g_ram[0xDD24] << 8) | g_ram[0xDD25];
            unsigned p26 = ((unsigned)g_ram[0xDD26] << 8) | g_ram[0xDD27];
            if (p22 != last22 || p26 != last26) {
                printf("  [pad] frame %4d dd22=%04X dd24=%04X dd26=%04X\n", i, p22, p24, p26);
                last22 = p22; last26 = p26;
            }
        }
        if (getenv("DSH_D7") && (i % 20) == 0) {
            extern M68KState g_cpu;
            printf("  [d7] frame %4d d7=%08X a7=%08X\n", i, g_cpu.D[7], g_cpu.A[7]);
        }
        if ((i % 60) == 0) {
            extern M68KState g_cpu;
            unsigned vbl = ((unsigned)g_ram[0xF9EC] << 24) | ((unsigned)g_ram[0xF9ED] << 16) |
                           ((unsigned)g_ram[0xF9EE] << 8) | g_ram[0xF9EF];
            printf("  frame %d: insns=%llu sr=%04X vblcount=%u\n", i,
                   (unsigned long long)g_native_insn_count, g_cpu.SR, vbl);
        }
    }

    if (getenv("DSH_NODE")) {
        extern M68KState g_cpu;
        uint32_t a0 = g_cpu.A[0] & 0xFFFF;
        printf("node a0=%08X:", g_cpu.A[0]);
        for (int k = 0; k < 6; k++) {
            uint32_t v = ((uint32_t)g_ram[(a0 + k*4) & 0xFFFF] << 24)
                       | ((uint32_t)g_ram[(a0 + k*4 + 1) & 0xFFFF] << 16)
                       | ((uint32_t)g_ram[(a0 + k*4 + 2) & 0xFFFF] << 8)
                       | (uint32_t)g_ram[(a0 + k*4 + 3) & 0xFFFF];
            printf(" [%d]=%08X", k, v);
        }
        printf("\n  fff0d2=%02X fff0d3=%02X\n", g_ram[0xF0D2], g_ram[0xF0D3]);
    }
    if (getenv("DSH_PADTEST")) {
        extern GenesisMachine g_machine;
        extern uint8_t m68k_read8(uint32_t);
        struct { const char *name; unsigned bit; } btns[] = {
            {"up",0x01},{"down",0x02},{"left",0x04},{"right",0x08},
            {"B",0x10},{"C",0x20},{"A",0x40},{"start",0x80}
        };
        for (int b = 0; b < 8; b++) {
            g_machine.bus.pad[0] = (uint16_t)btns[b].bit;
            g_machine.bus.io_data[0] = 0x00;                 /* TH = 0 */
            unsigned th0 = m68k_read8(0xA10003u);
            g_machine.bus.pad_th_count[0] = 0;
            g_machine.bus.io_data[0] = 0x40;                 /* TH = 1 */
            unsigned th1 = m68k_read8(0xA10003u);
            printf("  [padtest] %-5s TH0=%02X TH1=%02X\n", btns[b].name, th0, th1);
        }
        g_machine.bus.pad[0] = 0;
    }
    if (getenv("DSH_REPORT")) {
        extern void crash_report_dump(FILE *, const char *, const M68KState *,
                                      uint32_t, int, uint64_t);
        extern M68KState g_cpu;
        crash_report_dump(stderr, "manual state dump", &g_cpu, 0, 0, g_frame_count);
    }
    {
        extern GenesisMachine g_machine;
        const char *sram_path = getenv("DSH_SRAM");
        if (sram_path && g_machine.bus.sram_present) {
            unsigned sum = 0;
            for (uint32_t k = 0; k < g_machine.bus.sram_size; k++)
                sum = (sum * 31u) + g_machine.bus.sram[k];
            char tmp_path[1024];
            snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", sram_path);
            FILE *sf = fopen(tmp_path, "wb");
            if (sf) {
                size_t wrote = fwrite(g_machine.bus.sram, 1, g_machine.bus.sram_size, sf);
                int flush_ok = (fflush(sf) == 0);
                fclose(sf);
                /* Atomic replace: a crash mid-write leaves the previous .srm whole. */
                if (wrote == g_machine.bus.sram_size && flush_ok
                        && MoveFileExA(tmp_path, sram_path, MOVEFILE_REPLACE_EXISTING)) {
                    printf("SRAM: saved %u bytes (checksum %08X) to %s\n",
                           g_machine.bus.sram_size, sum, sram_path);
                } else {
                    printf("SRAM: WRITE FAILED for %s (previous file kept)\n", sram_path);
                    DeleteFileA(tmp_path);
                }
            }
        }
    }
    if (s_wav) {
        long bytes = ftell(s_wav) - 44;
        unsigned char h[44];
        unsigned int rate = s_wav_out_rate ? s_wav_out_rate : ym2612_sample_rate();
        if (!rate) rate = 44100;
        unsigned int data = (unsigned int)bytes;
        unsigned int file = data + 36;
        h[0]='R'; h[1]='I'; h[2]='F'; h[3]='F';
        h[4]=file&0xFF; h[5]=(file>>8)&0xFF; h[6]=(file>>16)&0xFF; h[7]=(file>>24)&0xFF;
        h[8]='W'; h[9]='A'; h[10]='V'; h[11]='E'; h[12]='f'; h[13]='m'; h[14]='t'; h[15]=' ';
        h[16]=16; h[17]=0; h[18]=0; h[19]=0; h[20]=1; h[21]=0; h[22]=2; h[23]=0;
        h[24]=rate&0xFF; h[25]=(rate>>8)&0xFF; h[26]=(rate>>16)&0xFF; h[27]=(rate>>24)&0xFF;
        unsigned int br = rate * 4;
        h[28]=br&0xFF; h[29]=(br>>8)&0xFF; h[30]=(br>>16)&0xFF; h[31]=(br>>24)&0xFF;
        h[32]=4; h[33]=0; h[34]=16; h[35]=0; h[36]='d'; h[37]='a'; h[38]='t'; h[39]='a';
        h[40]=data&0xFF; h[41]=(data>>8)&0xFF; h[42]=(data>>16)&0xFF; h[43]=(data>>24)&0xFF;
        fseek(s_wav, 0, SEEK_SET);
        fwrite(h, 1, 44, s_wav);
        fclose(s_wav);
        printf("wav written: %u bytes of PCM at %u Hz\n", data, rate);
    }
    if (getenv("DSH_LEAK")) {
        dsh_leak_report("exit");
        printf("leak: live block delta = %ld\n", dsh_leak_delta(leak_baseline));
    }
    printf("\naudio: frames_with_samples=%lu fm_peak=%d psg_peak=%d\n",
           s_frames_with_audio, s_fm_peak, s_psg_peak);
    printf("\nafter %d frames: insns=%llu\n", frames, (unsigned long long)g_native_insn_count);
    printf("sink calls=%lu non-black lines=%lu\n", s_sink_calls, s_sink_nonblack);
    {
        extern GenesisMachine g_machine;
        printf("Z80: pc=%04X cyc=%lu ram:", g_machine.z80.pc, g_machine.z80.cyc);
        for (int i = 0; i < 16; i++) printf(" %02X", g_machine.bus.z80_ram[i]);
        printf("\n");
        printf("68k RAM @0xFFF9E0:");
        for (int i = 0; i < 16; i++) printf(" %02X", g_ram[0xF9E0 + i]);
        printf("\n");
        printf("VDP regs:");
        for (int i = 0; i < 24; i++) printf(" %02X", g_machine.vdp.reg[i]);
        printf("\nCRAM[0..7]:");
        for (int i = 0; i < 8; i++) printf(" %03X", g_machine.vdp.cram[i]);
        printf("\nVSRAM[0..1]: %03X %03X\n", g_machine.vdp.vsram[0], g_machine.vdp.vsram[1]);
    }

    if (shot) {
        if (vdp_save_bmp(shot, s_fb, s_fb_w, 224))
            printf("frame dumped to %s\n", shot);
    }
    return 0;
}
