package engine

import "bigard.fr/bigbox/internal/module"

type Plan struct {
	Operations []Operation
}

type Operation struct {
	Module        module.Module
	OperationType OperationType
}

type OperationType int

const (
	InstallOperation OperationType = iota
	UninstallOperation
	StartOperation
	StopOperation
)
