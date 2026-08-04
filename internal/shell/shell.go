package shell

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

type RunnableCommand struct {
	Cmd                  string
	Args                 []string
	AcceptableErrorCodes []int
	OnSuccess            func(stdOut string) error                       // Version minimaliste du callback onSuccess
	OnError              func(exitCode int, stdOut, stdErr string) error // Version minimaliste du callback onError, vous pouvez les modifier à votre guise
}

type Runner struct {
	log *slog.Logger
}

func NewRunner() *Runner {
	return &Runner{
		log: slog.With("component", "Runner"),
	}
}

func (r *Runner) Run(ctx context.Context, cmd *RunnableCommand) error {

	var stdOutBuf, stdErrBuf bytes.Buffer

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
