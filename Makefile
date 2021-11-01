VENDOR := $(CURDIR)/vendor
VERSION := $(shell date +%Y.%m.%d)
GPGKEY := '4AA4767BBC9C4B1D18AE28B77F2D434B9741E8AC'
GPGSENDER:= 'Pierre Schmitz <pierre@archlinux.de>'

all: build create-signatures create-torrent show-info

clean:
	git clean -xdf -e .idea -e codesign.crt -e codesign.key

build:
	$(eval TMPDIR := $(shell mktemp -d))
	sudo mkarchiso \
		-c "$(CURDIR)/codesign.crt $(CURDIR)/codesign.key" \
		-m 'iso netboot bootstrap' \
		-w "$(TMPDIR)" \
		-o "$(CURDIR)" \
		/usr/share/archiso/configs/releng/ \

	sudo rm -rf "$(TMPDIR)"
	sudo rm -f arch/boot/memtest && sudo rm -rf arch/boot/licenses/memtest86+
	@echo "Set owner of generated files"
	sudo chown -R $$(id -u):$$(id -g) arch archlinux-*

create-signatures:
	for f in "archlinux-$(VERSION)-x86_64.iso" "archlinux-bootstrap-$(VERSION)-x86_64.tar.gz"; do \
		gpg --use-agent --sender $(GPGSENDER) --local-user $(GPGKEY) --detach-sign "$$f"; \
	done
	sha1sum "archlinux-$(VERSION)-x86_64.iso" "archlinux-bootstrap-$(VERSION)-x86_64.tar.gz" > sha1sums.txt
	md5sum "archlinux-$(VERSION)-x86_64.iso" "archlinux-bootstrap-$(VERSION)-x86_64.tar.gz" > md5sums.txt

create-torrent:
	$(VENDOR)/archlinux-torrent-utils/mktorrent-archlinux "$(VERSION)" "archlinux-$(VERSION)-x86_64.iso"

upload-release:
	rsync -cah --progress \
		"archlinux-$(VERSION)-x86_64.iso"* md5sums.txt sha1sums.txt arch "archlinux-bootstrap-$(VERSION)-x86_64.tar.gz"* \
		-e ssh repos.archlinux.org:tmp/

show-info:
	@file arch/boot/x86_64/vmlinuz-* | grep -P -o 'version [^-]*'
	@grep "archlinux-$(VERSION)-x86_64.iso" sha1sums.txt
	@grep "archlinux-$(VERSION)-x86_64.iso" md5sums.txt
	@echo GPG Fingerprint: ${GPGKEY}
	@echo GPG Signer: ${GPGSENDER}

copy-torrent:
	base64 "archlinux-$(VERSION)-x86_64.iso.torrent" | xclip

run-iso:
	qemu-system-x86_64 -boot d -m 4G -enable-kvm -device intel-hda -device hda-duplex -smp cores=2,threads=2 -cdrom "archlinux-$(VERSION)-x86_64.iso"

check-mirrors:
	@GODEBUG=netdns=go go run checkMirrors/main.go

.PHONY: all clean build create-signatures create-torrent upload-release show-info copy-torrent run-iso check-mirrors
