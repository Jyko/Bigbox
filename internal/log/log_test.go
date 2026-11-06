package log

import (
	"bufio"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/testutil"
)

func TestRedactor(t *testing.T) {
	r := NewRedactor()
	r.Add("s3cr3t-pg", "abc") // "abc" trop court : ignoré
	cases := map[string]string{
		"psql password=s3cr3t-pg":                "psql password=«masqué»",
		"valeur s3cr3t-pg seule":                 "valeur «masqué» seule",
		"PGPASSWORD=hunter22 psql":               "PGPASSWORD=«masqué» psql",
		"Authorization: Bearer eyJhbGciOi.xyz":   "Authorization: Bearer «masqué»",
		`{"token": "tok-123"}`:                   `{"token": "«masqué»"}`,
		"https://user:mdp@registry.example/v2":   "https://user:«masqué»@registry.example/v2",
		"abc reste lisible, api_key=ZZZZ fin":    "abc reste lisible, api_key=«masqué» fin",
		"aucune donnée sensible, port 5432 open": "aucune donnée sensible, port 5432 open",
	}
	for in, want := range cases {
		if got := r.Redact(in); got != want {
			t.Errorf("Redact(%q) = %q, attendu %q", in, got, want)
		}
	}
	var nilR *Redactor
	if nilR.Redact("token=x1") != "token=«masqué»" {
		t.Error("un Redactor nil doit appliquer les motifs")
	}
}

// Un secret injecté dans argv, stdout et un message d'erreur n'apparaît dans aucune sortie.
func TestSecretAbsentDeToutesLesSorties(t *testing.T) {
	const secret = "Zx9-tres-secret-42"
	r := NewRedactor()
	r.Add(secret)

	var console, journal strings.Builder
	l := New(Options{Console: &console, ConsoleLevel: slog.LevelDebug, Journal: &journal, RunID: "r1", Redactor: r})
	l.Debug(EvCmdExec, KeyArgv, []string{"psql", "--password", secret})
	l.Debug(EvCmdExit, KeyExitCode, 1, KeyStdout, "sortie "+secret, KeyStderr, "erreur "+secret, KeyDuration, time.Second)
	l.Error("connexion refusée pour "+secret, KeyError, errors.New("auth "+secret))
	l.Info(EvStepEnd, KeyFeature, "pg", KeyLabel, "Création du rôle "+secret, KeyStatus, string(StatusFailed))

	for name, out := range map[string]string{"console": console.String(), "journal": journal.String()} {
		if strings.Contains(out, secret) {
			t.Errorf("secret présent dans la sortie %s :\n%s", name, out)
		}
		if !strings.Contains(out, Masked) {
			t.Errorf("valeur masquée absente de la sortie %s", name)
		}
	}
}

func TestJournalJSONL(t *testing.T) {
	var journal strings.Builder
	l := New(Options{Journal: &journal, RunID: "7f3a", Redactor: NewRedactor()})
	l.Debug(EvCmdExit, KeyArgv, []string{"true"}, KeyExitCode, 0, KeyDuration, 1500*time.Millisecond)

	var rec map[string]any
	if err := json.Unmarshal([]byte(journal.String()), &rec); err != nil {
		t.Fatalf("JSON invalide : %v\n%s", err, journal.String())
	}
	if rec["msg"] != EvCmdExit || rec[KeyRunID] != "7f3a" || rec["level"] != "DEBUG" {
		t.Errorf("enregistrement inattendu : %v", rec)
	}
	if rec[KeyDuration+"_ms"] != float64(1500) {
		t.Errorf("durée en ms attendue : %v", rec)
	}
}

