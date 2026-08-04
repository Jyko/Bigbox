package modules

import (
	"context"
	"fmt"

	"bigard.fr/bigbox/internal/bash"
	"bigard.fr/bigbox/internal/module"
	"bigard.fr/bigbox/internal/runtime"
)

var _ module.Module = (*UbuntuModule)(nil)

type UbuntuModule struct {
	runtime runtime.BigboxRuntime
}

func NewUbuntuModule(runtime runtime.BigboxRuntime) *UbuntuModule {
	return &UbuntuModule{
		runtime: runtime,
	}
}

func (u UbuntuModule) GetInfos() module.Info {
	return module.Info{
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

	changed, err := u.runtime.File().ReplaceKeyValue(
		"/etc/update-manager/release-upgrades",
		"Prompt",
		"normal",
		false,
	)
	if err != nil {
		return fmt.Errorf("failed to modify do-release-update lts->normal: %w", err)
	}
	if changed > 0 {
		u.runtime.Logger().Debug("successfully changed do-release-update lts->normal")
	} else {
		u.runtime.Logger().Debug("skipped change do-release-update lts->normal")
	}

	// do-release-update retourne un exit code 1 en cas de release à jour, aussi étonnant que cela puisse paraitre.
	err = u.runtime.Cmd().Run(
		ctx,
		&bash.Cmd{
			Cmd:                  "do-release-upgrade",
			AcceptableErrorCodes: []int{1},
		},
	)
	if err != nil {
		u.runtime.Logger().Error("failed to upgrade ubuntu", "error", err)
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
