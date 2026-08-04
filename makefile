# Ce makefile permet de :
# - Construire l'exécutable sur une distro Ubuntu disposant de l'environnement de développement et de compilation installé
# - Copier et tester l'exécutable sur une distro Ubuntu d'intégration jetable

BIN_NAME := bigbox
BIN_PATH := ~/bigbox
# Récupérer le %USERPROFILE% depuis le Host Windows pour assurer une compatibilité à toute épreuve du makefile
WIN_HOME := $(shell wslpath "$$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')")
BASE_DISTRO := Ubuntu-26.04
WSL_DIR = $(WIN_HOME)/wsl2
WSL_BACKUP_DIR = $(WSL_DIR)/backup
WSL_INSTALL_DIR = $(WSL_DIR)/install
INT_DISTRIBUTION_NAME := Bigbox-Integration
INT_SNAPSHOT_PATH = $(WSL_BACKUP_DIR)/bigbox-integration.tar
INT_INSTALL_PATH := $(WSL_INSTALL_DIR)/integration

# Pour la règle `test`, nous récupérons tous les arguments passé à `make` pour balancer les actions à tester contre le binaire.
# Ca évite des les avoir en dur dans le makefile et de pouvoir faire directement des :
# make test install mon_module
# make test uninstall
ARGS := $(filter-out $@,$(filter-out test,$(MAKECMDGOALS)))

.PHONY: init-env reset-env build deploy test

init-env:
	@if wsl.exe -l -q | iconv -f UTF-16LE -t UTF-8 | tr -d '\r' | grep -qx "$(BASE_DISTRO)"; then \
		echo "Distribution de référence $(BASE_DISTRO) déjà présente, nous passons directement à la création de la snapshot d'intégration."; \
	else \
		echo "Création de la distribution de référence : créez votre user/mdp, puis tapez 'exit' pour continuer."; \
		wsl.exe --install -d $(BASE_DISTRO); \
	fi

	wsl.exe --terminate $(BASE_DISTRO)

	mkdir -p $(WSL_BACKUP_DIR)
	mkdir -p $(WSL_INSTALL_DIR)

	@echo "Génération de la snapshot d'intégration réutilisable."
	wsl.exe --export $(BASE_DISTRO) "$(shell wslpath -w $(INT_SNAPSHOT_PATH))"
	wsl.exe --import $(INT_DISTRIBUTION_NAME) "$(shell wslpath -w $(INT_INSTALL_PATH))" "$(shell wslpath -w $(INT_SNAPSHOT_PATH))"
	@echo "Snapshot d'intégration prête à l'usage."

reset-env:
	@echo "Remplacement de la snapshot d'intégration en cours."
	@if wsl.exe -l -q | iconv -f UTF-16LE -t UTF-8 | tr -d '\r' | grep -qx "$(INT_DISTRIBUTION_NAME)"; then \
		wsl.exe --unregister $(INT_DISTRIBUTION_NAME); \
	fi

	wsl.exe --import $(INT_DISTRIBUTION_NAME) "$(shell wslpath -w $(INT_INSTALL_PATH))" "$(shell wslpath -w $(INT_SNAPSHOT_PATH))"
	@echo "Remplacement de la snapshot d'intégration terminé."

# Build sur l'image officiel GoLang puis utilisation de Scratch pour exporter facilement le livrable crée sans problème de user/group et de spécifique OS.
build:
	docker build --target export --output type=local,dest=. .

deploy: build reset-env
	wsl.exe -d $(INT_DISTRIBUTION_NAME) --cd ~ -e bash -c "cat > $(BIN_PATH) && chmod +x $(BIN_PATH)" < ./$(BIN_NAME)

# Passage des arguments capturés précédement (l'action Bigbox et ses paramètres)
test:
	wsl.exe -d $(INT_DISTRIBUTION_NAME) --cd ~ -e $(BIN_PATH) $(ARGS)


# Empêche make de chercher une règle pour les actions que l'on souhaite passer à notre binaire lors de la règle test
%:
	@: