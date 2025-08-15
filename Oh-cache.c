/*
 * Oh-cache.c - Cache management module  
 * Part of Oh.c - Convert ANSI terminal output to GitHub-compatible SVG
 */

#include "Oh.h"

// Generate hash using system cksum for exact compatibility
unsigned int generate_hash(const char *input) {
    FILE *fp;
    char command[MAX_LINE_LENGTH + 50];
    char result[64];
    unsigned int hash = 0;
    
    // Use system cksum for exact compatibility with bash version
    snprintf(command, sizeof(command), "printf '%%s' '%s' | cksum", input);
    
    fp = popen(command, "r");
    if (fp && fgets(result, sizeof(result), fp)) {
        hash = (unsigned int)strtoul(result, NULL, 10);
        pclose(fp);
    } else {
        // Fallback to simple hash if cksum fails
        const unsigned char *data = (const unsigned char *)input;
        hash = 0;
        while (*data) {
            hash = hash * 31 + *data;
            data++;
        }
        if (fp) pclose(fp);
    }
    
    return hash;
}

// Generate configuration hash
void generate_config_hash(const Config *config, char *hash_out) {
    char config_string[1024];
    // Use "false"/"true" strings to match bash version
    const char *wrap_str = config->wrap ? "true" : "false";
    snprintf(config_string, sizeof(config_string), 
             "%s|%d|%.2f|%.2f|%d|%d|%d|%s|%d|%s|%s|%d",
             config->font_family, config->font_size, config->font_width, config->font_height,
             config->font_weight, config->width, config->height, wrap_str, config->tab_size,
             BG_COLOR, TEXT_COLOR, DEFAULT_PADDING);
    
    unsigned int hash = generate_hash(config_string);
    snprintf(hash_out, MAX_HASH_LENGTH, "%u", hash);
    
    if (debug_mode) {
        char msg[512];
        snprintf(msg, sizeof(msg), "Config string for hashing: %.400s", config_string);
        log_output(msg);
        snprintf(msg, sizeof(msg), "Generated config hash: %s", hash_out);
        log_output(msg);
    }
}

// Get cache key
void get_cache_key(const char *line_hash, const char *config_hash, char *cache_key) {
    snprintf(cache_key, MAX_CACHE_KEY_LENGTH, "%s_%s", config_hash, line_hash);
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Generated cache key: %s (config: %s, line: %s)", 
                cache_key, config_hash, line_hash);
        log_output(msg);
    }
}

// Save line cache to JSON file
int save_line_cache(const char *cache_key, const LineData *line_data) {
    char cache_file[MAX_PATH_LENGTH];
    int ret = snprintf(cache_file, sizeof(cache_file), "%s/%s.json", cache_dir, cache_key);
    if (ret >= (int)sizeof(cache_file)) {
        if (debug_mode) {
            log_output("Cache file path too long, skipping save");
        }
        return -1;
    }
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Saving cache for key: %.100s", cache_key);
        log_output(msg);
    }
    
    // Create JSON object using jansson
    json_t *root = json_object();
    if (!root) {
        if (debug_mode) {
            log_output("Failed to create JSON object");
        }
        return -1;
    }
    
    // Set cache_key
    json_object_set_new(root, "cache_key", json_string(cache_key));
    
    // Set visible_length
    json_object_set_new(root, "visible_length", json_integer(line_data->visible_length));
    
    // Create segments array
    json_t *segments_array = json_array();
    for (int i = 0; i < line_data->segment_count; i++) {
        const TextSegment *seg = &line_data->segments[i];
        char segment_string[MAX_LINE_LENGTH * 2];
        snprintf(segment_string, sizeof(segment_string), "%s|%s|%s|%s|%d",
                seg->text, seg->fg_color, seg->bg_color, 
                seg->bold ? "true" : "false", seg->visible_pos);
        json_array_append_new(segments_array, json_string(segment_string));
    }
    json_object_set_new(root, "segments", segments_array);
    
    // Set timestamp
    time_t timestamp = time(NULL);
    json_object_set_new(root, "timestamp", json_integer(timestamp));
    
    // Write JSON to file
    if (json_dump_file(root, cache_file, JSON_INDENT(2)) != 0) {
        if (debug_mode) {
            char msg[512];
            snprintf(msg, sizeof(msg), "Failed to write cache file: %.400s", cache_file);
            log_output(msg);
        }
        json_decref(root);
        return -1;
    }
    
    json_decref(root);
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Cache saved to: %.200s", cache_file);
        log_output(msg);
    }
    
    return 0;
}

