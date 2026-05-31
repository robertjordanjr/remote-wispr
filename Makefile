SWIFT_ENV = CLANG_MODULE_CACHE_PATH=$(PWD)/.module-cache

.PHONY: test-fixtures build-spike build-donor-app build-menubar-app build-input-spike setup-local-signing install-local privacy-scan local-db-check local-sync-next local-sync-next-cleanup-experimental local-sync-next-visible-donor input-spike-target-info input-spike-send-x input-spike-backspace input-spike-backspace-system input-spike-space-system input-spike-paste-fixed input-spike-paste-system input-spike-paste-keys input-spike-donor-paste-fixed input-spike-donor-clean-paste-system input-spike-donor-clean-paste-keys input-spike-type-fixed input-spike-type-modifiers input-spike-type-unicode clean

test-fixtures:
	$(SWIFT_ENV) swift run remote-wispr-fixture-tests

build-spike:
	$(SWIFT_ENV) swift build --product remote-wispr-spike

build-donor-app:
	./scripts/build-copy-donor-app.zsh

build-menubar-app: build-donor-app
	./scripts/build-menubar-app.zsh

build-input-spike:
	$(SWIFT_ENV) swift build --product remote-wispr-input-spike

setup-local-signing:
	./scripts/setup-local-signing.zsh

install-local:
	./scripts/install-local.zsh

privacy-scan:
	./scripts/privacy-scan.zsh

local-db-check: build-spike
	.build/debug/remote-wispr-spike db-check

local-sync-next: build-spike build-donor-app
	.build/debug/remote-wispr-spike wait-sync-next --timeout 20 --capture-delay 3 --copy-method persistent-donor-app --skip-return

local-sync-next-cleanup-experimental: build-spike build-donor-app
	.build/debug/remote-wispr-spike wait-sync-next --timeout 20 --capture-delay 3 --copy-method persistent-donor-app --skip-return --replace-v-with-space

local-sync-next-visible-donor: build-spike build-donor-app
	.build/debug/remote-wispr-spike wait-sync-next --timeout 20 --capture-delay 3 --copy-method persistent-donor-app --skip-return --visible-donor-window

input-spike-target-info: build-input-spike
	.build/debug/remote-wispr-input-spike target-info --capture-delay 3

input-spike-send-x: build-input-spike
	.build/debug/remote-wispr-input-spike send-key --key x --method hid --capture-delay 3

input-spike-backspace: build-input-spike
	.build/debug/remote-wispr-input-spike send-key --key delete --method hid --capture-delay 3

input-spike-backspace-system: build-input-spike
	.build/debug/remote-wispr-input-spike send-key --key delete --method system-events --capture-delay 3

input-spike-space-system: build-input-spike
	.build/debug/remote-wispr-input-spike send-key --key space --method system-events --capture-delay 3

input-spike-paste-fixed: build-input-spike
	.build/debug/remote-wispr-input-spike paste-fixed --method command-v --text REMOTE_WISPR_INPUT_TEST --capture-delay 3

input-spike-paste-system: build-input-spike
	.build/debug/remote-wispr-input-spike paste-fixed --method system-events --text REMOTE_WISPR_INPUT_TEST --capture-delay 3

input-spike-paste-keys: build-input-spike
	.build/debug/remote-wispr-input-spike paste-fixed --method command-v-keys --text REMOTE_WISPR_INPUT_TEST --capture-delay 3

input-spike-donor-paste-fixed: build-input-spike
	.build/debug/remote-wispr-input-spike donor-paste-fixed --text REMOTE_WISPR_DONOR_PASTE_TEST --capture-delay 3

input-spike-donor-clean-paste-system: build-input-spike
	.build/debug/remote-wispr-input-spike cleanup-paste-fixed --clipboard donor --cleanup backspace-space --cleanup-method system-events --paste-method system-events --text REMOTE_WISPR_CLEAN_PASTE_SYSTEM --capture-delay 3

input-spike-donor-clean-paste-keys: build-input-spike
	.build/debug/remote-wispr-input-spike cleanup-paste-fixed --clipboard donor --cleanup backspace-space --cleanup-method hid-modifiers --paste-method command-v-keys --text REMOTE_WISPR_CLEAN_PASTE_KEYS --capture-delay 3

input-spike-type-fixed: build-input-spike
	.build/debug/remote-wispr-input-spike type-fixed --method hid --text "Remote Wispr type test." --capture-delay 3

input-spike-type-modifiers: build-input-spike
	.build/debug/remote-wispr-input-spike type-fixed --method hid-modifiers --text "Remote Wispr MOD test!" --capture-delay 3

input-spike-type-unicode: build-input-spike
	.build/debug/remote-wispr-input-spike type-fixed --method unicode --text "Remote Wispr unicode test." --capture-delay 3

clean:
	rm -rf .build .module-cache
