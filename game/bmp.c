/* bmp.c - 24-bit BMP writer for frame dumps (no dependencies). */
#include <stdio.h>
#include <stdint.h>

int vdp_save_bmp(const char *path, const uint32_t *fb, int width, int height) {
    FILE *f = fopen(path, "wb");
    if (!f) return 0;
    int row_bytes = width * 3;
    int pad = (4 - (row_bytes % 4)) % 4;
    int data_size = (row_bytes + pad) * height;
    int file_size = 54 + data_size;

    unsigned char hdr[54] = { 'B','M' };
    hdr[2]  = (unsigned char)(file_size);      hdr[3]  = (unsigned char)(file_size >> 8);
    hdr[4]  = (unsigned char)(file_size >> 16); hdr[5]  = (unsigned char)(file_size >> 24);
    hdr[10] = 54;
    hdr[14] = 40;
    hdr[18] = (unsigned char)(width);       hdr[19] = (unsigned char)(width >> 8);
    hdr[20] = (unsigned char)(width >> 16); hdr[21] = (unsigned char)(width >> 24);
    hdr[22] = (unsigned char)(height);       hdr[23] = (unsigned char)(height >> 8);
    hdr[24] = (unsigned char)(height >> 16); hdr[25] = (unsigned char)(height >> 24);
    hdr[26] = 1; hdr[28] = 24;
    hdr[34] = (unsigned char)(data_size);       hdr[35] = (unsigned char)(data_size >> 8);
    hdr[36] = (unsigned char)(data_size >> 16); hdr[37] = (unsigned char)(data_size >> 24);
    fwrite(hdr, 1, 54, f);

    unsigned char padbuf[3] = { 0, 0, 0 };
    for (int y = height - 1; y >= 0; y--) {
        for (int x = 0; x < width; x++) {
            uint32_t p = fb[y * width + x];
            unsigned char bgr[3] = { (unsigned char)(p), (unsigned char)(p >> 8), (unsigned char)(p >> 16) };
            fwrite(bgr, 1, 3, f);
        }
        if (pad) fwrite(padbuf, 1, (size_t)pad, f);
    }
    fclose(f);
    return 1;
}
