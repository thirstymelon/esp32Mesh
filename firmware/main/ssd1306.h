#ifndef SSD1306_H
#define SSD1306_H

#include <stdint.h>
#include <stdbool.h>

#define SSD1306_WIDTH  128
#define SSD1306_HEIGHT 64

#ifdef __cplusplus
extern "C" {
#endif

void ssd1306_init(int sda_pin, int scl_pin);
void ssd1306_clear(void);
void ssd1306_draw_pixel(int x, int y, int color);
void ssd1306_draw_char(int x, int y, char c, int color);
void ssd1306_draw_string(int x, int y, const char* str, int color);
void ssd1306_draw_line(int x0, int y0, int x1, int y1, int color);
void ssd1306_draw_box(int x, int y, int w, int h, int color, bool fill);
void ssd1306_update(void);

#ifdef __cplusplus
}
#endif

#endif // SSD1306_H
