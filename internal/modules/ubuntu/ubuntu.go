package ubuntu

import (
	"context"
	"fmt"
	"log/slog"

	"bigard.fr/bigbox/internal/module"
	"bigard.fr/bigbox/internal/shell"
)

var _ module.Module = (*UbuntuModule)(nil)

type UbuntuModule struct {
	log    *slog.Logger
	runner *shell.Runner
}

func New() *UbuntuModule {
	return &UbuntuModule{
		log:    slog.With("component", "UbuntuModule"),
		runner: shell.NewRunner(),
	}
}

func (u UbuntuModule) GetInfos() module.ModuleInfo {
	return module.ModuleInfo{
		Name:        "ubuntu",
		Version:     "1.0.0",
		Description: "Vérification et mise-à-jour du kernel et de la distribution Ubuntu WSL2",
		Installable: true,
		Runnable:    false,
	}
}

func (u UbuntuModule) GetState(ctx context.Context) (module.State, error) {
	state := module.State{
		Installed: false,
		Running:   false,
		Version:   "1.0.0",
	}
	return state, nil
}

func (u UbuntuModule) Install(ctx context.Context) error {

	// TODO : /etc/update-manager/release-upgrades à changer pour passer en normal. Certainement une fonction générique à écrire pour changer des lignes de fichiers (çà servira pour les dotfiles et le .bashrc)

	// do-release-update retourne un exit code 1 en cas de release à jour, aussi étonnant que cela puisse paraitre.
	err := u.runner.Run(
		ctx,
		&shell.RunnableCommand{
			Cmd:                  "do-release-upgrade",
			AcceptableErrorCodes: []int{1},
		},
	)
	if err != nil {
		u.log.Error("failed to upgrade ubuntu", "error", err)
		return fmt.Errorf("failed to upgrade ubuntu: %w", err)
	}

	return nil
}

func (u UbuntuModule) Uninstall(ctx context.Context) error {
	panic("to be implemented")
}

func (u UbuntuModule) Start(ctx context.Context) error {
	return fmt.Errorf("module is not runnable")
}

func (u UbuntuModule) Stop(ctx context.Context) error {
	return fmt.Errorf("module is not runnable")
}
