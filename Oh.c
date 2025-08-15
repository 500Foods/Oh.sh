/*
 * Oh.c - Convert ANSI terminal output to GitHub-compatible SVG
 * C implementation mirroring Oh.sh functionality
 * 
 * CHANGELOG
 * 1.000 - Initial C implementation matching Oh.sh v1.007 functionality
 */

#include "Oh.h"

// Global variable definitions
double script_start_time;
int debug_mode = 0;
char cache_dir[MAX_PATH_LENGTH];
char svg_cache_dir[MAX_PATH_LENGTH];
char incremental_cache_file[MAX_PATH_LENGTH];
int cache_stats_segment_hits = 0;
int cache_stats_segment_misses = 0;
int cache_stats_svg_hits = 0;
int cache_stats_svg_misses = 0;
char input_lines[MAX_LINES][MAX_LINE_LENGTH];
char hash_cache[MAX_LINES][MAX_HASH_LENGTH];
int input_line_count = 0;
char global_input_hash[MAX_HASH_LENGTH];
char previous_input_hash[MAX_HASH_LENGTH];

// Font character width ratios (scaled by 100 for integer arithmetic)
FontRatio font_ratios[] = {
    {"Consolas", 60},
    {"Monaco", 60},
    {"Courier New", 60},
    {"Inconsolata", 60},
    {"JetBrains Mono", 55},
    {"Source Code Pro", 55},
    {"Fira Code", 58},
    {"Roboto Mono", 60},
    {"Ubuntu Mono", 50},
    {"Menlo", 60},
    {"", 0} // Terminator
};

// Google Fonts
GoogleFont google_fonts[] = {
    {"Inconsolata", "https://fonts.googleapis.com/css2?family=Inconsolata:wght@400;700&display=swap"},
    {"JetBrains Mono", "https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap"},
    {"Source Code Pro", "https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap"},
    {"Fira Code", "https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;700&display=swap"},
    {"Roboto Mono", "https://fonts.googleapis.com/css2?family=Roboto+Mono:wght@400;700&display=swap"},
    {"", ""} // Terminator
};

// ANSI color mappings
AnsiColor ansi_colors[] = {
    {30, "#000000"},   // Black
    {31, "#cd3131"},   // Red
    {32, "#0dbc79"},   // Green
    {33, "#e5e510"},   // Yellow
    {34, "#2472c8"},   // Blue
    {35, "#bc3fbc"},   // Magenta
    {36, "#11a8cd"},   // Cyan
    {37, "#e5e5e5"},   // White
    {90, "#666666"},   // Bright Black (Gray)
    {91, "#f14c4c"},   // Bright Red
    {92, "#23d18b"},   // Bright Green
    {93, "#f5f543"},   // Bright Yellow
    {94, "#3b8eea"},   // Bright Blue
    {95, "#d670d6"},   // Bright Magenta
    {96, "#29b8db"},   // Bright Cyan
    {97, "#e5e5e5"},   // Bright White
    {0, ""} // Terminator
};

