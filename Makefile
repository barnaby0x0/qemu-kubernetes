# Variables

.PHONY: all build add clean

all: build add clean

build:
	@packer build packer.pkr.hcl

add:
	@vagrant box add ./metadata.json

# Nettoyage (facultatif)
clean:
	@rm -rf ./output-k8s

