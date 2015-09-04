-include common.mk

################################################################################
# Mandatory definition to use common.mk
################################################################################
CROSS_COMPILE_NS_USER		?= "$(CCACHE)$(AARCH32_CROSS_COMPILE)"
CROSS_COMPILE_NS_KERNEL		?= "$(CCACHE)$(AARCH32_CROSS_COMPILE)"
CROSS_COMPILE_S_USER		?= "$(CCACHE)$(AARCH32_CROSS_COMPILE)"
CROSS_COMPILE_S_KERNEL		?= "$(CCACHE)$(AARCH32_CROSS_COMPILE)"
OPTEE_OS_BIN			?= $(OPTEE_OS_PATH)/out/arm-plat-vexpress/core/tee.bin
OPTEE_OS_TA_DEV_KIT_DIR		?= $(OPTEE_OS_PATH)/out/arm-plat-vexpress/export-user_ta

################################################################################
# Paths to git projects and various binaries
################################################################################
GEN_ROOTFS_PATH			?= $(ROOT)/gen_rootfs
GEN_ROOTFS_FILELIST		?= $(GEN_ROOTFS_PATH)/filelist-tee.txt

BIOS_QEMU_PATH			?= $(ROOT)/bios_qemu_tz_arm
QEMU_PATH			?= $(ROOT)/qemu

SOC_TERM_PATH			?= $(ROOT)/soc_term

DEBUG = 1

################################################################################
# Targets
################################################################################
all: bios-qemu linux optee-os optee-client optee-linuxdriver qemu soc-term xtest
all-clean: bios-qemu-clean busybox-clean linux-clean optee-os-clean \
	optee-client-clean optee-linuxdriver-clean qemu-clean soc-term-clean \
	check-clean

-include toolchain.mk

################################################################################
# QEMU
################################################################################
define bios-qemu-common
	make -C $(BIOS_QEMU_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH32_CROSS_COMPILE)" \
		O=$(ROOT)/out/bios-qemu \
		BIOS_NSEC_BLOB=$(LINUX_PATH)/arch/arm/boot/zImage \
		BIOS_NSEC_ROOTFS=$(GEN_ROOTFS_PATH)/filesystem.cpio.gz \
		BIOS_SECURE_BLOB=$(OPTEE_OS_BIN) \
		PLATFORM_FLAVOR=virt
endef

bios-qemu: linux update_rootfs optee-os
	$(call bios-qemu-common)

bios-qemu-clean:
	$(call bios-qemu-common) clean

qemu:
	cd $(QEMU_PATH); ./configure --target-list=arm-softmmu --cc="$(CCACHE)gcc"
	make -C $(QEMU_PATH) \
		-j`getconf _NPROCESSORS_ONLN`

qemu-clean:
	make -C $(QEMU_PATH) distclean

################################################################################
# Busybox
################################################################################
busybox: linux
	@if [ ! -d "$(GEN_ROOTFS_PATH)/build" ]; then \
		cd $(GEN_ROOTFS_PATH); \
			CC_DIR=$(AARCH32_PATH) \
			PATH=${PATH}:$(LINUX_PATH)/usr \
			$(GEN_ROOTFS_PATH)/generate-cpio-rootfs.sh vexpress; \
	fi

busybox-clean:
	cd $(GEN_ROOTFS_PATH); \
		$(GEN_ROOTFS_PATH)/generate-cpio-rootfs.sh vexpress clean


################################################################################
# Linux kernel
################################################################################
$(LINUX_PATH)/.config:
	# Temporary fix until we have the driver integrated in the kernel
	sed -i '/config ARM$$/a select DMA_SHARED_BUFFER' $(LINUX_PATH)/arch/arm/Kconfig;
	make -C $(LINUX_PATH) ARCH=arm vexpress_defconfig

linux-defconfig: $(LINUX_PATH)/.config

linux: linux-defconfig
	make -C $(LINUX_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH32_CROSS_COMPILE)" \
		LOCALVERSION= \
		ARCH=arm \
		-j`getconf _NPROCESSORS_ONLN`

linux-clean:
	make -C $(LINUX_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH32_CROSS_COMPILE)" \
		mrproper

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS += PLATFORM=vexpress-qemu_virt
optee-os: optee-os-common

OPTEE_OS_CLEAN_COMMON_FLAGS += PLATFORM=vexpress-qemu_virt
optee-os-clean: optee-os-clean-common

optee-client: optee-client-common

optee-client-clean: optee-client-clean-common

OPTEE_LINUXDRIVER_COMMON_FLAGS += ARCH=arm
optee-linuxdriver: optee-linuxdriver-common