// Get current time in seconds with microsecond precision
double get_current_time(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

// Log output with timestamp (mirrors bash version)
void log_output(const char *message) {
    if (debug_mode) {
        double current_time = get_current_time();
        double elapsed = current_time - script_start_time;
        fprintf(stderr, "%07.3f - %s\n", elapsed, message);
    }
}

// Progress output with timestamp (always shown, mirrors bash version)
void progress_output(const char *message) {
    double current_time = get_current_time();
    double elapsed = current_time - script_start_time;
    fprintf(stderr, "%07.3f - %s\n", elapsed, message);
}

// Show version information
void show_version(void) {
    fprintf(stderr, "%s   - v%s - Convert ANSI terminal output to GitHub-compatible SVG\n", 
            SCRIPT_NAME, SCRIPT_VERSION);
}

// Show help information
void show_help(void) {
    show_version();
    fprintf(stderr, "\nUSAGE:\n");
    fprintf(stderr, "    command | %s [OPTIONS] > output.svg\n", SCRIPT_NAME);
    fprintf(stderr, "    %s [OPTIONS] -i input.txt -o output.svg\n\n", SCRIPT_NAME);
    fprintf(stderr, "OPTIONS:\n");
    fprintf(stderr, "    -h, --help              Show this help\n");
    fprintf(stderr, "    -i, --input FILE        Input file (default: stdin)\n");
    fprintf(stderr, "    -o, --output FILE       Output file (default: stdout)\n");
    fprintf(stderr, "    --font FAMILY           Font family (default: Consolas)\n");
    fprintf(stderr, "    --font-size SIZE        Font size in pixels (default: 14)\n");
    fprintf(stderr, "    --font-width PX         Character width in pixels (default: 0.6 * font-size)\n");
    fprintf(stderr, "    --font-height PX        Line height in pixels (default: 1.2 * font-size)\n");
    fprintf(stderr, "    --font-weight WEIGHT    Font weight (default: 400)\n");
    fprintf(stderr, "    --width CHARS           Grid width in characters (default: 80)\n");
    fprintf(stderr, "    --height CHARS          Grid height in lines (default: input line count)\n");
    fprintf(stderr, "    --wrap                  Wrap lines at width (default: false)\n");
    fprintf(stderr, "    --tab-size SIZE         Tab stop size (default: 8)\n");
    fprintf(stderr, "    --debug                 Enable debug output\n");
    fprintf(stderr, "    --version               Show version information\n");
    fprintf(stderr, "\nSUPPORTED FONTS:\n");
    fprintf(stderr, "    Consolas, Monaco, Courier New (system fonts)\n");
    fprintf(stderr, "    Inconsolata, JetBrains Mono, Source Code Pro,\n");
    fprintf(stderr, "    Fira Code, Roboto Mono (Google Fonts - embedded automatically)\n");
    fprintf(stderr, "    Font metric defaults are editable in the script.\n");
    fprintf(stderr, "\nEXAMPLES:\n");
    fprintf(stderr, "    ls --color=always -l | %s > listing.svg\n", SCRIPT_NAME);
    fprintf(stderr, "    git diff --color | %s --font \"JetBrains Mono\" --font-size 16 -o diff.svg\n", SCRIPT_NAME);
    fprintf(stderr, "    %s --font Inconsolata --width 60 --wrap -i terminal-output.txt -o styled.svg\n", SCRIPT_NAME);
}

// Parse command line arguments
int parse_arguments(int argc, char **argv, Config *config) {
    // Initialize defaults
    strcpy(config->input_file, "");
    strcpy(config->output_file, "");
    strcpy(config->font_family, "Consolas");
    config->font_size = DEFAULT_FONT_SIZE;
    config->font_width = 0.0; // Will be calculated
    config->font_height = 0.0; // Will be calculated
    config->font_weight = DEFAULT_FONT_WEIGHT;
    config->width = DEFAULT_WIDTH;
    config->height = DEFAULT_HEIGHT;
    config->wrap = 0;
    config->tab_size = DEFAULT_TAB_SIZE;
    config->font_width_explicit = 0;
    config->font_height_explicit = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            show_help();
            exit(0);
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--version") == 0) {
            show_version();
            exit(0);
        } else if (strcmp(argv[i], "-i") == 0 || strcmp(argv[i], "--input") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --input requires a filename\n");
                return -1;
            }
            strcpy(config->input_file, argv[++i]);
        } else if (strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "--output") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --output requires a filename\n");
                return -1;
            }
            strcpy(config->output_file, argv[++i]);
        } else if (strcmp(argv[i], "--font") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --font requires a font family name\n");
                return -1;
            }
            strcpy(config->font_family, argv[++i]);
        } else if (strcmp(argv[i], "--font-size") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --font-size requires a number\n");
                return -1;
            }
            int size = atoi(argv[++i]);
            if (size < 8 || size > 72) {
                fprintf(stderr, "Error: --font-size must be between 8 and 72\n");
                return -1;
            }
            config->font_size = size;
        } else if (strcmp(argv[i], "--font-width") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --font-width requires a number\n");
                return -1;
            }
            double width = atof(argv[++i]);
            if (width < 1.0) {
                fprintf(stderr, "Error: --font-width must be >= 1\n");
                return -1;
            }
            config->font_width = width;
            config->font_width_explicit = 1;
        } else if (strcmp(argv[i], "--font-height") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --font-height requires a number\n");
                return -1;
            }
            double height = atof(argv[++i]);
            if (height < 1.0) {
                fprintf(stderr, "Error: --font-height must be >= 1\n");
                return -1;
            }
            config->font_height = height;
            config->font_height_explicit = 1;
        } else if (strcmp(argv[i], "--font-weight") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --font-weight requires a number\n");
                return -1;
            }
            int weight = atoi(argv[++i]);
            if (weight < 100 || weight > 900) {
                fprintf(stderr, "Error: --font-weight must be between 100 and 900\n");
                return -1;
            }
            config->font_weight = weight;
        } else if (strcmp(argv[i], "--width") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --width requires a number\n");
                return -1;
            }
            int width = atoi(argv[++i]);
            if (width < 1) {
                fprintf(stderr, "Error: --width must be >= 1\n");
                return -1;
            }
            config->width = width;
        } else if (strcmp(argv[i], "--height") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --height requires a number\n");
                return -1;
            }
            int height = atoi(argv[++i]);
            if (height < 1) {
                fprintf(stderr, "Error: --height must be >= 1\n");
                return -1;
            }
            config->height = height;
        } else if (strcmp(argv[i], "--wrap") == 0) {
            config->wrap = 1;
        } else if (strcmp(argv[i], "--tab-size") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Error: --tab-size requires a number\n");
                return -1;
            }
            int tab_size = atoi(argv[++i]);
            if (tab_size < 1 || tab_size > 16) {
                fprintf(stderr, "Error: --tab-size must be between 1 and 16\n");
                return -1;
            }
            config->tab_size = tab_size;
        } else if (strcmp(argv[i], "--debug") == 0) {
            debug_mode = 1;
        } else {
            fprintf(stderr, "Error: Unknown option '%s'\n", argv[i]);
            fprintf(stderr, "Use -h or --help for usage information\n");
            return -1;
        }
    }

    return 0;
}

