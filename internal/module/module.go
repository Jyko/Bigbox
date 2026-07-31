package module

import "context"

type ModuleInfo struct {
	Name        string
	Version     string
	Description string
	Installable bool
	Runnable    bool
}

type State struct {
	Installed bool
	Running   bool
	Version   string
}

type Module interface {
	GetInfos() ModuleInfo
	GetState(ctx context.Context) (State, error)
	Install(ctx context.Context) error
	Uninstall(ctx context.Context) error
	Start(ctx context.Context) error
	Stop(ctx context.Context) error
}
