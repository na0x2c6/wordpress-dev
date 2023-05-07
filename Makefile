HTML_DIR := html
SQL_DIR := sql
WP_CONFIG_FILENAME := wp-config.php

DOCKER_COMPOSE_YML := docker-compose.yml

DOCKER_COMPOSE = docker-compose -f $(DOCKER_COMPOSE_YML)

DOCKER := docker
SSH := ssh
TAR := tar
REMOTE_TAR := tar
PV := pv
PERL := perl
FIND := find
RSYNC := rsync

MYSQLDUMP_OPT := --single-transaction --quick --skip-lock-tables --add-drop-table

CLONE_EXCLUDE :=
REMOTE_TAR_OPT :=
RSYNC_OPT = -rltv --delete

SYNC_PATH = wp-content/themes

deploy-once-file = ./do-deploy
deploy-always-file = ./deploy-with-skipping-confirm
check-deploy = $(if $(wildcard $(deploy-once-file) $(deploy-always-file)),1)

start: # for default target

include .env.makefile
include .db.env

REMOTE_TAR_OPT += $(addprefix --exclude=,$(CLONE_EXCLUDE))

# $(call exist-or-error,some-file)
define exist-or-error
	$(if $(wildcard $1),,$(error no $1 variable))
endef

.PHONY: start
start: containers
	$(DOCKER_COMPOSE) start

.PHONY: up
up:
	$(DOCKER_COMPOSE) up

.PHONY: stop
stop:
	$(DOCKER_COMPOSE) stop

.PHONY: down
down:
	$(DOCKER_COMPOSE) down
	rm -f containers

containers:
	$(MAKE) down
	$(DOCKER_COMPOSE) up --build --no-start
	touch $@

.PHONY: logs
logs:
	$(DOCKER_COMPOSE) logs -f

.PHONY: clone-to-local
clone-to-local:
	$(SSH) $(SSH_REMOTE_HOST) -- $(REMOTE_TAR) -C $(REMOTE_DOCROOT_PATH) -cf - $(REMOTE_TAR_OPT) . \
		| $(PV) | $(TAR) -C $(HTML_DIR)/ -xf -

.PHONY: guard-sync
guard-sync:
ifndef SSH_REMOTE_HOST
	$(error SSH_REMOTE_HOST variable is not defined)
endif

.PHONY: pull
pull: guard-sync
	$(RSYNC) $(RSYNC_OPT) $(SSH_REMOTE_HOST):$(REMOTE_DOCROOT_PATH)/$(SYNC_PATH)/ $(HTML_DIR)/$(SYNC_PATH)/

.PHONY: deploy
deploy: RSYNC_OPT += $(if $(call check-deploy),,-n)
deploy: guard-sync
	-$(RSYNC) $(RSYNC_OPT) $(HTML_DIR)/$(SYNC_PATH)/ $(SSH_REMOTE_HOST):$(REMOTE_DOCROOT_PATH)/$(SYNC_PATH)/
	-@[[ -z "$(call check-deploy)" ]] \
		&& echo 'info: You need to create a file `$(deploy-once-file)` to deploy for once or `$(deploy-always-file)` for skipping this confirmation every time.'
	rm -f $(deploy-once-file)

%.sql.imported: %.sql | wait-db-start
	cat "$^" | $(DOCKER_COMPOSE) exec -T -- db sh -c 'mysql --user $$MYSQL_USER -p$$MYSQL_PASSWORD $$MYSQL_DATABASE'
	touch $@

imported-sql-files = $(addsuffix .imported,$(wildcard $(SQL_DIR)/*.sql))

.PHONY: import-sql
import-sql: $(imported-sql-files)

.PHONY: wait-db-start
wait-db-start: start
	$(DOCKER_COMPOSE) exec -T -- db bash -c ' \
		while ! { echo > /dev/tcp/localhost/3306; } 2> /dev/null ; do sleep 1 ; done'

.PHONY: db-attach
db-attach: start
	$(DOCKER_COMPOSE) exec -- db bash

.PHONY: init-conf
init-conf: WP_CONF ?= $(shell $(FIND) $(HTML_DIR)/ -name $(WP_CONFIG_FILENAME) | head -n 1)
init-conf: .db.env
	perl -i.orig -pe " \
		s/define\\(\\s*'DB_HOST',\\s*'[^']*'\\s*\\)/define('DB_HOST', 'db')/; \
		s/define\\(\\s*'DB_NAME',\\s*'[^']*'\\s*\\)/define('DB_NAME', '$(MYSQL_DATABASE)')/; \
		s/define\\(\\s*'DB_USER',\\s*'[^']*'\\s*\\)/define('DB_USER', '$(MYSQL_USER)')/; \
		s/define\\(\\s*'DB_PASSWORD',\\s*'[^']*'\\s*\\)/define('DB_PASSWORD', '$(MYSQL_PASSWORD)')/; \
	" $(WP_CONF)

ifneq ($(and $(SITE_URL_PATTERN),$(LOCAL_URL),$(REMOTE_DOCROOT_PATH),$(LOCAL_DOCROOT)),)
db-replaced: import-sql
	$(DOCKER_COMPOSE) run --rm -- cli wp search-replace '$(SITE_URL_PATTERN)' '$(LOCAL_URL)'
	$(DOCKER_COMPOSE) run --rm -- cli wp search-replace '$(REMOTE_DOCROOT_PATH)' '$(LOCAL_DOCROOT)'
	touch $@
else
db-replaced:
	$(error You must set variables all of SITE_URL_PATTERN, LOCAL_URL, REMOTE_DOCROOT_PATH, LOCAL_DOCROOT)
endif

.PHONY: db-import
db-import: db-replaced

.PHONY: dump-remote-db
dump-remote-db: WP_CONF = $(shell $(SSH) $(SSH_REMOTE_HOST) -- find $(REMOTE_DOCROOT_PATH) -type f -name $(WP_CONFIG_FILENAME) | head -n 1)
dump-remote-db: get-val = $(shell $(SSH) $(SSH_REMOTE_HOST) -- 'perl -nle "/\\(\\s*'"'"'$1'"'"'\\s*,\\s*'"'"'(.+)'"'"'\\s*\\)/ and print \$$1" $(WP_CONF)')
dump-remote-db: DB_PASSWORD = $(call get-val,DB_PASSWORD)
dump-remote-db: DB_HOST = $(call get-val,DB_HOST)
dump-remote-db: DB_USER = $(call get-val,DB_USER)
dump-remote-db: DB_NAME = $(call get-val,DB_NAME)
dump-remote-db: SQL_FILE = $(SQL_DIR)/$(shell date "+%Y-%m-%d").sql
dump-remote-db:
	@$(SSH) $(SSH_REMOTE_HOST) -- mysqldump $(MYSQLDUMP_OPT) -u $(DB_USER) -h $(DB_HOST) -p$(DB_PASSWORD) $(DB_NAME) \
	| $(PV) > $(SQL_FILE)

.PHONY: clean-imported
clean-imported:
	rm -f $(SQL_DIR)/*.imported db-replaced

.PHONY: purge-db
purge-db:
	$(DOCKER_COMPOSE) down -v
	$(MAKE) clean-imported

.PHONY: wp-cli
wp-cli:
	$(DOCKER_COMPOSE) run --rm -- cli bash
