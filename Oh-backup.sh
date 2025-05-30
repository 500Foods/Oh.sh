#!/bin/bash

# oh.sh - Convert ANSI terminal output to GitHub-compatible SVG
# 
# VERSION HISTORY:
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

# Version
VERSION="0.022"

# Default values
INPUT_FILE=""
OUTPUT_FILE=""
HELP=false
DEBUG=false

# SVG defaults
FONT_SIZE=14
FONT_FAMILY="Consolas"
LINE_HEIGHT=1.2
PADDING=20
BG_COLOR="#1e1e1e"
TEXT_COLOR="#ffffff"
TAB_SIZE=8  # Standard tab stop every 8 characters

# Multi-argument option storage
declare -A MULTI_ARGS

# Character width ratios for different monospace fonts (empirically tested)
declare -A FONT_CHAR_RATIOS
FONT_CHAR_RATIOS["Consolas"]=0.6
FONT_CHAR_RATIOS["Monaco"]=0.6
FONT_CHAR_RATIOS["Courier New"]=0.6
FONT_CHAR_RATIOS["Inconsolata"]=0.60
FONT_CHAR_RATIOS["JetBrains Mono"]=0.55
FONT_CHAR_RATIOS["Source Code Pro"]=0.55
FONT_CHAR_RATIOS["Fira Code"]=0.58
FONT_CHAR_RATIOS["Roboto Mono"]=0.6
FONT_CHAR_RATIOS["Ubuntu Mono"]=0.5
FONT_CHAR_RATIOS["Menlo"]=0.6

# Google Fonts that we know about (URLs will be XML-escaped)
declare -A GOOGLE_FONTS
GOOGLE_FONTS["Inconsolata"]="https://fonts.googleapis.com/css2?family=Inconsolata:wght@400;700&display=swap"
GOOGLE_FONTS["JetBrains Mono"]="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&display=swap"
GOOGLE_FONTS["Source Code Pro"]="https://fonts.googleapis.com/css2?family=Source+Code+Pro:wght@400;700&display=swap"
GOOGLE_FONTS["Fira Code"]="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;700&display=swap"
GOOGLE_FONTS["Roboto Mono"]="https://fonts.googleapis.com/css2?family=Roboto+Mono:wght@400;700&display=swap"

# ANSI color mappings (standard 16 colors)
declare -A ANSI_COLORS
ANSI_COLORS[30]="#000000"   # Black
ANSI_COLORS[31]="#cd3131"   # Red
ANSI_COLORS[32]="#0dbc79"   # Green  
ANSI_COLORS[33]="#e5e510"   # Yellow
ANSI_COLORS[34]="#2472c8"   # Blue
ANSI_COLORS[35]="#bc3fbc"   # Magenta
ANSI_COLORS[36]="#11a8cd"   # Cyan
ANSI_COLORS[37]="#e5e5e5"   # White

# Bright colors (90-97)
ANSI_COLORS[90]="#666666"   # Bright Black (Gray)
ANSI_COLORS[91]="#f14c4c"   # Bright Red
ANSI_COLORS[92]="#23d18b"   # Bright Green
ANSI_COLORS[93]="#f5f543"   # Bright Yellow
ANSI_COLORS[94]="#3b8eea"   # Bright Blue
ANSI_COLORS[95]="#d670d6"   # Bright Magenta
ANSI_COLORS[96]="#29b8db"   # Bright Cyan
ANSI_COLORS[97]="#e5e5e5"   # Bright White

show_version() {
    echo "Oh.sh - Convert ANSI terminal output to GitHub-compatible SVG" >&2
    echo "Version $VERSION" >&2
}

show_help() {
    cat >&2 << 'EOF'
Oh.sh - Convert ANSI terminal output to GitHub-compatible SVG

USAGE:
    command | oh.sh [OPTIONS] > output.svg
    oh.sh [OPTIONS] -i input.txt -o output.svg

OPTIONS:
    -h, --help              Show this help
    -i, --input FILE        Input file (default: stdin)
    -o, --output FILE       Output file (default: stdout)
    --font FAMILY           Font family (default: Consolas)
    --font-size SIZE        Font size in pixels (default: 14)
    --tab-size SIZE         Tab stop size (default: 8)
    --debug                 Enable debug output
    
PLANNED OPTIONS (coming soon):
    --background-color      Terminal background color or 'transparent'
    --line-height RATIO     Line spacing ratio (default: 1.2)
    --corner-radius PX      Border radius in pixels
    --padding PX            Padding around content
    --width CHARS           Terminal width in characters
    --border STYLE...       Border style (e.g. --border 1px solid blue)
    --no-wrap               Don't wrap long lines
    --cursor                Add blinking cursor
    --animation TYPE        Animation type (typewriter, fade-in)

SUPPORTED FONTS:
    Consolas, Monaco, Courier New (system fonts)
    Inconsolata, JetBrains Mono, Source Code Pro, 
    Fira Code, Roboto Mono (Google Fonts - embedded automatically)

EXAMPLES:
    ls --color=always -l | oh.sh > listing.svg
    git diff --color | oh.sh --font "JetBrains Mono" --font-size 16 -o diff.svg
    oh.sh --font Inconsolata --font-size 16 -i terminal-output.txt -o styled.svg

EOF
}

