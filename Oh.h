/*
 * Oh.h - Header file for ANSI to SVG converter
 * C implementation mirroring Oh.sh functionality
 */

#ifndef OH_H
#define OH_H

#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <time.h>
#include <jansson.h>

// MetaData
#define SCRIPT_NAME "Oh"
#define SCRIPT_VERSION "1.007"

// Configuration constants
#define MAX_LINE_LENGTH 4096
#define MAX_LINES 10000
#define MAX_SEGMENTS 1000
#define MAX_PATH_LENGTH 512
#define MAX_HASH_LENGTH 64
#define MAX_COLOR_LENGTH 16
#define MAX_FONT_NAME_LENGTH 64
#define MAX_URL_LENGTH 256
#define MAX_CACHE_KEY_LENGTH 128
#define DEFAULT_FONT_SIZE 14
#define DEFAULT_WIDTH 80
#define DEFAULT_HEIGHT 0
#define DEFAULT_TAB_SIZE 8
#define DEFAULT_PADDING 20
#define DEFAULT_FONT_WEIGHT 400
#define BG_COLOR "#1e1e1e"
#define TEXT_COLOR "#ffffff"

// Global variables (declared as extern)
extern double script_start_time;
extern int debug_mode;
extern char cache_dir[MAX_PATH_LENGTH];
extern char svg_cache_dir[MAX_PATH_LENGTH];
extern char incremental_cache_file[MAX_PATH_LENGTH];
extern int cache_stats_segment_hits;
extern int cache_stats_segment_misses;
extern int cache_stats_svg_hits;
extern int cache_stats_svg_misses;
extern char input_lines[MAX_LINES][MAX_LINE_LENGTH];
extern char hash_cache[MAX_LINES][MAX_HASH_LENGTH];
extern int input_line_count;
extern char global_input_hash[MAX_HASH_LENGTH];
extern char previous_input_hash[MAX_HASH_LENGTH];

// Configuration structure
typedef struct {
    char input_file[MAX_PATH_LENGTH];
    char output_file[MAX_PATH_LENGTH];
    char font_family[MAX_FONT_NAME_LENGTH];
    int font_size;
    double font_width;
    double font_height;
    int font_weight;
    int width;
    int height;
    int wrap;
    int tab_size;
    int font_width_explicit;
    int font_height_explicit;
} Config;

// Text segment for ANSI parsing
typedef struct {
    char text[MAX_LINE_LENGTH];
    char fg_color[MAX_COLOR_LENGTH];
    char bg_color[MAX_COLOR_LENGTH];
    int bold;
    int visible_pos;
} TextSegment;

// Line data
typedef struct {
    TextSegment segments[MAX_SEGMENTS];
    int segment_count;
    int visible_length;
} LineData;

// Font character width ratios structure
typedef struct {
    char name[MAX_FONT_NAME_LENGTH];
    int ratio;
} FontRatio;

// Google Fonts structure
typedef struct {
    char name[MAX_FONT_NAME_LENGTH];
    char url[MAX_URL_LENGTH];
} GoogleFont;

// ANSI color mappings structure
typedef struct {
    int code;
    char color[MAX_COLOR_LENGTH];
} AnsiColor;

// External data arrays (declared in Oh.c)
extern FontRatio font_ratios[];
extern GoogleFont google_fonts[];
extern AnsiColor ansi_colors[];

// Function declarations
double get_current_time(void);
void log_output(const char *message);
void progress_output(const char *message);
void show_version(void);
void show_help(void);
int parse_arguments(int argc, char **argv, Config *config);
void setup_cache_directories(void);
int get_font_ratio(const char *font_family);
void calculate_font_metrics(Config *config);
const char* get_google_font_url(const char *font_family);
const char* get_ansi_color(int code);
void xml_escape(const char *input, char *output, size_t output_size);
void xml_escape_url(const char *input, char *output, size_t output_size);
unsigned int generate_hash(const char *input);
void generate_config_hash(const Config *config, char *hash_out);
void get_cache_key(const char *line_hash, const char *config_hash, char *cache_key);
int save_line_cache(const char *cache_key, const LineData *line_data);
int load_line_cache(const char *cache_key, LineData *line_data);
void get_svg_fragment_cache_key(const char *line_hash, const char *config_hash, int line_number, char *cache_key);
int save_svg_fragment_cache(const char *cache_key, const char *svg_fragment);
char* load_svg_fragment_cache(const char *cache_key);
void generate_global_input_hash(void);
int load_incremental_cache(void);
int save_incremental_cache(const char *config_hash);
void expand_tabs(const char *input, char *output, int tab_size);
int utf8_strlen(const char *str);
int parse_ansi_line(const char *line, const char *line_hash, const char *config_hash, LineData *line_data);
int read_input(Config *config);
void build_font_css(const char *font, char *css_output, size_t css_size);
int process_lines_single_pass(Config *config, char **svg_output);
int output_svg(Config *config);

#endif // OH_H
