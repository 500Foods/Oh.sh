# Makefile for Oh.c - ANSI to SVG converter
# Mirrors the functionality of Oh.sh

CC = gcc
CFLAGS = -std=c99 -Wall -Wextra -O2 -D_POSIX_C_SOURCE=200809L $(shell pkg-config --cflags jansson)
LDFLAGS = -lm $(shell pkg-config --libs jansson)
TARGET = Oh
SOURCES = Oh.c Oh-parse.c Oh-cache.c
OBJECTS = $(SOURCES:.c=.o)

# Default target
all: $(TARGET)

# Build the main executable
$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) -o $(TARGET) $(OBJECTS) $(LDFLAGS)

# Build object files
%.o: %.c Oh.h
	$(CC) $(CFLAGS) -c $< -o $@

# Clean build artifacts
clean:
	rm -f $(TARGET) $(OBJECTS)

# Install to system path (optional)
install: $(TARGET)
	sudo cp $(TARGET) /usr/local/bin/

# Uninstall from system path
uninstall:
	sudo rm -f /usr/local/bin/$(TARGET)

# Debug build
debug: CFLAGS += -g -DDEBUG
debug: $(TARGET)

# Test with sample file
test: $(TARGET)
	./$(TARGET) -i sample.txt -o test_output.svg

# Compare output with bash version
compare: $(TARGET)
	./Oh.sh -i sample.txt -o bash_output.svg
	./$(TARGET) -i sample.txt -o c_output.svg
	@echo "Generated bash_output.svg and c_output.svg for comparison"

# Clean cache for fresh testing
clean-cache:
	rm -rf ~/.cache/Oh

# Help target
help:
	@echo "Available targets:"
	@echo "  all        - Build the Oh executable (default)"
	@echo "  clean      - Remove build artifacts"
	@echo "  install    - Install to /usr/local/bin"
	@echo "  uninstall  - Remove from /usr/local/bin"
	@echo "  debug      - Build with debug symbols"
	@echo "  test       - Test with sample.txt"
	@echo "  compare    - Compare C vs Bash output"
	@echo "  clean-cache- Clean cache directory"
	@echo "  help       - Show this help"

.PHONY: all clean install uninstall debug test compare clean-cache help
