package run

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"syscall"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/log"
)

// maxCapture borne la taille de chaque sortie conservée dans le journal.
const maxCapture = 256 << 10

// gracePeriod laisse à la commande le temps de s'arrêter après SIGTERM, avant SIGKILL.
const gracePeriod = 5 * time.Second

// Exec est le Runner réel.
type Exec struct {
	Logger   *slog.Logger
	Redactor *log.Redactor
	// Sudo doit avoir été obtenu (Sudo.Ensure) avant toute commande Privileged.
	Sudo *Sudo
}

var _ Runner = (*Exec)(nil)

// Run implémente Runner.
func (e *Exec) Run(ctx context.Context, c Cmd) (Result, error) {
	res, err := e.exec(ctx, c)
	if err != nil {
		return res, failure(c, res, err, e.Redactor)
	}
	return res, nil
}

// Probe implémente Runner.
func (e *Exec) Probe(ctx context.Context, c Cmd) (bool, error) {
	res, err := e.exec(ctx, c)
	var exitErr *ExitError
	switch {
	case err == nil:
		return true, nil
	case errors.As(err, &exitErr):
		return false, nil
	default:
		return false, failure(c, res, err, e.Redactor)
	}
}

func (e *Exec) exec(ctx context.Context, c Cmd) (Result, error) {
	if len(c.Args) == 0 {
		return Result{}, errs.New(errs.Internal, "commande vide")
	}
	if c.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, c.Timeout)
		defer cancel()
	}
	argv := c.Args
	if c.Privileged && os.Geteuid() != 0 {
		// -n : jamais de demande de mot de passe ici, elle a eu lieu dans Sudo.Ensure
		argv = append([]string{"sudo", "-n", "--"}, argv...)
	}

	logger := e.logger()
	logger.Debug(log.EvCmdExec, log.KeyArgv, argv, log.KeyDir, c.Dir)

	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	cmd.Dir = c.Dir
	if len(c.Env) > 0 {
		cmd.Env = append(os.Environ(), c.Env...)
	}
	cmd.Stdin = c.Stdin
	var stdout, stderr limitedBuffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	// Groupe de processus dédié : l'annulation atteint aussi les processus enfants
	// (et sudo relaie le signal à la commande qu'il a lancée).
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
	}
	cmd.WaitDelay = gracePeriod

	start := time.Now()
	err := cmd.Run()
	res := Result{Stdout: stdout.String(), Stderr: stderr.String(), Duration: time.Since(start), ExitCode: -1}
	if cmd.ProcessState != nil {
		res.ExitCode = cmd.ProcessState.ExitCode()
	}
	if cmd.Process != nil && ctx.Err() != nil {
		// Les retardataires du groupe sont tués
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}

	logger.Debug(log.EvCmdExit, log.KeyArgv, argv, log.KeyExitCode, res.ExitCode,
		log.KeyDuration, res.Duration, log.KeyStdout, res.Stdout, log.KeyStderr, res.Stderr)

	switch {
	case ctx.Err() != nil:
		return res, ctx.Err()
	case err == nil:
		return res, nil
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		return res, &ExitError{Code: res.ExitCode}
	}
	if errors.Is(err, exec.ErrNotFound) {
		return res, &errs.Error{Kind: errs.Precondition, Op: fmt.Sprintf("programme %s introuvable", argv[0]), Cause: err,
			Hint: "installez-le ou vérifiez le PATH"}
	}
	return res, err
}

func (e *Exec) logger() *slog.Logger {
	if e.Logger == nil {
		return log.Discard()
	}
	return e.Logger
}

// limitedBuffer conserve au plus maxCapture octets (les derniers, les plus utiles).
type limitedBuffer struct {
	buf       bytes.Buffer
	truncated bool
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	n := len(p)
	b.buf.Write(p)
	if over := b.buf.Len() - maxCapture; over > 0 {
		b.buf.Next(over)
		b.truncated = true
	}
	return n, nil
}

func (b *limitedBuffer) String() string {
	if b.truncated {
		return "[…sortie tronquée…]\n" + b.buf.String()
	}
	return b.buf.String()
}
