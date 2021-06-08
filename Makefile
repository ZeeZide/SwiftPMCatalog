# Makefile

all:
	@echo "Available targets:"
	@echo
	@echo "  make validate"

validate:
	scripts/validate.sh
