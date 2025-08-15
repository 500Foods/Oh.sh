#!/bin/bash

# oh.sh - Convert ANSI terminal output to GitHub-compatible SVG

# CHANGELOG
# 1.008 - Fixing shellcheck errors and reducing code size
# 1.007 - Implement Phase 6: Testing and validation with comprehensive performance benchmarking
# 1.006 - Implement Phase 5: Advanced optimizations with SVG fragment caching and incremental processing
#         Fix critical performance regression by replacing adler32_hash with cksum; optimize hash operations
# 1.005 - Implement Phase 4: Mathematical and subprocess optimizations, eliminate bc calls with integer arithmetic
# 1.004 - Implement Phase 3: Core parsing optimizations with pre-compiled ANSI patterns and streamlined processing
# 1.003 - Implement Phase 2: Single-pass architecture restructuring to eliminate double processing
# 1.002 - Add SVG validation with xmllint for XML well-formedness checking
# 1.001 - Updated Cache directory
# 1.000 - Initial release with basic functionality
# 0.026 - Fix XML character escaping in xml_escape function; improve width calculation reporting with auto-width limits
# 0.025 - Fix --width to enforce grid width and clip lines; add debug logging for clipping
# 0.024 - Fix syntax error in generate_svg loop; add empty input check; enhance debug logging for cell_width and height truncation
# 0.023 - Implement grid-based layout for font-agnostic alignment; add --width, --wrap, --height,
#         --font-width, --font-height, --font-weight; remove font-specific width calculations;
#         process wrapping/truncation early; clip text exceeding grid
# 0.022 - Fix XML parsing error in URL, fix parse_ansi_line to avoid over-accumulating visible_column
# 0.021 - Make parse_ansi_line generic, adjust Inconsolata font ratio
# 0.020 - Fix alignment by normalizing filename column position, remove expand_tabs
# 0.019 - Fix ShellCheck errors (unclosed quotes, parameter expansions)
# 0.018 - Retyped entire script to eliminate hidden characters causing unclosed quote errors
# 0.017 - Retype main function to fix hidden character causing unclosed quote error
# 0.016 - Fix syntax error in main function (unclosed single quote)
# 0.015 - Fix tab expansion by handling it in a separate pass before ANSI parsing
# 0.014 - Fix tab expansion to account for ANSI codes properly (attempted but incomplete)
# 0.013 - Fix position calculation to not count ANSI escape sequences as visible characters
# 0.012 - Debug positioning and fix overly aggressive XML escaping
# 0.011 - Switch to integer-based positioning to fix alignment drift
# 0.010 - Fix character counting to exclude ANSI codes from dimension calculations
# 0.009 - Add xml:space="preserve" to maintain exact whitespace spacing
# 0.008 - Fix XML encoding in URLs and proper tab handling for column alignment
# 0.007 - Font selection and accurate character width calculations
# 0.006 - ANSI color parsing and SVG styling
# 0.005 - Strip ANSI escape sequences to fix XML parsing errors
# 0.004 - Input handling and basic text rendering to SVG
# 0.003 - SVG output pipeline with file/stdout support
# 0.002 - Better help handling, version output, and empty input detection
# 0.001 - Initial framework with argument parsing and help system

set -euo pipefail

# MetaData
SCRIPT_NAME="Oh.sh"
SCRIPT_VERSION="1.007"
SCRIPT_START=$(date +%s.%N)

# Caching 
CACHE_STATS_SEGMENT_HITS=0
CACHE_STATS_SEGMENT_MISSES=0
CACHE_STATS_SVG_HITS=0
CACHE_STATS_SVG_MISSES=0
CACHE_DIR="${HOME}/.cache/Oh"
GLOBAL_INPUT_HASH=""              
PREVIOUS_INPUT_HASH=""            
SVG_CACHE_DIR="${CACHE_DIR}/svg"  
INCREMENTAL_CACHE_FILE="${CACHE_DIR}/incremental.json"  
mkdir -p "${CACHE_DIR}" "${CACHE_DIR}/svg"

# Defaults
INPUT_FILE=""
OUTPUT_FILE=""
DEBUG=false
FONT_SIZE=14
FONT_FAMILY="Consolas"
FONT_WIDTH=""                       # Will be calculated by calculate_font_metrics()
FONT_HEIGHT=""                      # Will be calculated by calculate_font_metrics()
FONT_WEIGHT=400
WIDTH=80                            # Default grid width in characters
HEIGHT=0                            # Default gird height in lines
WRAP=false
PADDING=20
BG_COLOR="#1e1e1e"
TEXT_COLOR="#ffffff"
TAB_SIZE=8                          # Standard tab stop every 8 characters
ANSI_COLOR_PATTERN=$'\e\[[0-9;]*m'  # Color/style sequences
FONT_WIDTH_EXPLICIT=false
FONT_HEIGHT_EXPLICIT=false
FONT_WIDTH_INT=0                    # Will be calculated based on font size and ratio
FONT_HEIGHT_INT=0                   # Will be calculated as font_size * 120 (1.2 ratio)
SVG_WIDTH_INT=0                     # Pre-calculated SVG width
SVG_HEIGHT_INT=0                    # Pre-calculated SVG height
CELL_WIDTH_INT=0                    # Pre-calculated cell width for positioning

# Storage arrays
declare -a INPUT_LINES
declare -a LINE_SEGMENTS
declare -a HASH_CACHE
declare -A MULTI_ARGS
declare -A FONT_CHAR_RATIOS_INT
declare -a INPUT_HASH_CACHE       
declare -A GOOGLE_FONTS
declare -A ANSI_COLORS

# Character width ratios for common fonts (scaled by 100 for integer arithmetic)
FONT_CHAR_RATIOS_INT["Consolas"]=60
FONT_CHAR_RATIOS_INT["Monaco"]=60
FONT_CHAR_RATIOS_INT["Courier New"]=60
FONT_CHAR_RATIOS_INT["Inconsolata"]=60
FONT_CHAR_RATIOS_INT["JetBrains Mono"]=55
FONT_CHAR_RATIOS_INT["Source Code Pro"]=55
FONT_CHAR_RATIOS_INT["Fira Code"]=58
FONT_CHAR_RATIOS_INT["Roboto Mono"]=60
FONT_CHAR_RATIOS_INT["Ubuntu Mono"]=50
FONT_CHAR_RATIOS_INT["Menlo"]=60