OPTEE_LINUXDRIVER_CLEAN_COMMON_FLAGS += ARCH=arm
optee-linuxdriver-clean: optee-linuxdriver-clean-common

################################################################################
# Soc-term
################################################################################
soc-term:
	make -C $(SOC_TERM_PATH)

soc-term-clean:
	make -C $(SOC_TERM_PATH) clean

################################################################################
# xtest / optee_test
################################################################################
XTEST_COMMON_FLAGS += CFG_ARM32=y
xtest: xtest-common

XTEST_CLEAN_COMMON_FLAGS += CFG_ARM32=y
xtest-clean: xtest-clean-common

XTEST_PATCH_COMMON_FLAGS += CFG_ARM32=y
xtest-patch: xtest-patch-common

################################################################################
# Root FS
################################################################################
.PHONY: filelist-tee
filelist-tee:
	@echo "# xtest / optee_test" > $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -type f -name "xtest" | sed 's/\(.*\)/file \/bin\/xtest \1 755 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "# TAs" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/optee_armtz 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@find $(OPTEE_TEST_OUT_PATH) -name "*.ta" | \
		sed 's/\(.*\)\/\(.*\)/file \/lib\/optee_armtz\/\2 \1\/\2 444 0 0/g' >> $(GEN_ROOTFS_FILELIST)
	@echo "# Secure storage dig" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /data/tee 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "# OP-TEE device" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/modules 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/modules/$(call KERNEL_VERSION) 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/modules/$(call KERNEL_VERSION)/optee.ko $(OPTEE_LINUXDRIVER_PATH)/core/optee.ko 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/modules/$(call KERNEL_VERSION)/optee_armtz.ko $(OPTEE_LINUXDRIVER_PATH)/armtz/optee_armtz.ko 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "# OP-TEE Client" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /bin/tee-supplicant $(OPTEE_CLIENT_EXPORT)/bin/tee-supplicant 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "dir /lib/arm-linux-gnueabihf 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "file /lib/arm-linux-gnueabihf/libteec.so.1.0 $(OPTEE_CLIENT_EXPORT)/lib/libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/arm-linux-gnueabihf/libteec.so.1 libteec.so.1.0 755 0 0" >> $(GEN_ROOTFS_FILELIST)
	@echo "slink /lib/arm-linux-gnueabihf/libteec.so libteec.so.1 755 0 0" >> $(GEN_ROOTFS_FILELIST)

update_rootfs: busybox optee-client optee-linuxdriver xtest filelist-tee
	cat $(GEN_ROOTFS_PATH)/filelist-final.txt $(GEN_ROOTFS_PATH)/filelist-tee.txt > $(GEN_ROOTFS_PATH)/filelist.tmp
	cd $(GEN_ROOTFS_PATH); \
		$(LINUX_PATH)/usr/gen_init_cpio $(GEN_ROOTFS_PATH)/filelist.tmp | gzip > $(GEN_ROOTFS_PATH)/filesystem.cpio.gz

################################################################################
# Run targets
################################################################################
define run-help
	@echo "Run QEMU"
	@echo QEMU is now waiting to start the execution
	@echo Start execution with either a \'c\' followed by \<enter\> in the QEMU console or
	@echo attach a debugger and continue from there.
	@echo
	@echo To run xtest paste the following on the serial 0 prompt
	@echo modprobe optee_armtz
	@echo sleep 0.1
	@echo tee-supplicant\&
	@echo sleep 0.1
	@echo xtest
	@echo
	@echo To run a single test case replace the xtest command with for instance
	@echo xtest 2001
endef

.PHONY: run
# This target enforces updating root fs etc
run: all
	$(MAKE) run-only

.PHONY: run-only
run-only:
	$(call run-help)
	@gnome-terminal -e "$(BASH) -c '$(SOC_TERM_PATH)/soc_term 54320; exec /bin/bash -i'" --title="Normal world"
	@gnome-terminal -e "$(BASH) -c '$(SOC_TERM_PATH)/soc_term 54321; exec /bin/bash -i'" --title="Secure world"
	@sleep 1
	$(QEMU_PATH)/arm-softmmu/qemu-system-arm \
		-nographic \
		-serial tcp:localhost:54320 -serial tcp:localhost:54321 \
		-s -S -machine virt -cpu cortex-a15 \
		-m 1057 \
		-bios $(ROOT)/out/bios-qemu/bios.bin


ifneq ($(filter check,$(MAKECMDGOALS)),)
CHECK_DEPS := all
endif

check: $(CHECK_DEPS)
	expect qemu-check.exp -- \
		--bios $(ROOT)/out/bios-qemu/bios.bin

check-only: check

check-clean:
	rm -f serial0.log serial1.log
