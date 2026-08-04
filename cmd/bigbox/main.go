package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"

	"bigard.fr/bigbox/internal/bash"
	"bigard.fr/bigbox/internal/cli"
	"bigard.fr/bigbox/internal/engine"
	"bigard.fr/bigbox/internal/file"
	"bigard.fr/bigbox/internal/module"
	"bigard.fr/bigbox/internal/modules"
	"bigard.fr/bigbox/internal/runtime"
	"bigard.fr/bigbox/internal/user"
)

func main() {

	err := validateSudo()
	if err != nil {
		os.Exit(1)
	}

	// Contexte de l'utilisateur
	userCtx, err := user.NewContext()
	if err != nil {
		os.Exit(1)
	}

	// Loggers structurés, sortie StdOut pour le moment
	logger := slog.New(slog.NewTextHandler(
		os.Stdout,
		&slog.HandlerOptions{
			Level: slog.LevelInfo,
		},
	))
	slog.SetDefault(logger)

	// Injection des "services" communs à la mano
	cmdRunner := bash.NewStdCmdRunner(logger)
	fileManager := file.NewStdManager(logger)
	pkgManager := bash.NewAptPkgManager(logger, cmdRunner)
	rcManager := bash.NewStdRcManager(logger, userCtx, cmdRunner, fileManager)

	// Instanciation du contexte d'éxecution partagé entre les modules
	bigboxRuntime := runtime.NewStdBigboxRuntime(
		userCtx,
		cmdRunner,
		pkgManager,
		fileManager,
		rcManager,
		logger,
	)

	registry := engine.NewRegistry()
	// TODO : Plus tard, nous aurons une implémentation de chargement des modules plutôt qu'une déclaration statique
	// TODO : Egalement, nous chargerons des variables et secrets depuis des sources externes afin de créer un environment context pour les modules
	registry.Register([]module.Module{
		modules.NewCoreModule(bigboxRuntime),
		modules.NewUbuntuModule(bigboxRuntime),
		modules.NewQoLModule(bigboxRuntime),
	})
	reconciler := engine.NewReconciler(registry)

	// Instanciation des commandes Cobra
	root := cli.NewRootCmd(reconciler)
	root.SetContext(context.Background())

	// Cobra traite la commande demandée par l'utilisateur
	if err := root.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

}

// Valider les droits et la capacité d'élévation de l'utilisateur
func validateSudo() error {

	// Déjà
	if os.Geteuid() == 0 {
		return errors.New("bigbox must not be run as root; retry as your user")
	}

	// Nous demandons à valider un ticket d'élévation de droit que l'utilisateur pourra ensuite utiliser à sa guise (via CmdRunner#RunAsRoot())
	cmd := exec.Command("sudo", "-v")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("sudo authentication failed: %w", err)
	}

	return nil
}