check_for_help() {
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            show_help
            exit 0
        fi
    done
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--input)
                if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
                    echo "Error: --input requires a filename" >&2
                    exit 1
                fi
                INPUT_FILE="$2"
                shift
                ;;
            -o|--output)
                if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
                    echo "Error: --output requires a filename" >&2
                    exit 1
                fi
                OUTPUT_FILE="$2"
                shift
                ;;
            --font)
                if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
                    echo "Error: --font requires a font family name" >&2
                    exit 1
                fi
                FONT_FAMILY="$2"
                shift
                ;;
            --font-size)
                if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
                    echo "Error: --font-size requires a number" >&2
                    exit 1
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 8 ]] || [[ "$2" -gt 72 ]]; then
                    echo "Error: --font-size must be a number between 8 and 72" >&2
                    exit 1
                fi
                FONT_SIZE="$2"
                shift
                ;;
            --tab-size)
                if [[ $# -lt 2 ]] || [[ "$2" =~ ^- ]]; then
                    echo "Error: --tab-size requires a number" >&2
                    exit 1
                fi
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]] || [[ "$2" -gt 16 ]]; then
                    echo "Error: --tab-size must be a number between 1 and 16" >&2
                    exit 1
                fi
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

get_char_width_int() {
    local font="$1"
    local size="$2"
    local ratio="${FONT_CHAR_RATIOS[$font]:-0.6}"
    echo "scale=0; $size * $ratio * 100 / 1" | bc
}

xml_escape_url() {
    local input="$1"
    input="${input//&/&amp;}"
    echo "$input"
}

build_font_css() {
    local font="$1"
    local css_family="'$font'"
    if [[ -n "${GOOGLE_FONTS[$font]:-}" ]]; then
        local escaped_url
        escaped_url=$(xml_escape_url "${GOOGLE_FONTS[$font]}")
        echo "    @import url('$escaped_url');"
        css_family="'$font'"
    fi
    css_family="$css_family, 'Consolas', 'Monaco', 'Courier New', monospace"
    echo "    .terminal-text { font-family: $css_family; }"
}