# Google Fonts (URLs will be XML-escaped)
GOOGLE_FONTS["Inconsolata"]="https://fonts.googleapis.com/css2?family=Inconsolata:wght@400;700&display=swap"
GOOGLE_FONTS["JetBrains Mono"]="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap"
GOOGLE_FONTS["Source Code Pro"]="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap"
GOOGLE_FONTS["Fira Code"]="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;700&display=swap"
GOOGLE_FONTS["Roboto Mono"]="https://fonts.googleapis.com/css2?family=Roboto+Mono:wght@400;700&display=swap"

# ANSI color mappings (standard 16 colors)
ANSI_COLORS[30]="#000000"   # Black
ANSI_COLORS[31]="#cd3131"   # Red
ANSI_COLORS[32]="#0dbc79"   # Green  
ANSI_COLORS[33]="#e5e510"   # Yellow
ANSI_COLORS[34]="#2472c8"   # Blue
ANSI_COLORS[35]="#bc3fbc"   # Magenta
ANSI_COLORS[36]="#11a8cd"   # Cyan
ANSI_COLORS[37]="#e5e5e5"   # White
ANSI_COLORS[90]="#666666"   # Bright Black (Gray)
ANSI_COLORS[91]="#f14c4c"   # Bright Red
ANSI_COLORS[92]="#23d18b"   # Bright Green
ANSI_COLORS[93]="#f5f543"   # Bright Yellow
ANSI_COLORS[94]="#3b8eea"   # Bright Blue
ANSI_COLORS[95]="#d670d6"   # Bright Magenta
ANSI_COLORS[96]="#29b8db"   # Bright Cyan
ANSI_COLORS[97]="#e5e5e5"   # Bright White

int_to_decimal() {
    local value="$1"
    local integer_part=$((value / 100))
    local decimal_part=$((value % 100))
    printf "%d.%02d" "${integer_part}" "${decimal_part}"
}

decimal_to_int() {
    local decimal="$1"
    # Handle both integer and decimal inputs
    if [[ "${decimal}" == *.* ]]; then
        local integer_part="${decimal%.*}"
        local decimal_part="${decimal#*.}"
        # Pad or truncate decimal part to 2 digits
        decimal_part="${decimal_part}00"
        decimal_part="${decimal_part:0:2}"
        echo $((integer_part * 100 + decimal_part))
    else
        echo $((decimal * 100))
    fi
}

calculate_font_metrics() {
    local font_ratio_int="${FONT_CHAR_RATIOS_INT[${FONT_FAMILY}]:-60}"  # Default 0.6 = 60/100
    FONT_WIDTH_INT=$((FONT_SIZE * font_ratio_int))      # font_size * ratio * 100
    FONT_HEIGHT_INT=$((FONT_SIZE * 120))                # font_size * 1.2 * 100
    [[ "${DEBUG}" == true ]] && log_output "Pre-calculated font metrics: width=${FONT_WIDTH_INT}/100, height=${FONT_HEIGHT_INT}/100"
    FONT_WIDTH=$(int_to_decimal "${FONT_WIDTH_INT}")
    FONT_HEIGHT=$(int_to_decimal "${FONT_HEIGHT_INT}")
}

log_output() {
    local message="$1"
    local elapsed_time
    local current_time
    current_time=$(date +%s.%N)
    elapsed_time=$(awk "BEGIN {printf \"%.6f\", ${current_time} - ${SCRIPT_START}}")
    elapsed_time_formatted=$(printf "%07.3f" "${elapsed_time}")
    echo "${elapsed_time_formatted} - ${message}" >&2
}

show_version() {
    echo "${SCRIPT_NAME}   - v${SCRIPT_VERSION} - Convert ANSI terminal output to GitHub-compatible SVG" >&2
}

show_help() {
    show_version
    cat >&2 << HELP_EOF

USAGE:
    command | oh.sh [OPTIONS] > output.svg
    oh.sh [OPTIONS] -i input.txt -o output.svg

OPTIONS:
    -h, --help              Show this help
    -i, --input FILE        Input file (default: stdin)
    -o, --output FILE       Output file (default: stdout)
    --font FAMILY           Font family (default: Consolas)
    --font-size SIZE        Font size in pixels (default: 14)
    --font-width PX         Character width in pixels (default: 0.6 * font-size)
    --font-height PX        Line height in pixels (default: 1.2 * font-size)
    --font-weight WEIGHT    Font weight (default: 400)
    --width CHARS           Grid width in characters (default: 80)
    --height CHARS          Grid height in lines (default: input line count)
    --wrap                  Wrap lines at width (default: false)
    --tab-size SIZE         Tab stop size (default: 8)
    --debug                 Enable debug output
    --version               Show version information
    
SUPPORTED FONTS:
    Consolas, Monaco, Courier New (system fonts)
    Inconsolata, JetBrains Mono, Source Code Pro, 
    Fira Code, Roboto Mono (Google Fonts - embedded automatically)
    Font metric defaults are editable in the script.

EXAMPLES:
    ls --color=always -l | ${SCRIPT_NAME} > listing.svg
    git diff --color | ${SCRIPT_NAME} --font "JetBrains Mono" --font-size 16 -o diff.svg
    ${SCRIPT_NAME} --font Inconsolata --width 60 --wrap -i terminal-output.txt -o styled.svg

HELP_EOF
}

