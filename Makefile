PANVIMDOC_DIR ?= /tmp/panvimdoc

.PHONY: setup lint panvimdoc docs

setup:
	git config core.hooksPath .githooks

panvimdoc:
	@if [ ! -d "$(PANVIMDOC_DIR)" ]; then \
		git clone --depth 1 https://github.com/kdheepak/panvimdoc $(PANVIMDOC_DIR); \
	fi

lint:
	stylua --check lua/

docs: panvimdoc
	$(PANVIMDOC_DIR)/panvimdoc.sh \
		--project-name ruby-lsp.nvim \
		--input-file README.md \
		--vim-version "NVIM v0.10.0" \
		--toc true \
		--treesitter true \
		--doc-mapping-project-name false
