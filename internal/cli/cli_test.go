package cli

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/Jyko/Bigbox/features"
	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/state"
)

// Tests de bout en bout de la CLI, en processus, sur une arborescence factice : HOME et
// /etc/os-release dans un répertoire temporaire. Seule la feature essai est utilisée (fichier
// témoin dans ~/.config/bigbox, commande `sh`) : rien n'est modifié hors du répertoire de test.

type box struct {
	t    *testing.T
	root string
	home string
	vars map[string]string
}

func newBox(t *testing.T, osRelease string) *box {
	t.Helper()
	b := &box{t: t, root: t.TempDir(), home: t.TempDir()}
	if osRelease != "" {
		p := filepath.Join(b.root, "etc", "os-release")
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(osRelease), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	b.vars = map[string]string{"HOME": b.home, "USER": "test", "BIGBOX_ESSAI": "1", "NO_COLOR": "1"}
	return b
}

const noble = "ID=ubuntu\nVERSION_ID=\"24.04\"\nVERSION_CODENAME=noble\n"

type result struct {
	code           int
	stdout, stderr string
}

func (b *box) run(args ...string) result {
	b.t.Helper()
	var out, errOut strings.Builder
	a := &App{
		Build: Build{Version: "0.0.0-test"}, Stdin: strings.NewReader(""), Stdout: &out, Stderr: &errOut,
		Getenv: func(k string) string { return b.vars[k] }, Root: b.root, Features: features.All,
	}
	code := a.Run(context.Background(), args)
	if os.Getenv("BIGBOX_TEST_SHOW") != "" {
		b.t.Logf("$ bigbox %s  → code %d\n--- stdout ---\n%s--- stderr ---\n%s", strings.Join(args, " "), code, out.String(), errOut.String())
	}
	return result{code, out.String(), errOut.String()}
}

func (b *box) config(content string) {
	b.t.Helper()
	p := filepath.Join(b.home, ".config", "bigbox", "bigbox.yaml")
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		b.t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
		b.t.Fatal(err)
	}
}

func (b *box) temoin() string { return filepath.Join(b.home, ".config", "bigbox", "essai", "temoin") }

func expect(t *testing.T, r result, code int, contains ...string) {
	t.Helper()
	if r.code != code {
		t.Errorf("code %d, attendu %d\n--- stdout ---\n%s\n--- stderr ---\n%s", r.code, code, r.stdout, r.stderr)
	}
	for _, c := range contains {
		if !strings.Contains(r.stdout+r.stderr, c) {
			t.Errorf("sortie sans %q\n--- stdout ---\n%s\n--- stderr ---\n%s", c, r.stdout, r.stderr)
		}
	}
}

func TestVersionEtAide(t *testing.T) {
	b := newBox(t, noble)
	expect(t, b.run("version"), 0, "bigbox 0.0.0-test")
	expect(t, b.run("--help"), 0, "Codes de sortie", "130  interruption")
	expect(t, b.run("inconnue"), errs.ExitUsage, "ligne de commande invalide")
	expect(t, b.run("plan", "--option-inconnue"), errs.ExitUsage, "option invalide")
	expect(t, b.run("plan", "-v", "-q"), errs.ExitUsage, "incompatibles")
	expect(t, b.run("plan", "-o", "yaml"), errs.ExitUsage, `--output = "yaml" invalide`)
}

func TestPlanSansConfiguration(t *testing.T) {
	b := newBox(t, noble)
	r := b.run("plan")
	expect(t, r, 0, "absent : valeurs par défaut", "Aucun changement")
	names, _ := os.ReadDir(filepath.Join(b.home, ".local", "state", "bigbox", "logs"))
	if len(names) != 1 || !strings.HasSuffix(names[0].Name(), "-plan.jsonl") {
		t.Errorf("journal attendu : %v", names)
	}
	expect(t, b.run("plan", "--detailed-exitcode"), 0)
	expect(t, b.run("status"), 0, "Aucune feature active")
}

func TestConfigurationInvalide(t *testing.T) {
	b := newBox(t, noble)
	b.config("apiVersion: bigbox.dev/v1\nfeatures:\n  essai:\n    state: on\n  hoppscotch: {}\n")
	r := b.run("plan")
	expect(t, r, errs.ExitUsage, `bigbox.yaml:4:12 : features.essai.state = "on" invalide`,
		"features.hoppscotch : feature inconnue (retirée", "journal  :")
}

