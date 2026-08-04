package qol

import (
	"context"
	"fmt"
	"log/slog"

	"bigard.fr/bigbox/internal/module"
	"bigard.fr/bigbox/internal/shell"
)

var _ module.Module = (*QualityOfLifeModule)(nil)

type QualityOfLifeModule struct {
	log      *slog.Logger
	runner   *shell.Runner
	packages []string
}

func New() *QualityOfLifeModule {

	return &QualityOfLifeModule{
		log:    slog.With("component", "QualityOfLifeModule"),
		runner: shell.NewRunner(),
		packages: []string{
			"git",
			"jq",
			"tar",
			"p7zip*",
			"fzf",
			"bat",
			"eza",
			"fd-find",
			"make",
		},
	}
}

func (m *QualityOfLifeModule) GetInfos() module.ModuleInfo {
	return module.ModuleInfo{
		Name:        "qol",
		Version:     "1.0.0",
		Description: "Outils, aliases et autocomplétion pour le confort d'utilisation de la distribution Ubuntu WSL2",
		Installable: true,
		Runnable:    false,
	}
}

func (m *QualityOfLifeModule) GetState(ctx context.Context) (module.State, error) {
	// FIXME : To be implemented
	state := module.State{
		Installed: false,
		Running:   false,
		Version:   "1.0.0",
	}

	return state, nil
}

func (m *QualityOfLifeModule) Install(ctx context.Context) error {

	var err error

	err = m.runner.Run(ctx, &shell.RunnableCommand{Cmd: "apt", Args: []string{"update"}})
	if err != nil {
		m.log.Error("repositories update failed", "error", err)
		return fmt.Errorf("repositories update failed: %w", err)
	}

	err = m.runner.Run(ctx, &shell.RunnableCommand{Cmd: "apt", Args: []string{"upgrade", "-y"}})
	if err != nil {
		m.log.Error("package upgrade failed", "error", err)
		return fmt.Errorf("package upgrade failed: %w", err)
	}

	err = m.runner.Run(
		ctx,
		&shell.RunnableCommand{
			Cmd:  "apt",
			Args: append([]string{"install", "-y"}, m.packages...),
		},
	)
	if err != nil {
		m.log.Error("packages install failed", "error", err)
		return fmt.Errorf("packages install failed: %w", err)
	}

	return nil
}

func (m *QualityOfLifeModule) Uninstall(ctx context.Context) error {
	panic("to be implemented")
}

func (m *QualityOfLifeModule) Start(ctx context.Context) error {
	return fmt.Errorf("module is not runnable")
}

func (m *QualityOfLifeModule) Stop(ctx context.Context) error {
	return fmt.Errorf("module is not runnable")
}
