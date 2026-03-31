WAVEC       ?= wavec
WAVEC_REPO  ?= /mnt/hdd/Wave
WAVEC_IMAGE ?= $(WAVEC_REPO)/target/debug/wavec
WAVE_FLAGS  ?= -c
NASM        ?= nasm
LD          ?= ld.lld
GRUB_MKISO  ?= grub2-mkrescue
QEMU        ?= qemu-system-x86_64
CARGO       ?= cargo

.DEFAULT_GOAL := all

BUILD_DIR  := build
ISO_DIR    := iso
ISO_IMAGE  := waveos.iso

ASM_SRC    := src/kernel.asm
WAVE_SRC   := src/kernel.wave
WAVE_DEPS  := $(wildcard src/*.wave)
LINKER     := src/link.ld

ASM_OBJ    := $(BUILD_DIR)/kernel_asm.o
WAVE_OBJ   := $(BUILD_DIR)/kernel_wave.o
KERNEL_BIN := $(BUILD_DIR)/kernel

all: iso

check-system-wavec:
	@command -v $(WAVEC) >/dev/null || { echo "system wavec not found in PATH"; exit 1; }

wavec-image:
	$(CARGO) build --manifest-path $(WAVEC_REPO)/Cargo.toml
	@test -x $(WAVEC_IMAGE) || { echo "missing built wavec at $(WAVEC_IMAGE)"; exit 1; }

$(WAVE_OBJ): $(WAVE_DEPS)
	@mkdir -p $(BUILD_DIR) target
	$(WAVEC) build $(WAVE_SRC) -o target/kernel.o $(WAVE_FLAGS)
	@mv target/kernel.o $(WAVE_OBJ)

$(ASM_OBJ): $(ASM_SRC)
	@mkdir -p $(BUILD_DIR)
	$(NASM) -f elf64 $(ASM_SRC) -o $(ASM_OBJ)

kernel: $(ASM_OBJ) $(WAVE_OBJ) $(LINKER)
	$(LD) -m elf_x86_64 -T $(LINKER) -o $(KERNEL_BIN) $(ASM_OBJ) $(WAVE_OBJ)

iso: check-system-wavec wavec-image kernel
	@rm -rf $(ISO_DIR)
	@mkdir -p $(ISO_DIR)/boot/grub $(ISO_DIR)/boot/tools
	cp $(KERNEL_BIN) $(ISO_DIR)/boot/kernel
	cp $(WAVEC_IMAGE) $(ISO_DIR)/boot/tools/wavec
	printf 'set timeout=0\nset default=0\n\nmenuentry "WaveOS" {\n  multiboot2 /boot/kernel\n  module2 /boot/tools/wavec wavec\n  boot\n}\n' > $(ISO_DIR)/boot/grub/grub.cfg
	$(GRUB_MKISO) -o $(ISO_IMAGE) $(ISO_DIR)

nogrun: iso
	$(QEMU) -cdrom $(ISO_IMAGE) -nographic -serial mon:stdio

run: iso
	$(QEMU) -cdrom $(ISO_IMAGE) -serial stdio

clean:
	rm -rf $(BUILD_DIR) $(ISO_DIR) $(ISO_IMAGE) target *.o

.PHONY: all check-system-wavec wavec-image kernel iso nogrun run clean