func TestCycleDeVie(t *testing.T) {
	b := newBox(t, noble)

	// enable : bigbox.yaml créé, fichier témoin créé et possédé
	r := b.run("enable", "essai", "--yes")
	expect(t, r, 0, "+ Création du fichier témoin", "bigbox.yaml mis à jour : essai → running",
		"Bigbox apply terminé", "1 modifié", "Journal : ~/.local/state/bigbox/logs/")
	if _, err := os.Stat(b.temoin()); err != nil {
		t.Fatalf("fichier témoin absent : %v", err)
	}
	reg, _ := state.Load(filepath.Join(b.home, ".config", "bigbox", "state", "owned.json"))
	if !reg.Owned(state.KindFile, b.temoin()) {
		t.Error("fichier témoin non enregistré dans le registre")
	}

	// Idempotence : second apply sans changement
	expect(t, b.run("plan", "--detailed-exitcode"), 0, "Aucun changement")
	expect(t, b.run("apply", "--yes"), 0, "Rien à faire")
	expect(t, b.run("status"), 0, "✓ essai")

	// JSON versionné
	r = b.run("plan", "-o", "json")
	var p map[string]any
	if err := json.Unmarshal([]byte(r.stdout), &p); err != nil || p["schemaVersion"] != float64(1) || p["changes"] != float64(0) {
		t.Errorf("JSON : %v %v\n%s", err, p, r.stdout)
	}

	// Dérive : fichier supprimé à la main
	_ = os.Remove(b.temoin())
	expect(t, b.run("status"), errs.ExitDrift, "≠ essai", "Dérive détectée")
	expect(t, b.run("plan", "--detailed-exitcode"), errs.ExitDrift, "+ Création du fichier témoin")
	expect(t, b.run("apply", "-y"), 0)

	// disable : fichier retiré, registre vidé
	expect(t, b.run("disable", "essai", "-y"), 0, "- Suppression du fichier témoin", "essai → absent")
	if _, err := os.Stat(b.temoin()); !os.IsNotExist(err) {
		t.Error("fichier témoin non supprimé")
	}
	reg, _ = state.Load(filepath.Join(b.home, ".config", "bigbox", "state", "owned.json"))
	if len(reg.Items("")) != 0 {
		t.Errorf("registre non vide : %v", reg.Items(""))
	}
}

func TestPréexistantConservé(t *testing.T) {
	b := newBox(t, noble)
	if err := os.MkdirAll(filepath.Dir(b.temoin()), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(b.temoin(), []byte("à moi"), 0o600); err != nil {
		t.Fatal(err)
	}
	b.config("apiVersion: bigbox.dev/v1\nfeatures:\n  essai: {state: absent}\n")
	expect(t, b.run("plan"), 0, "= Fichier témoin préexistant, conservé")
	expect(t, b.run("apply", "-y"), 0, "Rien à faire")
	if data, _ := os.ReadFile(b.temoin()); string(data) != "à moi" {
		t.Error("un fichier qui n'appartient pas à la Bigbox ne doit jamais être modifié")
	}
}

func TestÉchecRendu(t *testing.T) {
	b := newBox(t, noble)
	b.config("apiVersion: bigbox.dev/v1\nfeatures:\n  essai:\n    echec: true\n")
	r := b.run("apply", "--yes")
	expect(t, r, errs.ExitFailed,
		"✗ essai › Étape d'essai en échec  (échec après",
		"cause    : la commande sh a échoué : code de sortie 3",
		"commande : sh -c",
		"stderr   : essai : erreur simulée pour vérifier le rendu des erreurs",
		"à faire  : lisez stderr ci-dessus",
		"journal  : ~/.local/state/bigbox/logs/",
		"1 modifié", "1 échec", "✗ essai › Étape d'essai en échec   (voir ci-dessus)")

	// Le journal contient la sortie complète de la commande
	r = b.run("logs")
	expect(t, r, 0, "cmd.exit", "exit_code=3", "essai : début de la commande", "step.end", "status=échec")
	expect(t, b.run("logs", "--raw"), 0, `"msg":"cmd.exit"`)
	expect(t, b.run("logs", "--list"), 0, "-apply.jsonl")
	expect(t, b.run("logs", "--run", "inexistant"), errs.ExitUsage, "aucun journal pour le run")
}

func TestConfirmation(t *testing.T) {
	b := newBox(t, noble)
	b.config("apiVersion: bigbox.dev/v1\nfeatures:\n  essai: {}\n")
	expect(t, b.run("apply"), errs.ExitUsage, "confirmation impossible sans terminal", "--yes")
	if _, err := os.Stat(b.temoin()); !os.IsNotExist(err) {
		t.Error("rien ne doit être appliqué sans confirmation")
	}
}

func TestPréconditions(t *testing.T) {
	b := newBox(t, "ID=ubuntu\nVERSION_ID=\"22.04\"\n")
	expect(t, b.run("apply", "-y"), errs.ExitPrecondition, "Ubuntu 22.04 n'est pas supportée")

	b = newBox(t, noble)
	lock, err := state.Acquire(filepath.Join(b.home, ".config", "bigbox", "state", "lock"))
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = lock.Release() }()
	expect(t, b.run("enable", "essai", "-y"), errs.ExitPrecondition, "une autre exécution de la Bigbox est en cours")
}

func TestEnableInconnu(t *testing.T) {
	b := newBox(t, noble)
	expect(t, b.run("enable", "pg", "-y"), errs.ExitUsage, "feature inconnue : pg", "features disponibles : essai")
	expect(t, b.run("stop", "essai", "-y"), errs.ExitUsage, "essai ne s'arrête pas")
	expect(t, b.run("enable"), errs.ExitUsage, "au moins une feature")
	if _, err := os.Stat(filepath.Join(b.home, ".config", "bigbox", "bigbox.yaml")); !os.IsNotExist(err) {
		t.Error("bigbox.yaml ne doit pas être créé par une commande refusée")
	}
}
