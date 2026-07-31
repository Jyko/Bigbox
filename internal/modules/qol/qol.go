package qol

import (
	"context"

	"bigard.fr/bigbox/internal/module"
)

var _ module.Module = (*QualityOfLifeModule)(nil)

type QualityOfLifeModule struct{}

func New() *QualityOfLifeModule {
	return &QualityOfLifeModule{}
}

func (m *QualityOfLifeModule) GetInfos() module.ModuleInfo {
	return module.ModuleInfo{
		Name:        "qol",
		Version:     "1.0.0",
		Description: "Outils et aliases pour le confort d'utilisation de la distribution Ubuntu WSL2",
		Installable: true,
		Runnable:    false,
	}
}

func (m *QualityOfLifeModule) GetState(ctx context.Context) (module.State, error) {
	return module.State{}, nil
}

func (m *QualityOfLifeModule) Install(ctx context.Context) error {



	return nil
}

func (m *QualityOfLifeModule) Uninstall(ctx context.Context) error {
	return nil
}

func (m *QualityOfLifeModule) Start(ctx context.Context) error {
	return nil
}

func (m *QualityOfLifeModule) Stop(ctx context.Context) error {
	return nil
}
