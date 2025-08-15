/*
 * Oh-parse.c - ANSI parsing and text processing module
 * Part of Oh.c - Convert ANSI terminal output to GitHub-compatible SVG
 */

#include "Oh.h"

// Expand tabs to spaces
void expand_tabs(const char *input, char *output, int tab_size) {
    const char *src = input;
    char *dst = output;
    
    while (*src) {
        if (*src == '\t') {
            for (int i = 0; i < tab_size; i++) {
                *dst++ = ' ';
            }
        } else {
            *dst++ = *src;
        }
        src++;
    }
    *dst = '\0';
}

// XML escape function
void xml_escape(const char *input, char *output, size_t output_size) {
    const char *src = input;
    char *dst = output;
    size_t remaining = output_size - 1; // Leave space for null terminator
    
    while (*src && remaining > 5) { // Need at least 5 chars for longest escape (&quot;)
        if (*src == '&') {
            if (remaining >= 5) {
                strcpy(dst, "&amp;");
                dst += 5;
                remaining -= 5;
            }
        } else if (*src == '<') {
            if (remaining >= 4) {
                strcpy(dst, "&lt;");
                dst += 4;
                remaining -= 4;
            }
        } else if (*src == '>') {
            if (remaining >= 4) {
                strcpy(dst, "&gt;");
                dst += 4;
                remaining -= 4;
            }
        } else if (*src == '"') {
            if (remaining >= 6) {
                strcpy(dst, "&quot;");
                dst += 6;
                remaining -= 6;
            }
        } else if (*src == '\'') {
            if (remaining >= 6) {
                strcpy(dst, "&apos;");
                dst += 6;
                remaining -= 6;
            }
        } else {
            *dst++ = *src;
            remaining--;
        }
        src++;
    }
    *dst = '\0';
}

// XML escape for URLs
void xml_escape_url(const char *input, char *output, size_t output_size) {
    const char *src = input;
    char *dst = output;
    size_t remaining = output_size - 1;
    
    while (*src && remaining > 5) {
        if (*src == '&') {
            if (remaining >= 5) {
                strcpy(dst, "&amp;");
                dst += 5;
                remaining -= 5;
            }
        } else {
            *dst++ = *src;
            remaining--;
        }
        src++;
    }
    *dst = '\0';
}

#include <stdint.h>

// UTF-8 character length function
int utf8_strlen(const char *str) {
    int len = 0;
    const uint8_t *p = (const uint8_t *)str;
    while (*p) {
        if ((*p & 0xC0) != 0x80) len++;
        p++;
    }
    return len;
}

