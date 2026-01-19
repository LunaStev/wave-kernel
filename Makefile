# ===== Configuration =====

WAVEC      := wavec
NASM       := nasm
LD         := ld.lld
GRUB_MKISO := grub2-mkrescue

ARCH       := x86_64
BUILD_DIR  := build
ISO_DIR    := iso
KERNEL     := kernel
ISO_IMAGE  := waveos.iso

# ===== Files =====

ASM_SRC    := kernel.asm
WAVE_SRC   := kernel.wave
LINKER     := link.ld

ASM_OBJ    := $(BUILD_DIR)/kernel_asm.o
WAVE_OBJ   := $(BUILD_DIR)/kernel_wave.o
KERNEL_BIN := $(BUILD_DIR)/kernel

# ===== Targets =====

all: iso

# --- Wave → object (.o)
$(WAVE_OBJ): $(WAVE_SRC)
	@mkdir -p $(BUILD_DIR)
	@mkdir -p target
	$(WAVEC) build -o $(WAVE_SRC)
	@mv target/kernel.o $(WAVE_OBJ)

# --- ASM → object (.o)
$(ASM_OBJ): $(ASM_SRC)
	@mkdir -p $(BUILD_DIR)
	$(NASM) -f elf64 $(ASM_SRC) -o $(ASM_OBJ)

# --- Link kernel
$(KERNEL_BIN): $(ASM_OBJ) $(WAVE_OBJ) $(LINKER)
	$(LD) -m elf_x86_64 -T $(LINKER) -o $(KERNEL_BIN) $(ASM_OBJ) $(WAVE_OBJ)

# --- Build GRUB ISO
iso: $(KERNEL_BIN)
	@rm -rf $(ISO_DIR)
	@mkdir -p $(ISO_DIR)/boot/grub
	cp $(KERNEL_BIN) $(ISO_DIR)/boot/kernel
	printf 'set timeout=0\nset default=0\n\nmenuentry "WaveOS" {\n  multiboot2 /boot/kernel\n  boot\n}\n' > $(ISO_DIR)/boot/grub/grub.cfg
	$(GRUB_MKISO) -o $(ISO_IMAGE) $(ISO_DIR)

# --- Run in QEMU
run: iso
	qemu-system-x86_64 -cdrom $(ISO_IMAGE)

# --- Clean
clean:
	rm -rf $(BUILD_DIR) $(ISO_DIR) $(ISO_IMAGE) target

.PHONY: all iso run clean