// Setup cache directories
void setup_cache_directories(void) {
    const char *home = getenv("HOME");
    if (!home) {
        fprintf(stderr, "Error: HOME environment variable not set\n");
        exit(1);
    }
    
    snprintf(cache_dir, sizeof(cache_dir), "%s/.cache/Oh", home);
    snprintf(svg_cache_dir, sizeof(svg_cache_dir), "%s/.cache/Oh/svg", home);
    snprintf(incremental_cache_file, sizeof(incremental_cache_file), "%s/.cache/Oh/incremental.json", home);
    
    // Create directories
    mkdir(cache_dir, 0755);
    mkdir(svg_cache_dir, 0755);
}

// Get font character width ratio
int get_font_ratio(const char *font_family) {
    for (int i = 0; font_ratios[i].name[0] != '\0'; i++) {
        if (strcmp(font_ratios[i].name, font_family) == 0) {
            return font_ratios[i].ratio;
        }
    }
    return 60; // Default ratio
}

// Calculate font metrics based on font family and size
void calculate_font_metrics(Config *config) {
    if (!config->font_width_explicit) {
        int ratio = get_font_ratio(config->font_family);
        config->font_width = config->font_size * ratio / 100.0;
    }
    if (!config->font_height_explicit) {
        config->font_height = config->font_size * 1.2;
    }
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Pre-calculated font metrics: width=%.2f, height=%.2f", 
                config->font_width, config->font_height);
        log_output(msg);
    }
}

// Get Google Font URL
const char* get_google_font_url(const char *font_family) {
    for (int i = 0; google_fonts[i].name[0] != '\0'; i++) {
        if (strcmp(google_fonts[i].name, font_family) == 0) {
            return google_fonts[i].url;
        }
    }
    return NULL;
}