check_for_help() {
    for arg in "$@"; do
        if [[ "${arg}" == "-h" || "${arg}" == "--help" ]]; then
            show_help
            exit 0
        fi
    done
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                exit 0
                ;;
            -i|--input)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --input requires a filename" >&2; exit 1; }
                INPUT_FILE="$2"
                shift
                ;;
            -o|--output)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --output requires a filename" >&2; exit 1; }
                OUTPUT_FILE="$2"
                shift
                ;;
            --font)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --font requires a font family name" >&2; exit 1; }
                FONT_FAMILY="$2"
                shift
                ;;
            --font-size)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --font-size requires a number" >&2; exit 1; }
                [[ ! "$2" =~ ^[0-9]+$ || "$2" -lt 8 || "$2" -gt 72 ]] && { echo "Error: --font-size must be a number between 8 and 72" >&2; exit 1; }
                FONT_SIZE="$2"
                shift
                ;;
            --font-width)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --font-width requires a number" >&2; exit 1; }
                local width_int
                width_int=$(decimal_to_int "$2")
                [[ ! "$2" =~ ^[0-9]+(\.[0-9]+)?$ || "${width_int}" -lt 100 ]] && { echo "Error: --font-width must be a number >= 1" >&2; exit 1; }
                FONT_WIDTH="$2"
                FONT_WIDTH_EXPLICIT=true
                shift
                ;;
            --font-height)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --font-height requires a number" >&2; exit 1; }
                local height_int
                height_int=$(decimal_to_int "$2")
                [[ ! "$2" =~ ^[0-9]+(\.[0-9]+)?$ || "${height_int}" -lt 100 ]] && { echo "Error: --font-height must be a number >= 1" >&2; exit 1; }
                FONT_HEIGHT="$2"
                FONT_HEIGHT_EXPLICIT=true
                shift
                ;;
            --font-weight)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --font-weight requires a number" >&2; exit 1; }
                [[ ! "$2" =~ ^[0-9]+$ || "$2" -lt 100 || "$2" -gt 900 ]] && { echo "Error: --font-weight must be a number between 100 and 900" >&2; exit 1; }
                FONT_WEIGHT="$2"
                shift
                ;;
            --width)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --width requires a number" >&2; exit 1; }
                [[ ! "$2" =~ ^[0-9]+$ || "$2" -lt 1 ]] && { echo "Error: --width must be a number >= 1" >&2; exit 1; }
                WIDTH="$2"
                shift
                ;;
            --height)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --height requires a number" >&2; exit 1; }
                [[ ! "$2" =~ ^[0-9]+$ || "$2" -lt 1 ]] && { echo "Error: --height must be a number >= 1" >&2; exit 1; }
                HEIGHT="$2"
                shift
                ;;
            --wrap)
                WRAP=true
                ;;
            --tab-size)
                [[ $# -lt 2 || "$2" =~ ^- ]] && { echo "Error: --tab-size requires a number" >&2; exit 1; }
                [[ ! "$2" =~ ^[0-9]+$ || "$2" -lt 1 || "$2" -gt 16 ]] && { echo "Error: --tab-size must be a number between 1 and 16" >&2; exit 1; }
                TAB_SIZE="$2"
                shift
                ;;
            --debug)
                DEBUG=true
                ;;
            --border)
                shift
                BORDER_ARGS=()
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    BORDER_ARGS+=("$1")
                    shift
                done
                MULTI_ARGS[border]="${BORDER_ARGS[*]}"
                continue
                ;;
            -*)
                echo "Error: Unknown option '$1'" >&2
                echo "Use -h or --help for usage information" >&2
                exit 1
                ;;
            *)
                echo "Error: Unexpected argument '$1'" >&2
                echo "Use -h or --help for usage information" >&2
                exit 1
                ;;
        esac
        shift
    done
}

generate_config_hash() {
    local config_hash
    local cksum_result
    local config_string="${FONT_FAMILY}|${FONT_SIZE}|${FONT_WIDTH}|${FONT_HEIGHT}|${FONT_WEIGHT}|${WIDTH}|${HEIGHT}|${WRAP}|${TAB_SIZE}|${BG_COLOR}|${TEXT_COLOR}|${PADDING}"
    [[ "${DEBUG}" == true ]] && log_output "Config string for hashing: ${config_string}"
    cksum_result=$(echo -n "${config_string}" | cksum)
    config_hash=$(echo "${cksum_result}" | cut -d' ' -f1)
    [[ "${DEBUG}" == true ]] && log_output "Generated config hash: ${config_hash}"
    echo "${config_hash}"
}

get_cache_key() {
    local line_hash="$1"
    local config_hash="$2"
    local cache_key="${config_hash}_${line_hash}"
    [[ "${DEBUG}" == true ]] && log_output "Generated cache key: ${cache_key} (config: ${config_hash}, line: ${line_hash})"
    echo "${cache_key}"
}

save_line_cache() {
    local cache_key="$1"
    local segments_data="$2"
    local visible_length="$3"
    local cache_file="${CACHE_DIR}/${cache_key}.json"
    local json_content
    local formatted_segments timestamp
    [[ "${DEBUG}" == true ]] && log_output "Saving cache for key: ${cache_key}"
    formatted_segments=$(echo "${segments_data}" | sed 's/^/    "/' | sed 's/$/",/' | sed '$s/,$//' || true)
    timestamp=$(date +%s || true)
    json_content=$(cat << JSON_EOF
{
  "cache_key": "${cache_key}",
  "visible_length": ${visible_length},
  "segments": [
${formatted_segments}
  ],
  "timestamp": ${timestamp}
}
JSON_EOF
)
    echo "${json_content}" > "${cache_file}" 2>/dev/null || {
        [[ "${DEBUG}" == true ]] && log_output "Failed to write cache file: ${cache_file}"
        return 1
    }
    [[ "${DEBUG}" == true ]] && log_output "Cache saved to: ${cache_file}"
    return 0
}

