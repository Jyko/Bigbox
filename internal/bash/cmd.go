package bash

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"slices"
)

type Cmd struct {
	Cmd                  string
	Args                 []string
	Privilege            PrivilegeLevel
	AcceptableErrorCodes []int
	OnSuccess            func(stdOut string) error
	OnError              func(exitCode int, stdOut, stdErr string) error
}

type PrivilegeLevel int

const (
	PrivilegeUser PrivilegeLevel = iota
	PrivilegeRoot
)

type CmdRunner interface {
	Run(ctx context.Context, cmd *Cmd) error
	RunSequence(ctx context.Context, sequence []Cmd) error
}

type StdCmdRunner struct {
	log *slog.Logger
}

var _ CmdRunner = (*StdCmdRunner)(nil)

// NewStdCmdRunner Instancier un nouveau gestionnaire d'exécution de commandes
func NewStdCmdRunner(logger *slog.Logger) *StdCmdRunner {
	return &StdCmdRunner{
		log: logger,
	}
}

func (r *StdCmdRunner) Run(ctx context.Context, cmd *Cmd) error {

	var stdOutBuf, stdErrBuf bytes.Buffer

	if cmd.Privilege == PrivilegeRoot {
		// La commande devient un argument de sudo, nous prenons soin de l'insérer en tête de la slice d'args
		cmd.Args = slices.Insert(cmd.Args, 0, cmd.Cmd)
		cmd.Cmd = "sudo"
	}

	cmdCtx := exec.CommandContext(ctx, cmd.Cmd, cmd.Args...)
	cmdCtx.Stdin = os.Stdin
	cmdCtx.Stdout = io.MultiWriter(os.Stdout, &stdOutBuf)
	cmdCtx.Stderr = io.MultiWriter(os.Stderr, &stdErrBuf)

	if err := cmdCtx.Run(); err != nil {

		// Nous récupérons le code de l'erreur, sinon -1
		exitCode := -1
		var exitErr *exec.ExitError

		if errors.As(err, &exitErr) {
			exitCode = exitErr.ExitCode()
		}

		// Si le code erreur est acceptable, nous quittons la gestion d'erreur et considérons l'exécution comme réussie.
		if cmd.AcceptableErrorCodes != nil && slices.Contains(cmd.AcceptableErrorCodes, exitCode) {
			r.log.Debug(
				"command succeeded with accepted error code",
				"cmd", cmd,
				"args", cmd.Args,
				"exitCode", exitCode,
				"stdOut", stdOutBuf.String(),
				"stdErr", stdErrBuf.String(),
			)
			return nil
		}

		// Si nous avons un callback, let's gooooo !
		if cmd.OnError != nil {
			r.log.Debug("command failed with callback on-error",
				"cmd", cmd,
				"args", cmd.Args,
				"exitCode", exitCode,
				"stdOut", stdOutBuf.String(),
				"stdErr", stdErrBuf.String(),
			)
			return cmd.OnError(exitCode, stdOutBuf.String(), stdErrBuf.String())
		}

		r.log.Error(
			"command failed",
			"cmd", cmd,
			"args", cmd.Args,
			"exitCode", exitCode,
			"stdout", stdOutBuf.String(),
			"stdErr", stdErrBuf.String(),
		)
		return fmt.Errorf("running shell command %s failed : %w", cmd, err)
	}

	// Si nous avons un callback onSuccess, let's goooooooo !
	if cmd.OnSuccess != nil {
		r.log.Debug(
			"command succeeded with callback on-success",
			"cmd", cmd,
			"args", cmd.Args,
			"stdout", stdOutBuf.String(),
		)
		return cmd.OnSuccess(stdOutBuf.String())
	}

	r.log.Debug(
		"command succeeded",
		"cmd", cmd,
		"args", cmd.Args,
		"stdout", stdOutBuf.String(),
	)
	return nil
}

func (r *StdCmdRunner) RunSequence(ctx context.Context, sequence []Cmd) error {

	for _, cmd := range sequence {
		if err := r.Run(ctx, &cmd); err != nil {
			r.log.Error("commands sequence failed", "cmd", cmd.Cmd, "args", cmd.Args, "error", err)
			return fmt.Errorf("commands sequence failed with: %w", err)
		}
	}

	r.log.Debug("commands sequence successfully executed")

	return nil
}
