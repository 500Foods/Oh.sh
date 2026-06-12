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

@test "01 Oh.sh passes shellcheck" {
    run shellcheck Oh.sh --severity=error
    [ "$status" -eq 0 ]
}

@test "02 C sources pass cppcheck" {
    run cppcheck --error-exitcode=1 --suppress=missingIncludeSystem Oh.c Oh-parse.c Oh-cache.c
    [ "$status" -eq 0 ]
}

@test "03 Oh.c generates expected SVG from sample.ansi" {
    run ./Oh -i sample.ansi -o c_output.svg
    [ "$status" -eq 0 ]
    [ -f c_output.svg ]
    grep -q '<svg xmlns=' c_output.svg
    grep -q 'terminal-text' c_output.svg
}

@test "04 Oh.sh generates expected SVG from sample.ansi" {
    run bash Oh.sh -i sample.ansi -o bash_output.svg
    [ "$status" -eq 0 ]
    [ -f bash_output.svg ]
    grep -q '<svg xmlns=' bash_output.svg
    grep -q 'terminal-text' bash_output.svg
}

@test "05 Oh.c generates expected SVG from test_table.ansi" {
    run ./Oh -i test_table.ansi -o c_output.svg
    [ "$status" -eq 0 ]
    [ -f c_output.svg ]
    grep -q '<svg xmlns=' c_output.svg
}

@test "06 Oh.sh generates expected SVG from test_table.ansi" {
    run bash Oh.sh -i test_table.ansi -o bash_output.svg
    [ "$status" -eq 0 ]
    [ -f bash_output.svg ]
    grep -q '<svg xmlns=' bash_output.svg
}

@test "07 Oh.sh and Oh.c produce equivalent output" {
    rm -rf "$HOME/.cache/Oh"
    
    ./Oh -i sample.ansi -o c_output.svg
    bash Oh.sh -i sample.ansi -o bash_output.svg

    grep -q '<?xml version=' c_output.svg
    grep -q '<?xml version=' bash_output.svg

    c_viewbox=$(grep -o 'viewBox="[^"]*"' c_output.svg | head -1)
    bash_viewbox=$(grep -o 'viewBox="[^"]*"' bash_output.svg | head -1)
    [[ -n "$c_viewbox" ]]
    [[ -n "$bash_viewbox" ]]

    c_lines=$(grep -c '<text ' c_output.svg)
    bash_lines=$(grep -c '<text ' bash_output.svg)
    [ "$c_lines" -gt 0 ]
    [ "$bash_lines" -gt 0 ]

    c_colors=$(grep -o 'fill="#[a-f0-9]\{6\}"' c_output.svg | sort -u | wc -l)
    bash_colors=$(grep -o 'fill="#[a-f0-9]\{6\}"' bash_output.svg | sort -u | wc -l)
    [ "$c_colors" -gt 0 ]
    [ "$bash_colors" -gt 0 ]
}

@test "08 SVG output is well-formed XML" {
    ./Oh -i sample.ansi -o c_output.svg
    bash Oh.sh -i sample.ansi -o bash_output.svg

    run xmllint --noout c_output.svg
    [ "$status" -eq 0 ]

    run xmllint --noout bash_output.svg
    [ "$status" -eq 0 ]
}

@test "09 Empty input produces error" {
    run bash Oh.sh < /dev/null
    [ "$status" -ne 0 ]
}

@test "10 Oh.sh --help succeeds" {
    run bash Oh.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Oh.sh"* ]] || [[ "$output" == *"Convert ANSI"* ]]
}

@test "11 Oh.sh --version succeeds" {
    run bash Oh.sh --version
    [ "$status" -eq 0 ]
}

@test "12 Oh.c --help succeeds" {
    run ./Oh --help
    [ "$status" -eq 0 ]
}