// Parse ANSI line (matching bash logic exactly)
int parse_ansi_line(const char *line, const char *line_hash, const char *config_hash, LineData *line_data) {
    // Try cache first
    if (line_hash && config_hash && strlen(line_hash) > 0 && strlen(config_hash) > 0) {
        char cache_key[MAX_CACHE_KEY_LENGTH];
        get_cache_key(line_hash, config_hash, cache_key);
        
        if (load_line_cache(cache_key, line_data) == 0) {
            if (debug_mode) {
                char msg[256];
                snprintf(msg, sizeof(msg), "Cache hit for line: %.50s... (loaded %d segments)", 
                        line, line_data->segment_count);
                log_output(msg);
                // Debug: show loaded visible_pos values
                for (int i = 0; i < line_data->segment_count; i++) {
                    char debug_msg[512];
                    snprintf(debug_msg, sizeof(debug_msg), "  Loaded segment %d: text='%.20s' visible_pos=%d", 
                            i, line_data->segments[i].text, line_data->segments[i].visible_pos);
                    log_output(debug_msg);
                }
            }
            return 0;
        }
        
        if (debug_mode) {
            char msg[256];
            snprintf(msg, sizeof(msg), "Cache miss for line: %.50s...", line);
            log_output(msg);
        }
    }
    
    // Initialize line data
    line_data->segment_count = 0;
    line_data->visible_length = 0;
    
    // Current state
    const char *fg = TEXT_COLOR;
    const char *bg = "";
    int bold = 0;
    int visible_pos = 0;
    
    // Working variables for current segment
    char current_text[MAX_LINE_LENGTH] = "";
    int current_text_pos = 0;
    
    const char *ptr = line;
    
    while (*ptr) {
        if (*ptr == '\033' && *(ptr + 1) == '[') {
            // Save any accumulated text before processing escape sequence
            if (current_text_pos > 0 && line_data->segment_count < MAX_SEGMENTS) {
                current_text[current_text_pos] = '\0';
                
                TextSegment *seg = &line_data->segments[line_data->segment_count];
                strcpy(seg->text, current_text);
                strcpy(seg->fg_color, fg);
                strcpy(seg->bg_color, bg);
                seg->bold = bold;
                seg->visible_pos = visible_pos;
                
                if (debug_mode) {
                    char debug_msg[512];
                    snprintf(debug_msg, sizeof(debug_msg), "  Created segment %d: text='%.20s' visible_pos=%d", 
                            line_data->segment_count, current_text, visible_pos);
                    log_output(debug_msg);
                }
                
                int char_len = utf8_strlen(current_text);
                visible_pos += char_len;
                line_data->segment_count++;
                
                // Reset for next segment
                current_text_pos = 0;
            }
            
            // Skip ESC[
            ptr += 2;
            
            // Parse numeric codes
            char codes[64] = "";
            int codes_pos = 0;
            
            while (*ptr && *ptr != 'm' && codes_pos < (int)sizeof(codes) - 1) {
                codes[codes_pos++] = *ptr++;
            }
            codes[codes_pos] = '\0';
            
            // Skip 'm'
            if (*ptr == 'm') ptr++;
            
            // Process codes (handle semicolon-separated values)
            if (strlen(codes) == 0) {
                // Empty code means reset (ESC[m)
                fg = TEXT_COLOR;
                bg = "";
                bold = 0;
            } else {
                char *code_str = strtok(codes, ";");
                while (code_str) {
                    int code = atoi(code_str);
                    
                    if (code == 0) {
                        // Reset all
                        fg = TEXT_COLOR;
                        bg = "";
                        bold = 0;
                    } else if (code == 1) {
                        // Bold
                        bold = 1;
                    } else if (code >= 30 && code <= 37) {
                        // Foreground colors
                        fg = get_ansi_color(code);
                    } else if (code >= 90 && code <= 97) {
                        // Bright foreground colors
                        fg = get_ansi_color(code);
                    } else if (code >= 40 && code <= 47) {
                        // Background colors (basic implementation)
                        bg = get_ansi_color(code - 10);
                    }
                    
                    code_str = strtok(NULL, ";");
                }
            }
        } else {
            // Regular character - add to current text
            if (current_text_pos < MAX_LINE_LENGTH - 1) {
                current_text[current_text_pos++] = *ptr;
            }
            ptr++;
        }
    }
    
    // Save any remaining text
    if (current_text_pos > 0 && line_data->segment_count < MAX_SEGMENTS) {
        current_text[current_text_pos] = '\0';
        
        TextSegment *seg = &line_data->segments[line_data->segment_count];
        strcpy(seg->text, current_text);
        strcpy(seg->fg_color, fg);
        strcpy(seg->bg_color, bg);
        seg->bold = bold;
        seg->visible_pos = visible_pos;
        
        if (debug_mode) {
            char debug_msg[512];
            snprintf(debug_msg, sizeof(debug_msg), "  Final segment %d: text='%.20s' visible_pos=%d", 
                    line_data->segment_count, current_text, visible_pos);
            log_output(debug_msg);
        }
        
        int char_len = utf8_strlen(current_text);
        visible_pos += char_len;
        line_data->segment_count++;
    }
    
    // Set final visible length
    line_data->visible_length = visible_pos;
    
    // Save to cache
    if (line_hash && config_hash) {
        char cache_key[MAX_CACHE_KEY_LENGTH];
        get_cache_key(line_hash, config_hash, cache_key);
        save_line_cache(cache_key, line_data);
    }
    
    if (debug_mode) {
        char msg[512];
        snprintf(msg, sizeof(msg), "Parsed line: %d segments, visible length: %d", 
                line_data->segment_count, line_data->visible_length);
        log_output(msg);
    }
    
    return 0;
}
