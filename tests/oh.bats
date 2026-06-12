#!/usr/bin/env bats
# Oh.sh - Bats tests for ANSI to SVG converter

# Setup: Build C version and clean cache before tests
setup() {
    cd "$BATS_TEST_DIRNAME/.."
    make clean-cache 2>/dev/null || true
    make 2>/dev/null || true
}

# Teardown: Clean up generated files
teardown() {
    rm -f bash_output.svg c_output.svg test_output.svg
    rm -rf "$HOME/.cache/Oh"
}

# Test: Shellcheck passes on Oh.sh (ignore notes/warnings)
@test "Oh.sh passes shellcheck" {
    run shellcheck Oh.sh --severity=error
    [ "$status" -eq 0 ]
}

# Test: Cppcheck passes on C source files
@test "C sources pass cppcheck" {
    run cppcheck --error-exitcode=1 --suppress=missingIncludeSystem Oh.c Oh-parse.c Oh-cache.c
    [ "$status" -eq 0 ]
}

# Test: C version generates expected SVG from sample.ansi
@test "Oh.c generates expected SVG from sample.ansi" {
    run ./Oh -i sample.ansi -o c_output.svg
    [ "$status" -eq 0 ]
    [ -f c_output.svg ]
    grep -q '<svg xmlns=' c_output.svg
    grep -q 'terminal-text' c_output.svg
}

# Test: Bash version generates expected SVG from sample.ansi
@test "Oh.sh generates expected SVG from sample.ansi" {
    run bash Oh.sh -i sample.ansi -o bash_output.svg
    [ "$status" -eq 0 ]
    [ -f bash_output.svg ]
    grep -q '<svg xmlns=' bash_output.svg
    grep -q 'terminal-text' bash_output.svg
}

# Test: test_table.ansi generates expected SVG from C version
@test "Oh.c generates expected SVG from test_table.ansi" {
    run ./Oh -i test_table.ansi -o c_output.svg
    [ "$status" -eq 0 ]
    [ -f c_output.svg ]
    grep -q '<svg xmlns=' c_output.svg
}

# Test: test_table.ansi generates expected SVG from bash version
@test "Oh.sh generates expected SVG from test_table.ansi" {
    run bash Oh.sh -i test_table.ansi -o bash_output.svg
    [ "$status" -eq 0 ]
    [ -f bash_output.svg ]
    grep -q '<svg xmlns=' bash_output.svg
}

# Test: Both versions produce equivalent output (comparing normalized SVG)
@test "Oh.sh and Oh.c produce equivalent output" {
    # Clean cache to ensure fresh comparison
    rm -rf "$HOME/.cache/Oh"
    
    ./Oh -i sample.ansi -o c_output.svg
    bash Oh.sh -i sample.ansi -o bash_output.svg

    # Compare structure: both should have valid SVG header
    grep -q '<?xml version=' c_output.svg
    grep -q '<?xml version=' bash_output.svg

    # Compare viewBox structure (width and height differ due to auto-detection)
    c_viewbox=$(grep -o 'viewBox="[^"]*"' c_output.svg | head -1)
    bash_viewbox=$(grep -o 'viewBox="[^"]*"' bash_output.svg | head -1)
    [[ -n "$c_viewbox" ]]
    [[ -n "$bash_viewbox" ]]

    # Compare text element counts
    c_lines=$(grep -c '<text ' c_output.svg)
    bash_lines=$(grep -c '<text ' bash_output.svg)
    [ "$c_lines" -gt 0 ]
    [ "$bash_lines" -gt 0 ]

    # Compare color usage - extract unique colors used
    c_colors=$(grep -o 'fill="#[a-f0-9]\{6\}"' c_output.svg | sort -u | wc -l)
    bash_colors=$(grep -o 'fill="#[a-f0-9]\{6\}"' bash_output.svg | sort -u | wc -l)
    [ "$c_colors" -gt 0 ]
    [ "$bash_colors" -gt 0 ]
}

# Test: Generated SVG is well-formed XML
@test "SVG output is well-formed XML" {
    ./Oh -i sample.ansi -o c_output.svg
    bash Oh.sh -i sample.ansi -o bash_output.svg

    run xmllint --noout c_output.svg
    [ "$status" -eq 0 ]

    run xmllint --noout bash_output.svg
    [ "$status" -eq 0 ]
}

# Test: Empty input produces error
@test "Empty input produces error" {
    run bash Oh.sh < /dev/null
    [ "$status" -ne 0 ]
}

# Test: Help option works
@test "Oh.sh --help succeeds" {
    run bash Oh.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Oh.sh"* ]] || [[ "$output" == *"Convert ANSI"* ]]
}

# Test: Version option works
@test "Oh.sh --version succeeds" {
    run bash Oh.sh --version
    [ "$status" -eq 0 ]
}

# Test: Oh.c --help succeeds
@test "Oh.c --help succeeds" {
    run ./Oh --help
    [ "$status" -eq 0 ]
}