load_line_cache() {
    local cache_key="$1"
    local cache_file="${CACHE_DIR}/${cache_key}.json"
    local segments_json visible_length
    [[ "${DEBUG}" == true ]] && log_output "Looking for cache key: ${cache_key}"
    if [[ ! -f "${cache_file}" ]]; then
        [[ "${DEBUG}" == true ]] && log_output "Cache miss: ${cache_file}"
        CACHE_STATS_SEGMENT_MISSES=$((CACHE_STATS_SEGMENT_MISSES + 1))
        return 1
    fi
    [[ "${DEBUG}" == true ]] && log_output "Cache hit: ${cache_file}"
    CACHE_STATS_SEGMENT_HITS=$((CACHE_STATS_SEGMENT_HITS + 1))
    visible_length=$(grep '"visible_length"' "${cache_file}" | sed 's/.*: *\([0-9]*\).*/\1/')
    segments_json=$(sed -n '/  "segments": \[/,/  \]/p' "${cache_file}" | sed '1d;$d' | sed 's/^ *"//;s/",$//;s/"$//')
    if [[ -z "${segments_json}" ]]; then
        [[ "${DEBUG}" == true ]] && log_output "Cache file corrupted or empty: ${cache_file}"
        return 1
    fi
    LINE_SEGMENTS=()
    while IFS= read -r segment; do
        [[ -n "${segment}" ]] && LINE_SEGMENTS+=("${segment}")
    done <<< "${segments_json}"
    CACHED_VISIBLE_LENGTH="${visible_length}"
    [[ "${DEBUG}" == true ]] && log_output "Cache loaded: ${#LINE_SEGMENTS[@]} segments, visible length: ${visible_length}"
    return 0
}

get_svg_fragment_cache_key() {
    local line_hash="$1"
    local config_hash="$2"
    local line_number="$3"
    echo "svg_${config_hash}_${line_number}_${line_hash}"
}

save_svg_fragment_cache() {
    local cache_key="$1"
    local svg_fragment="$2"
    local cache_file="${SVG_CACHE_DIR}/${cache_key}.svg"
    [[ "${DEBUG}" == true ]] && log_output "Saving SVG fragment cache: ${cache_key}"
    echo "${svg_fragment}" > "${cache_file}" 2>/dev/null || {
        [[ "${DEBUG}" == true ]] && log_output "Failed to write SVG fragment cache: ${cache_file}"
        return 1
    }
    return 0
}

load_svg_fragment_cache() {
    local cache_key="$1"
    local cache_file="${SVG_CACHE_DIR}/${cache_key}.svg"
    [[ "${DEBUG}" == true ]] && log_output "Looking for SVG fragment cache: ${cache_key}"
    if [[ ! -f "${cache_file}" ]]; then
        [[ "${DEBUG}" == true ]] && log_output "SVG fragment cache miss: ${cache_file}"
        CACHE_STATS_SVG_MISSES=$((CACHE_STATS_SVG_MISSES + 1))
        return 1
    fi
    [[ "${DEBUG}" == true ]] && log_output "SVG fragment cache hit: ${cache_file}"
    CACHE_STATS_SVG_HITS=$((CACHE_STATS_SVG_HITS + 1))
    cat "${cache_file}" 2>/dev/null || {
        [[ "${DEBUG}" == true ]] && log_output "Failed to read SVG fragment cache: ${cache_file}"
        return 1
    }
    return 0
}

generate_global_input_hash() {
    local cksum_result
    local combined_hashes=""
    for hash in "${HASH_CACHE[@]}"; do
        combined_hashes+="${hash}"
    done
    cksum_result=$(echo -n "${combined_hashes}" | cksum)
    GLOBAL_INPUT_HASH=$(echo "${cksum_result}" | cut -d' ' -f1)
    [[ "${DEBUG}" == true ]] && log_output "Generated global input hash: ${GLOBAL_INPUT_HASH}"
}

load_incremental_cache() {
    if [[ ! -f "${INCREMENTAL_CACHE_FILE}" ]]; then
        [[ "${DEBUG}" == true ]] && log_output "No incremental cache found"
        return 1
    fi
    PREVIOUS_INPUT_HASH=$(grep '"global_input_hash"' "${INCREMENTAL_CACHE_FILE}" 2>/dev/null | sed 's/.*: *"\([^"]*\)".*/\1/' || echo "")
    [[ "${DEBUG}" == true ]] && log_output "Loaded previous input hash: ${PREVIOUS_INPUT_HASH}"
    INPUT_HASH_CACHE=()
    local prev_hashes
    prev_hashes=$(sed -n '/  "line_hashes": \[/,/  \]/p' "${INCREMENTAL_CACHE_FILE}" 2>/dev/null | sed '1d;$d' | sed 's/^ *"//;s/",$//;s/"$//' || echo "")
    if [[ -n "${prev_hashes}" ]]; then
        while IFS= read -r hash; do
            [[ -n "${hash}" ]] && INPUT_HASH_CACHE+=("${hash}")
        done <<< "${prev_hashes}"
    fi
    [[ "${DEBUG}" == true ]] && log_output "Loaded ${#INPUT_HASH_CACHE[@]} previous line hashes"
    return 0
}