// Get ANSI color by code
const char* get_ansi_color(int code) {
    for (int i = 0; ansi_colors[i].code != 0 || ansi_colors[i].color[0] != '\0'; i++) {
        if (ansi_colors[i].code == code) {
            return ansi_colors[i].color;
        }
    }
    return TEXT_COLOR; // Default color
}


// Read input (simplified version)
int read_input(Config *config) {
    FILE *input_source;
    
    progress_output("Reading source input");
    
    if (strlen(config->input_file) > 0) {
        input_source = fopen(config->input_file, "r");
        if (!input_source) {
            fprintf(stderr, "Error: Input file '%s' not found\n", config->input_file);
            return -1;
        }
    } else {
        input_source = stdin;
    }
    
    char line[MAX_LINE_LENGTH];
    input_line_count = 0;
    
    while (fgets(line, sizeof(line), input_source) && input_line_count < MAX_LINES) {
        int len = strlen(line);
        if (len > 0 && line[len-1] == '\n') {
            line[len-1] = '\0';
        }
        
        char expanded_line[MAX_LINE_LENGTH];
        expand_tabs(line, expanded_line, config->tab_size);
        strcpy(input_lines[input_line_count], expanded_line);
        input_line_count++;
    }
    
    if (input_source != stdin) {
        fclose(input_source);
    }
    
    char msg[768];  // Larger buffer to accommodate long paths
    const char *input_source_name = strlen(config->input_file) > 0 ? config->input_file : "stdin";
    snprintf(msg, sizeof(msg), "Read %d lines from %.500s", input_line_count, input_source_name);
    progress_output(msg);
    
    if (input_line_count == 0) {
        fprintf(stderr, "Error: No input provided\n");
        return -1;
    }
    
    if (config->height == 0) {
        config->height = input_line_count;
    }
    
    // Generate hashes with timing
    char hash_msg[256];
    snprintf(hash_msg, sizeof(hash_msg), "Hashing %d lines after wrapping/truncation", input_line_count);
    progress_output(hash_msg);
    
    double hash_start_time = get_current_time();
    
    for (int i = 0; i < input_line_count; i++) {
        unsigned int hash = generate_hash(input_lines[i]);
        snprintf(hash_cache[i], sizeof(hash_cache[i]), "%u", hash);
    }
    
    double hash_time = get_current_time() - hash_start_time;
    snprintf(hash_msg, sizeof(hash_msg), "Hash time: %.3fs, Time per line: %.3fs", 
            hash_time, hash_time / input_line_count);
    progress_output(hash_msg);
    
    return 0;
}

// Build font CSS
void build_font_css(const char *font, char *css_output, size_t css_size) {
    const char *google_url = get_google_font_url(font);
    
    if (google_url) {
        char escaped_url[MAX_URL_LENGTH];
        xml_escape_url(google_url, escaped_url, sizeof(escaped_url));
        snprintf(css_output, css_size, "@import url('%s'); .terminal-text { font-family: '%s', 'Consolas', 'Monaco', 'Courier New', monospace; }", 
                escaped_url, font);
    } else {
        snprintf(css_output, css_size, ".terminal-text { font-family: '%s', 'Consolas', 'Monaco', 'Courier New', monospace; }", font);
    }
}

