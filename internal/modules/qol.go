package modules

import (
	"context"
	"fmt"

	"bigard.fr/bigbox/internal/module"
	"bigard.fr/bigbox/internal/runtime"
)

var _ module.Module = (*QoLModule)(nil)

type QoLModule struct {
	runtime runtime.BigboxRuntime
	pkgs    []string
}

func NewQoLModule(runtime runtime.BigboxRuntime) *QoLModule {

	return &QoLModule{
		runtime: runtime,
		pkgs: []string{
			"bat",
			"eza",
			"fd-find",
			"fzf",
		},
	}
}

func (m *QoLModule) GetInfos() module.Info {
	return module.Info{
		Name:        "qol",
		Version:     "1.0.0",
		Description: "Outils, aliases et autocomplétion pour le confort d'utilisation de la distribution Ubuntu WSL2",
		Installable: true,
		Runnable:    false,
	}
}

func (m *QoLModule) GetState(ctx context.Context) (module.State, error) {
	// FIXME : To be implemented
	state := module.State{
		Installed: false,
		Running:   false,
		Version:   "1.0.0",
	}

	return state, nil
}

func (m *QoLModule) Install(ctx context.Context) error {

	if err := m.runtime.Pkg().Install(ctx, m.pkgs); err != nil {
		return fmt.Errorf("packages installation failed: %w", err)
	}

	return nil
}

func (m *QoLModule) Uninstall(ctx context.Context) error {

	if err := m.runtime.Pkg().Install(ctx, m.pkgs); err != nil {
		return err
	}

	return nil
}

func (m *QoLModule) Start(ctx context.Context) error {
	return fmt.Errorf("module is not runnable")
}

func (m *QoLModule) Stop(ctx context.Context) error {
	return fmt.Errorf("module is not runnable")
}
