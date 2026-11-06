package errs

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/Jyko/Bigbox/internal/testutil"
)

func TestExitCode(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want int
	}{
		{"nil", nil, ExitOK},
		{"interne", errors.New("boum"), ExitFailed},
		{"usage", New(Usage, "x"), ExitUsage},
		{"config", New(Config, "x"), ExitUsage},
		{"précondition", New(Precondition, "x"), ExitPrecondition},
		{"conflit", New(Conflict, "x"), ExitPrecondition},
		{"environnement", New(Environment, "x"), ExitFailed},
		{"dérive", &DriftError{Changes: 2}, ExitDrift},
		{"annulation", fmt.Errorf("étape : %w", context.Canceled), ExitInterrupted},
		{"enveloppée", fmt.Errorf("ctx : %w", New(Precondition, "x")), ExitPrecondition},
	}
	for _, c := range cases {
		if got := ExitCode(c.err); got != c.want {
			t.Errorf("%s : ExitCode = %d, attendu %d", c.name, got, c.want)
		}
	}
}

func TestWithStepCompleteSansEmpiler(t *testing.T) {
	cause := errors.New("connection refused")
	base := &Error{Kind: Environment, Op: "appeler l'API", Cause: cause}
	err := WithStep(fmt.Errorf("contexte : %w", base), "pg", "déployer")

	var e *Error
	if !errors.As(err, &e) {
		t.Fatal("*Error attendue")
	}
	if e.Feature != "pg" || e.Step != "déployer" || e.Kind != Environment {
		t.Errorf("champs inattendus : %+v", e)
	}
	if !errors.Is(err, cause) {
		t.Error("la cause doit rester accessible par errors.Is")
	}
	if base.Feature != "" {
		t.Error("l'erreur d'origine ne doit pas être modifiée")
	}
	if KindOf(WithStep(errors.New("x"), "f", "s")) != Internal {
		t.Error("une erreur non typée doit devenir Internal")
	}
}

func TestFindHint(t *testing.T) {
	cases := []struct {
		name, out, want string
		kind            Kind
	}{
		{"verrou dpkg",
			"E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 1234 (unattended-upgr)\nE: Unable to acquire the dpkg frontend lock",
			"apt est utilisé par le processus unattended-upgr (PID 1234) ; attendez la fin des mises à jour automatiques puis relancez", Conflict},
		{"verrou lists",
			"E: Could not get lock /var/lib/apt/lists/lock - open (11: Resource temporarily unavailable)",
			"apt est utilisé par un autre processus ; attendez la fin des mises à jour automatiques puis relancez", Conflict},
		{"sudo sans tty",
			"sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper\nsudo: a password is required",
			"des étapes nécessitent root ; relancez dans un terminal interactif", Precondition},
		{"k3s injoignable",
			"The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?",
			"k3s ne répond pas ; `sudo systemctl status k3s` puis `journalctl -u k3s -n 50`", Environment},
		{"webhook cnpg",
			`Internal error occurred: failed calling webhook "mcluster.cnpg.io": failed to call webhook: Post "https://cnpg-webhook-service.cnpg-system.svc:443/mutate-postgresql-cnpg-io-v1-cluster?timeout=10s": dial tcp 10.43.12.7:443: connect: connection refused`,
			"l'opérateur cnpg démarre encore ; relancez `bigbox apply`", Environment},
		{"port occupé",
			"Error starting userland proxy: listen tcp4 0.0.0.0:5432: bind: address already in use",
			"le port 5432 est déjà utilisé sur le poste ; libérez-le ou changez le port exposé dans bigbox.yaml", Precondition},
		{"dns apt",
			"W: Failed to fetch http://archive.ubuntu.com/ubuntu/dists/noble/InRelease  Temporary failure resolving 'archive.ubuntu.com'",
			"archive.ubuntu.com injoignable ; vérifiez la connexion ou le proxy (`HTTPS_PROXY`)", Environment},
		{"dns curl", "curl: (6) Could not resolve host: get.k3s.io",
			"get.k3s.io injoignable ; vérifiez la connexion ou le proxy (`HTTPS_PROXY`)", Environment},
		{"disque", "write /var/lib/rancher: No space left on device",
			"disque plein ; libérez de l'espace (`df -h`) puis relancez", Precondition},
	}
	for _, c := range cases {
		got, kind, ok := FindHint(c.out)
		if !ok || got != c.want || kind != c.kind {
			t.Errorf("%s :\n obtenu  %q (%v, %v)\n attendu %q (%v)", c.name, got, kind, ok, c.want, c.kind)
		}
	}
	if _, _, ok := FindHint("tout va bien"); ok {
		t.Error("aucun remède attendu")
	}
}

func TestRender(t *testing.T) {
	err := &Error{
		Kind:    Environment,
		Feature: "pg",
		Step:    "déployer le Cluster bigbox-pg",
		Cause:   errors.New(`webhook "mcluster.cnpg.io" injoignable (connection refused)`),
		Command: []string{"helm", "upgrade", "--install", "bigbox-pg", "cnpg/cluster", "0.9.0"},
		Hint:    "l'opérateur cnpg démarre encore ; relancez `bigbox apply`,\nou consultez `kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg`",
	}
	var b strings.Builder
	Render(&b, err, RenderOptions{
		Elapsed: 42 * time.Second,
		Journal: JournalRef{Path: "~/.local/state/bigbox/logs/2026-11-06T14-03-12-apply.jsonl", RunID: "7f3a"},
	})
	testutil.Golden(t, "render_step", b.String())

	b.Reset()
	Render(&b, errors.New("index hors limites"), RenderOptions{})
	testutil.Golden(t, "render_internal", b.String())

	b.Reset()
	Render(&b, errors.Join(
		&Error{Kind: Environment, Feature: "nats", Step: "retirer la release", Cause: errors.New("timeout")},
		&Error{Kind: Environment, Feature: "apt", Step: "purger les paquets", Stderr: []string{"E: paquet verrouillé"}},
	), RenderOptions{Journal: JournalRef{Path: "/j.jsonl", RunID: "ab12"}})
	testutil.Golden(t, "render_join", b.String())
}

func TestFormatDuration(t *testing.T) {
	for d, want := range map[time.Duration]string{
		850 * time.Millisecond: "850 ms",
		42 * time.Second:       "42 s",
		192 * time.Second:      "3 min 12 s",
		120 * time.Second:      "2 min",
	} {
		if got := FormatDuration(d); got != want {
			t.Errorf("%v : %q, attendu %q", d, got, want)
		}
	}
}

func TestTailLines(t *testing.T) {
	got := TailLines("a\n\nb\r\nc  \n", 2)
	if strings.Join(got, "|") != "b|c" {
		t.Errorf("TailLines = %q", got)
	}
}
