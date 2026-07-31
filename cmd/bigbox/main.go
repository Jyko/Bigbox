package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	"bigard.fr/bigbox/internal/cli"
	"bigard.fr/bigbox/internal/engine"
	"bigard.fr/bigbox/internal/module"
	"bigard.fr/bigbox/internal/modules/qol"
)

func main() {

	// Loggers structurés, sortie StdOut pour le moment
	defaultLogger := slog.New(slog.NewTextHandler(
		os.Stdout,
		&slog.HandlerOptions{
			Level: slog.LevelInfo,
		},
	))

	slog.SetDefault(defaultLogger)

	registry := engine.NewRegistry()
	// TODO : Plus tard, nous aurons un système de chargement des modules plutôt qu'une déclaration statique
	// TODO : Egalement, nous chargerons des variables et secrets depuis des sources externes
	registry.Register([]module.Module{
		qol.New(),
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
