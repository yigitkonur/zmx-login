.PHONY: install uninstall check test help

help:
	@echo "targets:"
	@echo "  install    install the hook and wire it into ~/.zshrc"
	@echo "  uninstall  remove the hook and unwire ~/.zshrc"
	@echo "  check      lint the shell scripts and run the sandbox round-trip test"
	@echo "  test       alias for check"

install:
	sh ./install.sh

uninstall:
	sh ./uninstall.sh

check test:
	@zsh -n zellij-ssh-login.zsh     && echo "zsh -n: zellij-ssh-login.zsh     OK"
	@sh  -n install.sh               && echo "sh -n:  install.sh               OK"
	@sh  -n uninstall.sh             && echo "sh -n:  uninstall.sh             OK"
	@sh  -n zellij-login-preview.sh  && echo "sh -n:  zellij-login-preview.sh  OK"
	@sh  -n zellij-login-action.sh   && echo "sh -n:  zellij-login-action.sh   OK"
	@sh  -n test/roundtrip.sh        && echo "sh -n:  test/roundtrip.sh        OK"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck --shell=sh install.sh uninstall.sh \
		             zellij-login-preview.sh zellij-login-action.sh test/roundtrip.sh \
		  && echo "shellcheck: OK"; \
	else \
		echo "shellcheck: not installed (skipped)"; \
	fi
	sh test/roundtrip.sh
