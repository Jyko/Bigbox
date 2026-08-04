package runtime

import (
	"log/slog"

	"bigard.fr/bigbox/internal/bash"
	"bigard.fr/bigbox/internal/file"
	"bigard.fr/bigbox/internal/user"
)

// BigboxRuntime Contrat du contexte applicatif Bigbox, rassemblant les fonctionnalités transverses mise à disposition
// du reconcilier et de l'ensemble des modules.
type BigboxRuntime interface {
	User() user.Context
	Cmd() bash.CmdRunner
	Pkg() bash.PkgManager
	File() file.Manager
	Rc() bash.RcManager
	Logger() *slog.Logger
}

var _ BigboxRuntime = (*StdBigboxRuntime)(nil)

type StdBigboxRuntime struct {
	user   user.Context
	cmd    bash.CmdRunner
	pkg    bash.PkgManager
	file   file.Manager
	rc     bash.RcManager
	logger *slog.Logger
}

func NewStdBigboxRuntime(
	user user.Context,
	cmd bash.CmdRunner,
	pkg bash.PkgManager,
	file file.Manager,
	rc bash.RcManager,
	logger *slog.Logger,
) *StdBigboxRuntime {
	return &StdBigboxRuntime{
		user:   user,
		cmd:    cmd,
		pkg:    pkg,
		file:   file,
		rc:     rc,
		logger: logger,
	}
}

func (bc *StdBigboxRuntime) User() user.Context {
	return bc.user
}

func (bc *StdBigboxRuntime) Cmd() bash.CmdRunner {
	return bc.cmd
}

func (bc *StdBigboxRuntime) Pkg() bash.PkgManager {
	return bc.pkg
}

func (bc *StdBigboxRuntime) File() file.Manager {
	return bc.file
}

func (bc *StdBigboxRuntime) Rc() bash.RcManager {
	return bc.rc
}

func (bc *StdBigboxRuntime) Logger() *slog.Logger {
	return bc.logger
}