// Load line cache from JSON file
int load_line_cache(const char *cache_key, LineData *line_data) {
    char cache_file[MAX_PATH_LENGTH];
    int ret = snprintf(cache_file, sizeof(cache_file), "%s/%s.json", cache_dir, cache_key);
    if (ret >= (int)sizeof(cache_file)) {
        if (debug_mode) {
            log_output("Cache file path too long, skipping load");
        }
        cache_stats_segment_misses++;
        return -1;
    }
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Looking for cache key: %.100s", cache_key);
        log_output(msg);
    }
    
    // Load JSON from file using jansson
    json_error_t error;
    json_t *root = json_load_file(cache_file, 0, &error);
    if (!root) {
        if (debug_mode) {
            char msg[256];
            snprintf(msg, sizeof(msg), "Cache miss: %.200s", cache_file);
            log_output(msg);
        }
        cache_stats_segment_misses++;
        return -1;
    }
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Cache hit: %.200s", cache_file);
        log_output(msg);
    }
    cache_stats_segment_hits++;
    
    // Initialize line data
    line_data->segment_count = 0;
    line_data->visible_length = 0;
    
    // Parse visible_length
    json_t *visible_length_obj = json_object_get(root, "visible_length");
    if (json_is_integer(visible_length_obj)) {
        line_data->visible_length = (int)json_integer_value(visible_length_obj);
    }
    
    // Parse segments array
    json_t *segments_array = json_object_get(root, "segments");
    if (json_is_array(segments_array)) {
        size_t array_size = json_array_size(segments_array);
        for (size_t i = 0; i < array_size && line_data->segment_count < MAX_SEGMENTS; i++) {
            json_t *segment_str = json_array_get(segments_array, i);
            if (json_is_string(segment_str)) {
                const char *segment_data = json_string_value(segment_str);
                
                // Parse segment: text|fg|bg|bold|pos
                if (debug_mode) {
                    char raw_debug_msg[512];
                    snprintf(raw_debug_msg, sizeof(raw_debug_msg), "    Raw segment data: '%s'", segment_data);
                    log_output(raw_debug_msg);
                }
                
                char segment_copy[MAX_LINE_LENGTH * 2];
                strncpy(segment_copy, segment_data, sizeof(segment_copy) - 1);
                segment_copy[sizeof(segment_copy) - 1] = '\0';
                
                // Manual parsing to handle empty fields (strtok_r skips empty fields)
                char *parts[5] = {NULL, NULL, NULL, NULL, NULL};
                char *current = segment_copy;
                int part_count = 0;
                
                for (int field = 0; field < 5 && part_count < 5; field++) {
                    parts[part_count] = current;
                    char *next_pipe = strchr(current, '|');
                    if (next_pipe) {
                        *next_pipe = '\0';
                        current = next_pipe + 1;
                    }
                    part_count++;
                    if (!next_pipe) break;
                }
                
                // Parse each field
                if (parts[0]) {
                    strcpy(line_data->segments[line_data->segment_count].text, parts[0]);
                    if (debug_mode) {
                        char text_debug_msg[256];
                        snprintf(text_debug_msg, sizeof(text_debug_msg), "    Parsed text: '%s'", parts[0]);
                        log_output(text_debug_msg);
                    }
                }
                
                if (parts[1]) {
                    strcpy(line_data->segments[line_data->segment_count].fg_color, parts[1]);
                    if (debug_mode) {
                        char fg_debug_msg[256];
                        snprintf(fg_debug_msg, sizeof(fg_debug_msg), "    Parsed fg_color: '%s'", parts[1]);
                        log_output(fg_debug_msg);
                    }
                }
                
                if (parts[2]) {
                    strcpy(line_data->segments[line_data->segment_count].bg_color, parts[2]);
                    if (debug_mode) {
                        char bg_debug_msg[256];
                        snprintf(bg_debug_msg, sizeof(bg_debug_msg), "    Parsed bg_color: '%s'", parts[2]);
                        log_output(bg_debug_msg);
                    }
                }
                
                if (parts[3]) {
                    line_data->segments[line_data->segment_count].bold = (strcmp(parts[3], "true") == 0);
                    if (debug_mode) {
                        char bold_debug_msg[256];
                        snprintf(bold_debug_msg, sizeof(bold_debug_msg), "    Parsed bold: '%s' -> %d", parts[3], line_data->segments[line_data->segment_count].bold);
                        log_output(bold_debug_msg);
                    }
                }
                
                if (parts[4]) {
                    line_data->segments[line_data->segment_count].visible_pos = atoi(parts[4]);
                    
                    if (debug_mode) {
                        char pos_debug_msg[256];
                        snprintf(pos_debug_msg, sizeof(pos_debug_msg), "    Parsed visible_pos: '%s' -> %d for segment '%s'", 
                                parts[4], line_data->segments[line_data->segment_count].visible_pos,
                                line_data->segments[line_data->segment_count].text);
                        log_output(pos_debug_msg);
                    }
                }
                
                line_data->segment_count++;
            }
        }
    }
    
    json_decref(root);
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Cache loaded: %d segments, visible length: %d", 
                line_data->segment_count, line_data->visible_length);
        log_output(msg);
    }
    
    return 0;
}

