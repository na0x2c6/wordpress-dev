
WP_PATH = $(patsubst %/,%,$(HTML_DIR)/$(WP_INSTALL_DIR))

wp-includes = $(WP_PATH)/wp-includes

$(wp-includes):
	$(DOCKER) run --rm -- docker.io/library/wordpress:$(WP_IMAGE_TAG) tar -cf - --exclude wp-content . \
		| tar -C $(WP_PATH) -xvf -

.PHONY: extract
extract: | $(wp-includes)
	$(if $(wildcard $(file)),,$(error usage: make extract file=<Tar file from VaultPress>))
	$(TAR) -C $(SQL_DIR)/ -xvzf $(file) --strip-components 1 sql/
	$(TAR) -C $(WP_PATH)/ -xvzf $(file) --exclude sql/ --exclude wp-config.php
	[[ -e "$(WP_PATH)/wp-config.php" ]] || \
		$(TAR) -C $(WP_PATH)/ -xvzf $(file) wp-config.php