// Process lines (simplified version)
int process_lines_single_pass(Config *config, char **svg_output) {
    char config_hash[MAX_HASH_LENGTH];
    generate_config_hash(config, config_hash);
    
    generate_global_input_hash();
    load_incremental_cache();
    
    char msg[256];
    snprintf(msg, sizeof(msg), "Processing %d lines", input_line_count);
    progress_output(msg);
    
    // Determine processing approach
    int cache_changed = (strcmp(global_input_hash, previous_input_hash) != 0);
    if (cache_changed || strlen(previous_input_hash) == 0) {
        snprintf(msg, sizeof(msg), "First run or major changes - processing all %d lines", input_line_count);
        progress_output(msg);
    }
    
    snprintf(msg, sizeof(msg), "Starting enhanced single-pass processing for %d lines", input_line_count);
    progress_output(msg);
    
    // Parse all lines
    LineData *line_data = malloc(input_line_count * sizeof(LineData));
    if (!line_data) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        return -1;
    }
    
    int max_width = 0;
    int max_width_line = 0;
    for (int i = 0; i < input_line_count; i++) {
        parse_ansi_line(input_lines[i], hash_cache[i], config_hash, &line_data[i]);
        if (line_data[i].visible_length > max_width) {
            max_width = line_data[i].visible_length;
            max_width_line = i;
        }
        
        if (debug_mode && line_data[i].visible_length > 0) {
            char debug_msg[512];
            snprintf(debug_msg, sizeof(debug_msg), "Line %d: visible_length=%d, content: %.50s...", 
                    i + 1, line_data[i].visible_length, input_lines[i]);
            log_output(debug_msg);
        }
    }
    
    // Content analysis
    snprintf(msg, sizeof(msg), "Content analysis: longest line is %d characters (line %d)", max_width, max_width_line + 1);
    progress_output(msg);
    
    if (debug_mode) {
        char debug_msg[512];
        snprintf(debug_msg, sizeof(debug_msg), "Longest line content: %.100s...", input_lines[max_width_line]);
        log_output(debug_msg);
    }
    
    // Fix grid width calculation to match bash version logic
    int grid_width;
    if (config->width == 80 && max_width > 80) {
        // Auto-detect width, but cap at 100 to match bash version behavior
        grid_width = max_width;
        if (grid_width > 100) grid_width = 100;
    } else {
        grid_width = config->width;
    }
    
    if (config->width == 80 && max_width > 80) {
        snprintf(msg, sizeof(msg), "Auto-detected width: %d characters (max_width: %d, capped at 100)", 
                grid_width, max_width);
        progress_output(msg);
    }
    
    double svg_width = (2 * DEFAULT_PADDING) + (grid_width * config->font_width);
    double svg_height = (2 * DEFAULT_PADDING) + (config->height * config->font_height);
    
    snprintf(msg, sizeof(msg), "SVG dimensions: %.2fx%.2f (%d lines, grid width: %d chars)", 
            svg_width, svg_height, config->height, grid_width);
    progress_output(msg);
    
    snprintf(msg, sizeof(msg), "Font: %s %dpx (char width: %.2f, line height: %.2f, weight: %d)", 
            config->font_family, config->font_size, config->font_width, config->font_height, config->font_weight);
    progress_output(msg);
    
    progress_output("Generating SVG fragments with enhanced caching");
    
    // Generate SVG
    size_t svg_size = 1024 * 1024;
    *svg_output = malloc(svg_size);
    if (!*svg_output) {
        free(line_data);
        return -1;
    }
    
    char font_css[1024];
    build_font_css(config->font_family, font_css, sizeof(font_css));
    
    int pos = 0;
    pos += snprintf(*svg_output + pos, svg_size - pos,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%.2f\" height=\"%.2f\" viewBox=\"0 0 %.2f %.2f\">\n"
        "  <defs><style>%s</style></defs>\n"
        "  <rect width=\"100%%\" height=\"100%%\" fill=\"%s\" rx=\"6\"/>\n",
        svg_width, svg_height, svg_width, svg_height, font_css, BG_COLOR);
    
    // Calculate cell width (same logic as bash version)
    double cell_width = (svg_width - (2.0 * DEFAULT_PADDING)) / grid_width;
    
    // Process each line
    for (int i = 0; i < input_line_count && i < config->height; i++) {
        double y_offset = DEFAULT_PADDING + config->font_size + (i * config->font_height);
        
        for (int j = 0; j < line_data[i].segment_count; j++) {
            TextSegment *seg = &line_data[i].segments[j];
            
            if (strlen(seg->text) > 0) {
                char escaped_text[MAX_LINE_LENGTH * 6];
                xml_escape(seg->text, escaped_text, sizeof(escaped_text));
                
                // Use cell_width for proper positioning (matches bash version)
                double current_x = DEFAULT_PADDING + (seg->visible_pos * cell_width);
                double text_width = utf8_strlen(seg->text) * cell_width;
                
                if (debug_mode) {
                    char debug_msg[512];
                    snprintf(debug_msg, sizeof(debug_msg), "  SVG segment: text='%s' visible_pos=%d current_x=%.2f cell_width=%.2f", 
                            seg->text, seg->visible_pos, current_x, cell_width);
                    log_output(debug_msg);
                }
                
                pos += snprintf(*svg_output + pos, svg_size - pos,
                    "  <text x=\"%.2f\" y=\"%.2f\" font-size=\"%d\" class=\"terminal-text\" xml:space=\"preserve\" textLength=\"%.2f\" lengthAdjust=\"spacingAndGlyphs\" fill=\"%s\">%s</text>\n",
                    current_x, y_offset, config->font_size, text_width, seg->fg_color, escaped_text);
            }
        }
    }
    
    pos += snprintf(*svg_output + pos, svg_size - pos, "</svg>\n");
    
    // Show cache statistics
    snprintf(msg, sizeof(msg), "Cache statistics: Segments %d/%d hits, SVG fragments %d/%d hits", 
            cache_stats_segment_hits, cache_stats_segment_hits + cache_stats_segment_misses,
            cache_stats_svg_hits, cache_stats_svg_hits + cache_stats_svg_misses);
    progress_output(msg);
    
    save_incremental_cache(config_hash);
    free(line_data);
    return 0;
}