// Get SVG fragment cache key
void get_svg_fragment_cache_key(const char *line_hash, const char *config_hash, int line_number, char *cache_key) {
    snprintf(cache_key, MAX_CACHE_KEY_LENGTH, "svg_%s_%d_%s", config_hash, line_number, line_hash);
}

// Save SVG fragment cache
int save_svg_fragment_cache(const char *cache_key, const char *svg_fragment) {
    char cache_file[MAX_PATH_LENGTH];
    int ret = snprintf(cache_file, sizeof(cache_file), "%s/%s.svg", svg_cache_dir, cache_key);
    if (ret >= (int)sizeof(cache_file)) {
        if (debug_mode) {
            log_output("SVG cache file path too long, skipping save");
        }
        return -1;
    }
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Saving SVG fragment cache: %.100s", cache_key);
        log_output(msg);
    }
    
    FILE *file = fopen(cache_file, "w");
    if (!file) {
        if (debug_mode) {
            char msg[512];
            snprintf(msg, sizeof(msg), "Failed to write SVG fragment cache: %.400s", cache_file);
            log_output(msg);
        }
        return -1;
    }
    
    fprintf(file, "%s", svg_fragment);
    fclose(file);
    return 0;
}

// Load SVG fragment cache
char* load_svg_fragment_cache(const char *cache_key) {
    char cache_file[MAX_PATH_LENGTH];
    int ret = snprintf(cache_file, sizeof(cache_file), "%s/%s.svg", svg_cache_dir, cache_key);
    if (ret >= (int)sizeof(cache_file)) {
        if (debug_mode) {
            log_output("SVG cache file path too long, skipping load");
        }
        cache_stats_svg_misses++;
        return NULL;
    }
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Looking for SVG fragment cache: %.100s", cache_key);
        log_output(msg);
    }
    
    FILE *file = fopen(cache_file, "r");
    if (!file) {
        if (debug_mode) {
            char msg[256];
            snprintf(msg, sizeof(msg), "SVG fragment cache miss: %.200s", cache_file);
            log_output(msg);
        }
        cache_stats_svg_misses++;
        return NULL;
    }
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "SVG fragment cache hit: %.200s", cache_file);
        log_output(msg);
    }
    cache_stats_svg_hits++;
    
    // Read entire file
    fseek(file, 0, SEEK_END);
    long file_size = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    char *content = malloc(file_size + 1);
    if (!content) {
        fclose(file);
        return NULL;
    }
    
    fread(content, 1, file_size, file);
    content[file_size] = '\0';
    fclose(file);
    
    return content;
}

