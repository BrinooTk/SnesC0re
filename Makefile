PROJECT_ROOT := $(abspath ..)
BUILD_DIR    := $(PROJECT_ROOT)/compiled
OBJ_DIR      := $(BUILD_DIR)/obj

CC      ?= gcc
OBJCOPY ?= objcopy

CFLAGS  = -Os -ffreestanding -fno-stack-protector -fno-builtin \
          -fpie -mno-red-zone -mstackrealign -fomit-frame-pointer -fcf-protection=none \
          -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables \
          -Wall -Wno-unused-function -Isrc

LDFLAGS = -T linker.ld -nostdlib -nostartfiles -static \
          -Wl,--build-id=none -Wl,--no-dynamic-linker -Wl,-z,norelro -no-pie

SNES_CORE_SRCS = $(sort $(wildcard src/snes/*.c))
SNES_SRCS = src/snes_main.c src/snes_runtime.c src/ftp.c $(SNES_CORE_SRCS)
SNES_OBJS = $(patsubst %.c,$(OBJ_DIR)/%.o,$(SNES_SRCS))

SNES_ELF = $(BUILD_DIR)/snes_emu.elf
SNES_BIN = $(BUILD_DIR)/snes_emu.bin

all: snes

snes: $(SNES_BIN)

$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(SNES_ELF): $(SNES_OBJS)
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(SNES_OBJS)

$(SNES_BIN): $(SNES_ELF)
	@mkdir -p $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $@
	@echo "Built: $@ ($$(wc -c < $@) bytes)"

clean:
	rm -rf $(OBJ_DIR) $(SNES_ELF) $(SNES_BIN)

.PHONY: all clean snes