// Output SVG
int output_svg(Config *config) {
    char *svg_content;
    
    if (process_lines_single_pass(config, &svg_content) != 0) {
        return -1;
    }
    
    if (strlen(config->output_file) > 0) {
        FILE *output_file = fopen(config->output_file, "w");
        if (!output_file) {
            fprintf(stderr, "Error: Cannot create output file '%s'\n", config->output_file);
            free(svg_content);
            return -1;
        }
        fprintf(output_file, "%s", svg_content);
        fclose(output_file);
        
        char msg[768];  // Larger buffer to accommodate long paths
        snprintf(msg, sizeof(msg), "SVG written to: %.500s", config->output_file);
        progress_output(msg);
    } else {
        printf("%s", svg_content);
    }
    
    free(svg_content);
    return 0;
}

// Main function
int main(int argc, char **argv) {
    script_start_time = get_current_time();
    
    Config config;
    
    if (argc == 1 && isatty(STDIN_FILENO)) {
        show_help();
        return 0;
    }
    
    show_version();
    
    if (parse_arguments(argc, argv, &config) != 0) {
        return 1;
    }
    
    setup_cache_directories();
    
    if (!config.font_width_explicit || !config.font_height_explicit) {
        calculate_font_metrics(&config);
    }
    
    char msg[768];  // Larger buffer to accommodate long paths
    progress_output("Parsed options:");
    const char *input_name = strlen(config.input_file) > 0 ? config.input_file : "stdin";
    const char *output_name = strlen(config.output_file) > 0 ? config.output_file : "stdout";
    snprintf(msg, sizeof(msg), "  Input: %.500s", input_name);
    progress_output(msg);
    snprintf(msg, sizeof(msg), "  Output: %.500s", output_name);
    progress_output(msg);
    snprintf(msg, sizeof(msg), "  Font: %s %dpx (width: %.2f, line height: %.2f, weight: %d)", 
            config.font_family, config.font_size, config.font_width, config.font_height, config.font_weight);
    progress_output(msg);
    snprintf(msg, sizeof(msg), "  Grid: %dx%d", config.width, config.height);
    progress_output(msg);
    snprintf(msg, sizeof(msg), "  Wrap: %s", config.wrap ? "true" : "false");
    progress_output(msg);
    snprintf(msg, sizeof(msg), "  Tab size: %d", config.tab_size);
    progress_output(msg);
    
    if (read_input(&config) != 0) {
        return 1;
    }
    
    if (output_svg(&config) != 0) {
        return 1;
    }
    
    progress_output("Oh v1.000 SVG generation complete! 🎯");
    
    return 0;
}
