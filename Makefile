# Makefile

CATALOG_FILE="catalog-info.json"

all:
	@echo "Available targets:"
	@echo
	@echo "  make validate"
	@echo "  make validate-generation"
	@echo "  make regenerate # regenerate catalog info index"
	@echo

validate:
	scripts/validate.sh

validate-generation:
	scripts/generate-catalog-info.sh | jq . > /dev/null

regenerate: validate-generation
	scripts/generate-catalog-info.sh > $(CATALOG_FILE)
