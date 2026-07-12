# Метроград — команды разработки
GODOT ?= godot

.PHONY: run
run: ## Запустить проект
	$(GODOT) --path .
