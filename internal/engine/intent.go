package engine

type Intent struct {
	ModulesName []string
	Action      Action
}

type Action int

const (
	ActionInstall Action = iota
	ActionUninstall
	ActionStart
	ActionStop
	ActionInfo
	ActionVersion
)
