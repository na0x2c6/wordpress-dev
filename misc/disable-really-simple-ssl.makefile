WP_PATH = $(patsubst %/,%,$(HTML_DIR)/$(WP_INSTALL_DIR))
URL_BASE = $(patsubst %/,%,$(LOCAL_URL)/$(WP_INSTALL_DIR))

.PHONY: disable-ssl
disable-ssl: deactive-file = $(shell find $(WP_PATH)/wp-content/plugins -name force-deactivate.txt)
disable-ssl:
	$(if $(wildcard $(deactive-file)),, $(error force-deactivate.txt: not found))
	cp $(deactive-file) $(basename $(deactive-file)).php
	@echo "Success, don't forget to access \`$(URL_BASE)/wp-content/plugins/really-simple-ssl/force-deactivate.php\` to disable SSL."