func TestConsole(t *testing.T) {
	render := func(level slog.Level, interactive bool) string {
		var b strings.Builder
		l := New(Options{Console: &b, ConsoleLevel: level, Interactive: interactive, Redactor: NewRedactor()})
		l.Info(EvRunStart, KeyCommand, "apply")
		l.Info(EvFeatureStart, KeyFeature, "docker")
		l.Info(EvStepStart, KeyFeature, "docker", KeyLabel, "Installation des paquets Docker")
		l.Debug(EvCmdExec, KeyArgv, []string{"apt-get", "install", "-y", "docker-ce"})
		l.Debug(EvCmdExit, KeyExitCode, 0, KeyDuration, 12*time.Second)
		l.Info(EvStepEnd, KeyFeature, "docker", KeyLabel, "Installation des paquets Docker", KeyStatus, string(StatusChanged), KeyDuration, 12*time.Second)
		l.Info(EvStepStart, KeyFeature, "docker", KeyLabel, "Ajout au groupe docker")
		l.Info(EvStepEnd, KeyFeature, "docker", KeyLabel, "Ajout au groupe docker", KeyStatus, string(StatusFailed), KeyDuration, 2*time.Second)
		l.Info(EvStepEnd, KeyFeature, "docker", KeyLabel, "Activation du socket", KeyStatus, string(StatusSkipped), KeyError, "étape précédente en échec")
		l.Debug(EvFeatureEnd, KeyFeature, "k3s", KeyStatus, string(StatusOK))
		l.Warn("Le port 5432 est déjà utilisé", "port", 5432)
		l.Info("Message libre")
		return b.String()
	}
	testutil.Golden(t, "console_info", render(slog.LevelInfo, false))
	testutil.Golden(t, "console_debug", render(slog.LevelDebug, false))
	testutil.Golden(t, "console_tty", render(slog.LevelInfo, true))
	testutil.Golden(t, "console_quiet", render(slog.LevelError, false))
}

func TestSummary(t *testing.T) {
	var b strings.Builder
	RenderSummary(&b, Summary{
		Command:  "apply",
		Duration: 192 * time.Second,
		Counts:   map[Status]int{StatusOK: 14, StatusChanged: 6, StatusSkipped: 2, StatusFailed: 1},
		Failures: []string{"sftp › charger les utilisateurs"},
		NewTools: []string{"kubectl", "helm", "psql"},
		Journal:  errs.JournalRef{Path: "~/.local/state/bigbox/logs/2026-11-06T14-03-12-apply.jsonl"},
	})
	testutil.Golden(t, "summary", b.String())
}

func TestJournalRotation(t *testing.T) {
	dir := t.TempDir()
	start := time.Date(2026, 11, 6, 14, 0, 0, 0, time.UTC)
	for i := range KeepJournals + 5 {
		j, err := OpenJournal(dir, "apply", "r", start.Add(time.Duration(i)*time.Minute))
		if err != nil {
			t.Fatal(err)
		}
		_ = j.Close()
	}
	names, err := List(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(names) != KeepJournals {
		t.Fatalf("%d journaux conservés, attendu %d", len(names), KeepJournals)
	}
	if names[0] != "2026-11-06T14-05-00-apply.jsonl" {
		t.Errorf("les plus anciens doivent être retirés, premier = %s", names[0])
	}
	info, _ := os.Stat(filepath.Join(dir, names[0]))
	if info.Mode().Perm() != 0o600 {
		t.Errorf("droits du journal : %v", info.Mode().Perm())
	}
}

func TestReadJournal(t *testing.T) {
	dir := t.TempDir()
	j, err := OpenJournal(dir, "apply", "ab12", time.Now())
	if err != nil {
		t.Fatal(err)
	}
	l := New(Options{Journal: j, RunID: "ab12"})
	l.Info(EvStepEnd, KeyFeature, "f", KeyLabel, "étape", KeyStatus, string(StatusChanged))
	_ = j.Close()

	f, _ := os.Open(j.Path)
	defer f.Close()
	sc := bufio.NewScanner(f)
	n := 0
	for sc.Scan() {
		n++
	}
	if n != 1 {
		t.Errorf("%d lignes, attendu 1", n)
	}
}