// Generate global input hash
void generate_global_input_hash(void) {
    char combined_hashes[MAX_LINES * MAX_HASH_LENGTH];
    combined_hashes[0] = '\0';
    
    for (int i = 0; i < input_line_count; i++) {
        strcat(combined_hashes, hash_cache[i]);
    }
    
    unsigned int hash = generate_hash(combined_hashes);
    snprintf(global_input_hash, sizeof(global_input_hash), "%u", hash);
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Generated global input hash: %s", global_input_hash);
        log_output(msg);
    }
}

// Load incremental cache
int load_incremental_cache(void) {
    // Load JSON from file using jansson
    json_error_t error;
    json_t *root = json_load_file(incremental_cache_file, 0, &error);
    if (!root) {
        if (debug_mode) {
            log_output("No incremental cache found");
        }
        return -1;
    }
    
    // Parse global_input_hash
    json_t *hash_obj = json_object_get(root, "global_input_hash");
    if (json_is_string(hash_obj)) {
        const char *hash_value = json_string_value(hash_obj);
        strncpy(previous_input_hash, hash_value, sizeof(previous_input_hash) - 1);
        previous_input_hash[sizeof(previous_input_hash) - 1] = '\0';
    }
    
    json_decref(root);
    
    if (debug_mode) {
        char msg[256];
        snprintf(msg, sizeof(msg), "Loaded previous input hash: %s", previous_input_hash);
        log_output(msg);
    }
    
    return 0;
}

// Save incremental cache
int save_incremental_cache(const char *config_hash) {
    if (debug_mode) {
        log_output("Saving incremental cache data");
    }
    
    // Create JSON object using jansson
    json_t *root = json_object();
    if (!root) {
        if (debug_mode) {
            log_output("Failed to create JSON object for incremental cache");
        }
        return -1;
    }
    
    // Set global_input_hash
    json_object_set_new(root, "global_input_hash", json_string(global_input_hash));
    
    // Set config_hash
    json_object_set_new(root, "config_hash", json_string(config_hash));
    
    // Set line_count
    json_object_set_new(root, "line_count", json_integer(input_line_count));
    
    // Create line_hashes array
    json_t *line_hashes_array = json_array();
    for (int i = 0; i < input_line_count; i++) {
        json_array_append_new(line_hashes_array, json_string(hash_cache[i]));
    }
    json_object_set_new(root, "line_hashes", line_hashes_array);
    
    // Set timestamp
    time_t timestamp = time(NULL);
    json_object_set_new(root, "timestamp", json_integer(timestamp));
    
    // Create cache_stats object
    json_t *cache_stats = json_object();
    json_object_set_new(cache_stats, "segment_hits", json_integer(cache_stats_segment_hits));
    json_object_set_new(cache_stats, "segment_misses", json_integer(cache_stats_segment_misses));
    json_object_set_new(cache_stats, "svg_hits", json_integer(cache_stats_svg_hits));
    json_object_set_new(cache_stats, "svg_misses", json_integer(cache_stats_svg_misses));
    json_object_set_new(root, "cache_stats", cache_stats);
    
    // Write JSON to file
    if (json_dump_file(root, incremental_cache_file, JSON_INDENT(2)) != 0) {
        if (debug_mode) {
            log_output("Failed to write incremental cache file");
        }
        json_decref(root);
        return -1;
    }
    
    json_decref(root);
    return 0;
}