save_incremental_cache() {
    local config_hash="$1"
    local json_content
    local formatted_hashes timestamp
    [[ "${DEBUG}" == true ]] && log_output "Saving incremental cache data"
    formatted_hashes=$(printf '%s\n' "${HASH_CACHE[@]}" | sed 's/^/    "/' | sed 's/$/",/' | sed '$s/,$//' || true)
    timestamp=$(date +%s || true)
    json_content=$(cat << JSON_EOF
{
  "global_input_hash": "${GLOBAL_INPUT_HASH}",
  "config_hash": "${config_hash}",
  "line_count": ${#INPUT_LINES[@]},
  "line_hashes": [
${formatted_hashes}
  ],
  "timestamp": ${timestamp},
  "cache_stats": {
    "segment_hits": ${CACHE_STATS_SEGMENT_HITS},
    "segment_misses": ${CACHE_STATS_SEGMENT_MISSES},
    "svg_hits": ${CACHE_STATS_SVG_HITS},
    "svg_misses": ${CACHE_STATS_SVG_MISSES}
  }
}
JSON_EOF
)
    echo "${json_content}" > "${INCREMENTAL_CACHE_FILE}" 2>/dev/null || {
        [[ "${DEBUG}" == true ]] && log_output "Failed to write incremental cache file"
        return 1
    }
    return 0
}

detect_changed_lines() {
    local -a changed_lines=()
    if [[ -z "${INPUT_HASH_CACHE+x}" ]]; then
        INPUT_HASH_CACHE=()
    fi
    if [[ ${#INPUT_HASH_CACHE[@]} -ne ${#HASH_CACHE[@]} ]]; then
        log_output "Line count changed (${#INPUT_HASH_CACHE[@]} → ${#HASH_CACHE[@]}), processing all lines"
        for i in "${!HASH_CACHE[@]}"; do
            changed_lines+=("${i}")
        done
    else
        for i in "${!HASH_CACHE[@]}"; do
            if [[ "${HASH_CACHE[i]}" != "${INPUT_HASH_CACHE[i]:-}" ]]; then
                changed_lines+=("${i}")
                [[ "${DEBUG}" == true ]] && log_output "Line ${i} changed: ${INPUT_HASH_CACHE[i]:-none} → ${HASH_CACHE[i]}"
            fi
        done
    fi
    printf '%s\n' "${changed_lines[@]}"
}

xml_escape_url() {
    local input="$1"
    input="${input//&/&amp;}"
    echo "${input}"
}

build_font_css() {
    local font="$1"
    local css_family="'${font}'"
    local css=""
    if [[ -n "${GOOGLE_FONTS[${font}]:-}" ]]; then
        local escaped_url
        escaped_url=$(xml_escape_url "${GOOGLE_FONTS[${font}]}")
        css="@import url('${escaped_url}');"
    fi
    css_family="${css_family}, 'Consolas', 'Monaco', 'Courier New', monospace"
    css="${css} .terminal-text { font-family: ${css_family};"
    [[ "${FONT_WEIGHT}" != 400 ]] && css="${css} font-weight: ${FONT_WEIGHT};"
    css="${css} }"
    echo "${css}"
}

validate_svg_output() {
    local svg_content="$1"
    local temp_file="${CACHE_DIR}/temp_validation.svg"
    local validation_result=0
    log_output "SVG validation started"
    echo "${svg_content}" > "${temp_file}"
    xmllint --noout "${temp_file}" 2>/dev/null
    local xmllint_result=$?
    if [[ "${xmllint_result}" -ne 0 ]]; then
        log_output "SVG validation failed: Not well-formed XML"
        validation_result=1
    else
        log_output "SVG validation passed: Well-formed XML"
    fi
    if [[ "${validation_result}" == 0 ]]; then
        # Try validating against SVG 1.1 DTD (will work if network available)
        if xmllint --valid --noout "${temp_file}" 2>/dev/null; then
            [[ "${DEBUG}" == true ]] && log_output "SVG validation passed: Valid against DTD"
        else
            # DTD validation failed (likely no network or DTD not found), but XML is well-formed
            [[ "${DEBUG}" == true ]] && log_output "SVG validation: DTD validation unavailable"
        fi
    fi
    rm -f "${temp_file}" 2>/dev/null || true
    return "${validation_result}"
}

xml_escape() {
    local input="$1"
    # Must escape ampersands first, then other entities
    input=${input//\&/\&amp;}
    input=${input//</\&lt;}
    input=${input//>/\&gt;}
    input=${input//\"/\&quot;}
    local sq="'"
    input=${input//${sq}/\&apos;}
    echo "${input}"
}

parse_ansi_line() {
    local line="$1"
    local line_hash="$2"
    local config_hash="$3"
    if [[ -n "${line_hash}" && -n "${config_hash}" ]]; then
        local cache_key
        cache_key=$(get_cache_key "${line_hash}" "${config_hash}")
        # shellcheck disable=SC2310 # Not anticipating failures here
        if load_line_cache "${cache_key}"; then
            [[ "${DEBUG}" == true ]] && log_output "Cache hit for line: ${line:0:50}..."
            return 0  # LINE_SEGMENTS and CACHED_VISIBLE_LENGTH are set by load_line_cache
        fi
        [[ "${DEBUG}" == true ]] && log_output "Cache miss for line: ${line:0:50}..."
    fi
    
    local segments=()
    local fg="${TEXT_COLOR}" bg="" bold="false"
    local visible_column=0
    local remaining_line="${line}"
    [[ "${DEBUG}" == true ]] && log_output "Parsing line (${#line} chars): ${line}" | cat -v
    
    while [[ -n "${remaining_line}" ]]; do
        # Check if line starts with ANSI escape sequence
        if [[ "${remaining_line}" =~ ^${ANSI_COLOR_PATTERN} ]]; then
            local ansi_match="${BASH_REMATCH[0]}"
            local ansi_length=${#ansi_match}
            local codes_string="${ansi_match:2:$((ansi_length-3))}"
            [[ "${DEBUG}" == true ]] && log_output "  Processing ANSI sequence: ${codes_string}"
            if [[ -z "${codes_string}" || "${codes_string}" == "0" ]]; then
                # Reset sequence
                fg="${TEXT_COLOR}"; bg=""; bold="false"
                [[ "${DEBUG}" == true ]] && log_output "    Reset styling"
            else
                # Process semicolon-separated codes
                IFS=";" read -ra codes <<< "${codes_string}"
                for code in "${codes[@]}"; do
                    # Remove non-digits more efficiently
                    code="${code//[^0-9]/}"
                    [[ -z "${code}" ]] && continue
                    case "${code}" in
                        1) bold="true" ;;
                        22) bold="false" ;;
                        30|31|32|33|34|35|36|37|90|91|92|93|94|95|96|97)
                            fg="${ANSI_COLORS[${code}]:-${fg}}" ;;
                        4[0-7]|10[0-7])
                            local bg_code=$((code - 10))
                            bg="${ANSI_COLORS[${bg_code}]:-}" ;;
                        0) fg="${TEXT_COLOR}"; bg=""; bold="false" ;;
                        *) ;;  # Ignore unknown codes
                    esac
                    [[ "${DEBUG}" == true ]] && log_output "    Code ${code}: fg=${fg}, bg=${bg}, bold=${bold}"
                done
            fi
            remaining_line="${remaining_line:${ansi_length}}"
        else
            # Find next ANSI sequence or end of line
            local next_ansi_pos=0
            local text_chunk=""
            if [[ "${remaining_line}" =~ ${ANSI_COLOR_PATTERN} ]]; then
                next_ansi_pos="${#remaining_line}"
                for ((j=0; j<${#remaining_line}; j++)); do
                    if [[ "${remaining_line:j}" =~ ^${ANSI_COLOR_PATTERN} ]]; then
                        next_ansi_pos=${j}
                        break
                    fi
                done
                text_chunk="${remaining_line:0:${next_ansi_pos}}"
                remaining_line="${remaining_line:${next_ansi_pos}}"
            else
                # No more ANSI sequences, take rest of line
                text_chunk="${remaining_line}"
                remaining_line=""
            fi
            if [[ -n "${text_chunk}" ]]; then
                [[ "${DEBUG}" == true ]] && log_output "  Emitting segment: \"${text_chunk}\" (${#text_chunk} chars) at column ${visible_column} (fg=${fg}, bold=${bold})"
                segments+=("$(printf '%s|%s|%s|%s|%d' "${text_chunk}" "${fg}" "${bg}" "${bold}" "${visible_column}")")
                visible_column=$((visible_column + ${#text_chunk}))
                [[ "${DEBUG}" == true ]] && log_output "  Updated visible_column to ${visible_column}"
            fi
        fi
    done
    
    LINE_SEGMENTS=("${segments[@]}")
    if [[ -n "${line_hash}" && -n "${config_hash}" ]]; then
        local visible_length=${visible_column}  # Use accumulated visible_column
        local cache_key
        cache_key=$(get_cache_key "${line_hash}" "${config_hash}")
        local segments_data=""
        for segment in "${LINE_SEGMENTS[@]}"; do
            segments_data+="${segment}"$'\n'
        done
        segments_data="${segments_data%$'\n'}"  # Remove trailing newline
        save_line_cache "${cache_key}" "${segments_data}" "${visible_length}"
    fi
}

get_visible_line_length() {
    local line="$1"
    local line_hash="$2"
    local config_hash="$3"
    local total_chars=0
    parse_ansi_line "${line}" "${line_hash}" "${config_hash}"
    if [[ -n "${CACHED_VISIBLE_LENGTH:-}" ]]; then
        echo "${CACHED_VISIBLE_LENGTH}"
        unset CACHED_VISIBLE_LENGTH  # Clean up
        return
    fi
    for segment in "${LINE_SEGMENTS[@]}"; do
        IFS='|' read -r text fg bg bold _ <<< "${segment}"
        total_chars=$((total_chars + ${#text}))
    done
    echo "${total_chars}"
}

read_input() {
    local input_source
    log_output "Reading source input"
    if [[ -n "${INPUT_FILE}" ]]; then
        [[ ! -f "${INPUT_FILE}" ]] && { echo "Error: Input file '${INPUT_FILE}' not found" >&2; exit 1; }
        input_source="${INPUT_FILE}"
    else
        input_source="/dev/stdin"
    fi
    local tab_spaces
    printf -v tab_spaces '%*s' "${TAB_SIZE}" ''
    tab_spaces=${tab_spaces// / }
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line//$'\t'/${tab_spaces}}"
        INPUT_LINES+=("${line}")
    done < "${input_source}"
    log_output "Read ${#INPUT_LINES[@]} lines from ${input_source}"
    if [[ ${#INPUT_LINES[@]} -eq 0 ]]; then
        echo "Error: No input provided" >&2
        exit 1
    fi
    if [[ "${HEIGHT}" -gt 0 && "${#INPUT_LINES[@]}" -gt "${HEIGHT}" ]]; then
        INPUT_LINES=("${INPUT_LINES[@]:0:${HEIGHT}}")
        [[ "${DEBUG}" == true ]] && log_output "Truncated to ${HEIGHT} lines"
    fi
    if [[ "${WRAP}" == true ]]; then
        local wrapped_lines=()
        for line in "${INPUT_LINES[@]}"; do
            if [[ "${#line}" -gt "${WIDTH}" ]]; then
                echo "${line}" | fold -w "${WIDTH}" | while IFS= read -r wrapped_line; do
                    wrapped_lines+=("${wrapped_line}")
                done
            else
                wrapped_lines+=("${line}")
            fi
        done
        INPUT_LINES=("${wrapped_lines[@]}")
    fi
    log_output "Hashing ${#INPUT_LINES[@]} lines after wrapping/truncation"
    [[ "${HEIGHT}" == 0 ]] && HEIGHT="${#INPUT_LINES[@]}"
    start_hash_time=$(date +%s.%N)
    for line in "${INPUT_LINES[@]}"; do
        local line_hash cksum_result
        cksum_result=$(echo -n "${line}" | cksum)
        line_hash=$(echo "${cksum_result}" | cut -d' ' -f1)
        HASH_CACHE+=("${line_hash}")
    done
    end_hash_time=$(date +%s.%N)
    elapsed_hash_time=$(awk "BEGIN {printf \"%.6f\", ${end_hash_time} - ${start_hash_time}}")
    num_hash_lines=${#INPUT_LINES[@]}
    if (( num_hash_lines > 0 )); then
        hash_time_per_line=$(awk "BEGIN {printf \"%.6f\", ${elapsed_hash_time} / ${num_hash_lines}}")
    else
        hash_time_per_line=0
    fi
    elapsed_hash_time_formatted=$(printf "%.3f" "${elapsed_hash_time}")
    hash_time_per_line_formatted=$(printf "%.3f" "${hash_time_per_line}")
    log_output "Hash time: ${elapsed_hash_time_formatted}s, Time per line: ${hash_time_per_line_formatted}s"
    log_output "Processing ${num_hash_lines} lines"
}

process_lines_single_pass() {
    local -a changed_lines
    local temp_output
    local max_width=0
    local char_count
    local max_auto_width=120  # Maximum auto-detected width
    local longest_line_index=-1
    local svg_fragments=()
    local config_hash
    declare -a all_line_segments  # Store parsed segments for each line to avoid re-parsing

    config_hash=$(generate_config_hash)
    [[ "${DEBUG}" == true ]] && log_output "Using config hash for enhanced processing: ${config_hash}"
    generate_global_input_hash
    load_incremental_cache || true
    
    # shellcheck disable=SC2310 # Not anticipating failures here
    temp_output=$(detect_changed_lines) || true
    mapfile -t changed_lines <<< "${temp_output}"
    if [[ "${GLOBAL_INPUT_HASH}" == "${PREVIOUS_INPUT_HASH}" ]]; then
        log_output "Input unchanged from previous run - full cache utilization possible"
    elif [[ ${#changed_lines[@]} -eq ${#INPUT_LINES[@]} ]]; then
        log_output "First run or major changes - processing all ${#INPUT_LINES[@]} lines"
    else
        log_output "Incremental processing: ${#changed_lines[@]} of ${#INPUT_LINES[@]} lines changed"
        [[ "${DEBUG}" == true ]] && log_output "Changed lines: ${changed_lines[*]}"
    fi
   
    log_output "Starting enhanced single-pass processing for ${#INPUT_LINES[@]} lines"
    for i in "${!INPUT_LINES[@]}"; do
        local line="${INPUT_LINES[i]}"
        local line_hash="${HASH_CACHE[i]}"
        parse_ansi_line "${line}" "${line_hash}" "${config_hash}"
        if [[ -n "${CACHED_VISIBLE_LENGTH:-}" ]]; then
            char_count="${CACHED_VISIBLE_LENGTH}"
            unset CACHED_VISIBLE_LENGTH
        else
            char_count=0
            for segment in "${LINE_SEGMENTS[@]}"; do
                IFS='|' read -r text _ _ _ _ <<< "${segment}"
                char_count=$((char_count + ${#text}))
            done
        fi
        local segments_joined=""
        for segment in "${LINE_SEGMENTS[@]}"; do
            segments_joined+="${segment}"$'\x1F'  # Use ASCII unit separator
        done
        all_line_segments[i]="${segments_joined%$'\x1F'}"  # Remove trailing delimiter
        if [[ ${char_count} -gt ${max_width} ]]; then
            max_width=${char_count}
            longest_line_index=${i}
        fi
        [[ "${DEBUG}" == true ]] && log_output "Line ${i}: ${char_count} visible chars, ${#LINE_SEGMENTS[@]} segments stored"
    done
    
    log_output "Content analysis: longest line is ${max_width} characters (line $((longest_line_index + 1)))" 
    [[ "${DEBUG}" == true ]] && log_output "  Longest line content: \"${INPUT_LINES[longest_line_index]:0:50}...\""
    if [[ "${WIDTH}" == 80 && ${max_width} -gt 80 ]]; then
        if [[ ${max_width} -gt ${max_auto_width} ]]; then
            GRID_WIDTH="${max_auto_width}"
            log_output "Auto-detected width limited to ${max_auto_width} characters (content: ${max_width} chars)" 
            log_output "  Use --width ${max_width} to display full content width" 
        else
            GRID_WIDTH="${max_width}"
            log_output "Auto-detected width: ${max_width} characters" 
        fi
    else
        GRID_WIDTH="${WIDTH}"
        log_output "Using specified width: ${WIDTH} characters" 
        if [[ "${WRAP}" == false && ${max_width} -gt ${WIDTH} ]]; then
            log_output "Warning: Lines exceed width ${WIDTH} (max: ${max_width}), will clip" 
        fi
    fi
    GRID_HEIGHT="${HEIGHT}"
    [[ "${GRID_WIDTH}" -lt 1 ]] && GRID_WIDTH=1
    [[ "${GRID_HEIGHT}" -lt 1 ]] && GRID_HEIGHT=1
    SVG_WIDTH_INT=$(( (2 * PADDING * 100) + (GRID_WIDTH * FONT_WIDTH_INT) ))
    SVG_HEIGHT_INT=$(( (2 * PADDING * 100) + (GRID_HEIGHT * FONT_HEIGHT_INT) ))
    SVG_WIDTH=$(int_to_decimal "${SVG_WIDTH_INT}")
    SVG_HEIGHT=$(int_to_decimal "${SVG_HEIGHT_INT}")
    log_output "SVG dimensions: ${SVG_WIDTH}x${SVG_HEIGHT} (${GRID_HEIGHT} lines, grid width: ${GRID_WIDTH} chars)" 
    log_output "Font: ${FONT_FAMILY} ${FONT_SIZE}px (char width: ${FONT_WIDTH}, line height: ${FONT_HEIGHT}, weight: ${FONT_WEIGHT})" 
    
    CELL_WIDTH_INT=$(( (SVG_WIDTH_INT - 2 * PADDING * 100) / GRID_WIDTH ))
    local cell_width
    cell_width=$(int_to_decimal "${CELL_WIDTH_INT}")
    [[ "${DEBUG}" == true ]] && log_output "Cell width: ${cell_width} pixels (${CELL_WIDTH_INT}/100)"
    log_output "Generating SVG fragments with enhanced caching"
    for i in "${!INPUT_LINES[@]}"; do
        [[ ${i} -ge ${GRID_HEIGHT} ]] && { [[ "${DEBUG}" == true ]] && log_output "Skipping line ${i} (exceeds grid height ${GRID_HEIGHT})"; break; }
        local line_hash="${HASH_CACHE[i]}"
        local svg_fragment_cache_key
        svg_fragment_cache_key=$(get_svg_fragment_cache_key "${line_hash}" "${config_hash}" "${i}")
        local cached_fragment
        # shellcheck disable=SC2310 # Not anticipating failures here
        if cached_fragment=$(load_svg_fragment_cache "${svg_fragment_cache_key}"); then
            # Use cached SVG fragment
            svg_fragments+=("${cached_fragment}")
            [[ "${DEBUG}" == true ]] && log_output "Using cached SVG fragment for line ${i}"
            continue
        fi
        [[ "${DEBUG}" == true ]] && log_output "Generating new SVG fragment for line ${i}"
        local stored_segments="${all_line_segments[i]}"
        [[ -z "${stored_segments}" ]] && continue
        local fragments=""
        local y_offset_int=$(( (PADDING * 100) + (FONT_SIZE * 100) + (i * FONT_HEIGHT_INT) ))
        local y_offset
        y_offset=$(int_to_decimal "${y_offset_int}")
        # Split stored segments and process each one
        IFS=$'\x1F' read -ra stored_segments_array <<< "${stored_segments}"
        for segment in "${stored_segments_array[@]}"; do
            [[ -z "${segment}" ]] && continue
            IFS='|' read -r text fg bg bold visible_pos <<< "${segment}"
            if [[ -n "${text}" ]]; then
                # Clip text if it exceeds grid width
                local max_chars=$((GRID_WIDTH - visible_pos))
                if [[ ${max_chars} -le 0 ]]; then
                    [[ "${DEBUG}" == true ]] && log_output "  Skipping text at col ${visible_pos} (exceeds grid width ${GRID_WIDTH})"
                    continue
                fi
                if [[ ${#text} -gt ${max_chars} ]]; then
                    [[ "${DEBUG}" == true ]] && log_output "  Clipping text at col ${visible_pos}: '${text:0:20}'... to ${max_chars} chars"
                    text="${text:0:${max_chars}}"
                fi
                [[ -z "${text}" ]] && continue
                local escaped_text
                escaped_text=$(xml_escape "${text}")
                # Calculate positioning using integer arithmetic (Phase 4 optimization)
                local current_x_int=$(( (PADDING * 100) + (visible_pos * CELL_WIDTH_INT) ))
                local text_width_int=$(( ${#text} * CELL_WIDTH_INT ))
                local current_x text_width
                current_x=$(int_to_decimal "${current_x_int}")
                text_width=$(int_to_decimal "${text_width_int}")
                [[ "${DEBUG}" == true ]] && log_output "  Placing text at x=${current_x} (col ${visible_pos}): \"${text:0:20}\"..." "(${#text} chars)"
                local style_attrs="fill=\"${fg}\""
                [[ "${bold}" == "true" ]] && style_attrs+=" font-weight=\"bold\""
                if [[ -n "${bg}" ]]; then
                    # Calculate background rectangle coordinates using integer arithmetic
                    local bg_y_int=$(( y_offset_int - (FONT_SIZE * 100) + 200 ))  # +2 pixels = +200 in scaled units
                    local bg_height_int=$(( FONT_SIZE * 100 + 200 ))              # font_size + 2 pixels
                    local bg_y bg_height
                    bg_y=$(int_to_decimal "${bg_y_int}")
                    bg_height=$(int_to_decimal "${bg_height_int}")
                    fragments+="    <rect x=\"${current_x}\" y=\"${bg_y}\" width=\"${text_width}\" height=\"${bg_height}\" fill=\"${bg}\"/>"$'\n'
                fi
                fragments+="    <text x=\"${current_x}\" y=\"${y_offset}\" font-size=\"${FONT_SIZE}\" class=\"terminal-text\" xml:space=\"preserve\" textLength=\"${text_width}\" lengthAdjust=\"spacingAndGlyphs\" ${style_attrs}>${escaped_text}</text>"$'\n'
            fi
        done
        save_svg_fragment_cache "${svg_fragment_cache_key}" "${fragments}"
        svg_fragments+=("${fragments}")
    done
    save_incremental_cache "${config_hash}"
    
    # Report enhanced cache statistics
    local segment_total=$((CACHE_STATS_SEGMENT_HITS + CACHE_STATS_SEGMENT_MISSES))
    local svg_total=$((CACHE_STATS_SVG_HITS + CACHE_STATS_SVG_MISSES))
    if [[ ${segment_total} -gt 0 || ${svg_total} -gt 0 ]]; then
        log_output "Cache statistics: Segments ${CACHE_STATS_SEGMENT_HITS}/${segment_total} hits, SVG fragments ${CACHE_STATS_SVG_HITS}/${svg_total} hits"
    fi
    
    # Assemble final SVG
    cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     width="${SVG_WIDTH}" 
     height="${SVG_HEIGHT}" 
     viewBox="0 0 ${SVG_WIDTH} ${SVG_HEIGHT}">
     
  <defs>
    <style>
$(
    # Separate build_font_css call to avoid masking return value in || condition
    local font_css_output
    # shellcheck disable=SC2310 # Not anticipating failures here
    font_css_output=$(build_font_css "${FONT_FAMILY}") || true
    echo "${font_css_output}"
) 
    </style>
  </defs>
     
  <!-- Background -->
  <rect width="100%" height="100%" fill="${BG_COLOR}" rx="6"/>
  
  <!-- Text Content -->
EOF
    # Output all generated fragments
    for fragment in "${svg_fragments[@]}"; do
        echo "${fragment}"
    done
    echo "</svg>"
}

output_svg() {
    local svg_content
    svg_content=$(process_lines_single_pass)
    validate_svg_output "${svg_content}"
    if [[ -n "${OUTPUT_FILE}" ]]; then
        echo "${svg_content}" > "${OUTPUT_FILE}"
        log_output "SVG written to: ${OUTPUT_FILE}"
    else
        echo "${svg_content}"
    fi
}

main() {
    check_for_help "$@"
    if [[ $# -eq 0 && -t 0 ]]; then
        show_help
        exit 0
    fi
    show_version
    parse_arguments "$@"
    if [[ "${FONT_WIDTH_EXPLICIT}" == false || "${FONT_HEIGHT_EXPLICIT}" == false ]]; then
        calculate_font_metrics
    fi
    if [[ "${FONT_WIDTH_EXPLICIT}" == true ]]; then
        FONT_WIDTH_INT=$(decimal_to_int "${FONT_WIDTH}")
    fi
    if [[ "${FONT_HEIGHT_EXPLICIT}" == true ]]; then
        FONT_HEIGHT_INT=$(decimal_to_int "${FONT_HEIGHT}")
    fi
    log_output "Parsed options:" 
    log_output "  Input: ${INPUT_FILE:-stdin}" 
    log_output "  Output: ${OUTPUT_FILE:-stdout}" 
    log_output "  Font: ${FONT_FAMILY} ${FONT_SIZE}px (width: ${FONT_WIDTH}, line height: ${FONT_HEIGHT}, weight: ${FONT_WEIGHT})" 
    log_output "  Grid: ${WIDTH}x${HEIGHT}" 
    log_output "  Wrap: ${WRAP}" 
    log_output "  Tab size: ${TAB_SIZE}"
    if [[ -n "${MULTI_ARGS[border]:-}" ]]; then
        echo "  Border: ${MULTI_ARGS[border]}" 
    fi
    read_input
    output_svg
    log_output "Oh.sh v${SCRIPT_VERSION} SVG generation complete! 🎯"
}

main "$@"
