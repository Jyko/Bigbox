package modules

import (
	"context"
	"fmt"

	"bigard.fr/bigbox/internal/module"
	"bigard.fr/bigbox/internal/runtime"
)

var _ module.Module = (*CoreModule)(nil)

type CoreModule struct {
	runtime runtime.BigboxRuntime
	pkgs    []string
}

func NewCoreModule(runtime runtime.BigboxRuntime) *CoreModule {
	return &CoreModule{
		runtime: runtime,
		pkgs: []string{
			"apt-transport-https",
			"bash-completion",
			"ca-certificates",
			"curl",
			"gnupg",
			"jq",
			"make",
			"openssl",
			"shellcheck",
			"tar",
			"yq",
			"wget",
		},
	}
}

func (m *CoreModule) GetInfos() module.Info {
	return module.Info{
		Name:        "core",
		Version:     "1.0.0",
		Description: "Module coeur de la Bigbox dont l'installation est obligatoire à son bon fonctionnement",
		Installable: true,
		Runnable:    false,
	}
}

func (m *CoreModule) GetState(ctx context.Context) (module.State, error) {

	checkResults, err := module.RunChecks(ctx, m.checks())
	if err != nil {
		return module.State{}, err
	}

	// TODO : Reduce checkResults à un bool assignagle à State.Installed

	return module.State{
		Installed: isInstalled,
		Running:   false,
		Version:   "1.0.0",
	}, nil
}

func (m *CoreModule) Install(ctx context.Context) error {

	// Le module Core est responsable du bootstrap de la bigbox
	if err := m.runtime.Rc().Install(ctx); err != nil {
		return err
	}

	if err := m.runtime.Pkg().Install(ctx, m.pkgs); err != nil {
		return err
	}

	return nil
}

func (m *CoreModule) Uninstall(ctx context.Context) error {

	if err := m.runtime.Pkg().Uninstall(ctx, m.pkgs); err != nil {
		return err
	}

	if err := m.runtime.Rc().Uninstall(ctx); err != nil {
		return err
	}

	return nil
}

func (m *CoreModule) Start(ctx context.Context) error {
	return fmt.Errorf("core module does not support starting")
}

func (m *CoreModule) Stop(ctx context.Context) error {
	return fmt.Errorf("core module does not support stopping")
}

func (m *CoreModule) checks() []module.Check {

	return []module.Check{
		{Name: "rc config", Fn: func(ctx context.Context) (bool, error) { return m.runtime.Rc().Verify(ctx) }},
	}

}