xml_escape() {
    local input="$1"
    input=${input//&/&amp;}
    input=${input//</&lt;}
    input=${input//>/&gt;}
    input=${input//\"/&quot;}
    # Use a variable to represent a single quote to avoid quoting issues
    local sq="'"
    input=${input//$sq/&apos;}
    echo "$input"
}

parse_ansi_line() {
    local line="$1"
    local segments=()
    local current_text=""
    local current_fg="$TEXT_COLOR"
    local current_bg=""
    local current_bold=false
    local i=0
    local visible_column=0
    
    [[ "$DEBUG" == true ]] && echo "Parsing line (${#line} chars): $line" | cat -v >&2
    
    while [[ $i -lt ${#line} ]]; do
        if [[ "${line:$i:1}" == $'\e' ]] && [[ "${line:$i+1:1}" == "[" ]]; then
            # Emit current text before processing ANSI codes
            if [[ -n "$current_text" ]]; then
                [[ "$DEBUG" == true ]] && echo "  Emitting segment: \"$current_text\" (${#current_text} chars) at column $visible_column (fg=$current_fg, bold=$current_bold)" >&2
                segments+=("$(printf '%s|%s|%s|%s|%d' "$current_text" "$current_fg" "$current_bg" "$current_bold" "$visible_column")")
                visible_column=$((visible_column + ${#current_text}))
                current_text=""
                [[ "$DEBUG" == true ]] && echo "  Updated visible_column to $visible_column" >&2
            fi
            
            # Process all consecutive ANSI sequences
            while [[ $i -lt ${#line} && "${line:$i:1}" == $'\e' && "${line:$i+1:1}" == "[" ]]; do
                i=$((i + 2))  # Skip ESC[
                local ansi_codes=""
                
                while [[ $i -lt ${#line} ]]; do
                    local char="${line:$i:1}"
                    ansi_codes+="$char"
                    i=$((i + 1))
                    if [[ "$char" =~ [a-zA-Z] ]]; then
                        break
                    fi
                done
                
                [[ "$DEBUG" == true ]] && echo "  ANSI codes: $ansi_codes" >&2
                
                if [[ "${ansi_codes: -1}" == "m" ]]; then
                    ansi_codes="${ansi_codes%?}"  # Remove trailing 'm'
                    IFS=";" read -ra codes <<< "$ansi_codes"
                    for code in "${codes[@]}"; do
                        code=$(echo "$code" | tr -d -c '0-9')  # Strip non-digits
                        code=$((10#$code))  # Normalize (e.g., 01 -> 1)
                        [[ "$DEBUG" == true ]] && echo "    Processing code: $code" >&2
                        if [[ -z "$code" ]] || [[ "$code" == 0 ]]; then
                            current_fg="$TEXT_COLOR"
                            current_bg=""
                            current_bold=false
                            [[ "$DEBUG" == true ]] && echo "    Reset: fg=$current_fg, bg=$current_bg, bold=$current_bold" >&2
                        elif [[ "$code" == 1 ]]; then
                            current_bold=true
                            [[ "$DEBUG" == true ]] && echo "    Set bold=$current_bold" >&2
                        elif [[ "$code" == 22 ]]; then
                            current_bold=false
                            [[ "$DEBUG" == true ]] && echo "    Unset bold=$current_bold" >&2
                        elif [[ -n "${ANSI_COLORS[$code]:-}" ]]; then
                            current_fg="${ANSI_COLORS[$code]}"
                            [[ "$DEBUG" == true ]] && echo "    Set fg=$current_fg" >&2
                        elif [[ $code -ge 40 && $code -le 47 ]]; then
                            local bg_code=$((code - 10))
                            current_bg="${ANSI_COLORS[$bg_code]:-}"
                            [[ "$DEBUG" == true ]] && echo "    Set bg=$current_bg" >&2
                        elif [[ $code -ge 100 && $code -le 107 ]]; then
                            local bg_code=$((code - 10))
                            current_bg="${ANSI_COLORS[$bg_code]:-}"
                            [[ "$DEBUG" == true ]] && echo "    Set bg=$current_bg" >&2
                        fi
                    done
                fi
            done
        else
            # Accumulate regular character
            current_text+="${line:$i:1}"
            i=$((i + 1))
        fi
    done
    
    # Emit final segment
    if [[ -n "$current_text" ]]; then
        [[ "$DEBUG" == true ]] && echo "  Emitting segment: \"$current_text\" (${#current_text} chars) at column $visible_column (fg=$current_fg, bold=$current_bold)" >&2
        segments+=("$(printf '%s|%s|%s|%s|%d' "$current_text" "$current_fg" "$current_bg" "$current_bold" "$visible_column")")
    fi
    
    LINE_SEGMENTS=("${segments[@]}")
}

get_visible_line_length() {
    local line="$1"
    local total_chars=0
    
    parse_ansi_line "$line"
    for segment in "${LINE_SEGMENTS[@]}"; do
        IFS='|' read -r text fg bg bold pos <<< "$segment"
        total_chars=$((total_chars + ${#text}))
    done
    
    echo "$total_chars"
}

read_input() {
    local -a lines=()
    
    if [[ -n "$INPUT_FILE" ]]; then
        if [[ ! -f "$INPUT_FILE" ]]; then
            echo "Error: Input file '$INPUT_FILE' not found" >&2
            exit 1
        fi
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            lines+=("$line")
        done < "$INPUT_FILE"
        
        echo "Read ${#lines[@]} lines from file: $INPUT_FILE" >&2
    else
        while IFS= read -r line || [[ -n "$line" ]]; do
            lines+=("$line")
        done
        
        echo "Read ${#lines[@]} lines from stdin" >&2
    fi
    
    INPUT_LINES=("${lines[@]}")
}

calculate_dimensions() {
    local max_width=0
    local char_count
    local line
    local char_width_int
    
    char_width_int=$(get_char_width_int "$FONT_FAMILY" "$FONT_SIZE")
    
    for line in "${INPUT_LINES[@]}"; do
        char_count=$(get_visible_line_length "$line")
        if [[ $char_count -gt $max_width ]]; then
            max_width=$char_count
        fi
    done
    
    local line_height_px=$(echo "scale=2; $FONT_SIZE * $LINE_HEIGHT" | bc)
    
    SVG_WIDTH=$(echo "scale=0; ($max_width * $char_width_int) / 100 + (2 * $PADDING)" | bc)
    SVG_HEIGHT=$(echo "scale=0; (${#INPUT_LINES[@]} * $line_height_px) + (2 * $PADDING)" | bc)
    
    echo "SVG dimensions: ${SVG_WIDTH}x${SVG_HEIGHT} (${#INPUT_LINES[@]} lines, max width: $max_width chars)" >&2
    echo "Font: $FONT_FAMILY ${FONT_SIZE}px (char width: $(echo "scale=2; $char_width_int / 100" | bc), tab size: $TAB_SIZE)" >&2
}

generate_svg() {
    local line_height_px=$(echo "scale=2; $FONT_SIZE * $LINE_HEIGHT" | bc)
    local x_offset=$PADDING
    local char_width_int
    char_width_int=$(get_char_width_int "$FONT_FAMILY" "$FONT_SIZE")
    
    cat << EOF
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" 
     width="${SVG_WIDTH}" 
     height="${SVG_HEIGHT}" 
     viewBox="0 0 ${SVG_WIDTH} ${SVG_HEIGHT}">
     
  <defs>
    <style>
$(build_font_css "$FONT_FAMILY")
    </style>
  </defs>
     
  <!-- Background -->
  <rect width="100%" height="100%" fill="${BG_COLOR}" rx="6"/>
  
  <!-- Text Content -->
EOF

    # Process each line
    for i in "${!INPUT_LINES[@]}"; do
        local line="${INPUT_LINES[i]}"
        [[ "$DEBUG" == true ]] && echo "Processing line $i: ${#line} chars" >&2
        parse_ansi_line "$line"
        
        # Calculate y position
        local y_offset=$(echo "scale=2; $PADDING + ($FONT_SIZE + ($i * $line_height_px))" | bc)
        
        # Process each segment in the line
        for segment in "${LINE_SEGMENTS[@]}"; do
            IFS='|' read -r text fg bg bold visible_pos <<< "$segment"
            
            if [[ -n "$text" ]]; then
                local escaped_text
                escaped_text=$(xml_escape "$text")
                
                # Calculate x position based on VISIBLE character position
                local current_x=$(echo "scale=2; $PADDING + ($visible_pos * $char_width_int) / 100" | bc)
                [[ "$DEBUG" == true ]] && echo "  Placing text at x=$current_x (col $visible_pos): \"${text:0:20}\"..." "(${#text} chars)" >&2
                
                # Build style attributes
                local style_attrs="fill=\"$fg\""
                if [[ "$bold" == "true" ]]; then
                    style_attrs+=" font-weight=\"bold\""
                fi
                
                # Add background if specified  
                if [[ -n "$bg" ]]; then
                    local text_width=$(echo "scale=2; ${#text} * $char_width_int / 100" | bc)
                    cat << EOF
    <rect x="$current_x" y="$(echo "scale=2; $y_offset - $FONT_SIZE + 2" | bc)" width="$text_width" height="$(echo "scale=2; $FONT_SIZE + 2" | bc)" fill="$bg"/>
EOF
                fi
                
                cat << EOF
    <text x="$current_x" y="$y_offset" font-size="$FONT_SIZE" class="terminal-text" xml:space="preserve" $style_attrs>$escaped_text</text>
EOF
            fi
        done
    done
    
    echo "</svg>"
}

output_svg() {
    local svg_content
    svg_content=$(generate_svg)
    
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$svg_content" > "$OUTPUT_FILE"
        echo "SVG written to: $OUTPUT_FILE" >&2
    else
        echo "$svg_content"
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

    echo "Parsed options:" >&2
    echo "  Input: ${INPUT_FILE:-stdin}" >&2
    echo "  Output: ${OUTPUT_FILE:-stdout}" >&2
    echo "  Font: $FONT_FAMILY ${FONT_SIZE}px" >&2
    echo "  Tab size: $TAB_SIZE" >&2

    if [[ -n "${MULTI_ARGS[border]:-}" ]]; then
        echo "  Border: ${MULTI_ARGS[border]}" >&2
    fi

    declare -a INPUT_LINES
    declare -a LINE_SEGMENTS
    read_input
    calculate_dimensions
    output_svg

    echo "Version 0.022 complete! 🎯" >&2
}

main "$@"
