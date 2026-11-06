package spec

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"gopkg.in/yaml.v3"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/testutil"
)

// catalog factice : docker (non arrêtable), k3s (option autostart), pg (arrêtable)
type catalog map[string]Info

func (c catalog) Info(name string) (Info, bool) { i, ok := c[name]; return i, ok }

var testCatalog = catalog{
	"docker": {},
	"k3s": {ValidateOptions: func(n *yaml.Node) []Problem {
		var pbs []Problem
		for i := 0; i+1 < len(n.Content); i += 2 {
			k, v := n.Content[i], n.Content[i+1]
			switch {
			case k.Value != "autostart":
				pbs = append(pbs, Problem{Line: k.Line, Column: k.Column, Key: k.Value, Msg: ": option inconnue (admises : autostart)"})
			case v.Tag != "!!bool":
				pbs = append(pbs, Problem{Line: v.Line, Column: v.Column, Key: "autostart", Msg: "= " + v.Value + " invalide (admis : true, false)"})
			}
		}
		return pbs
	}},
	"pg": {Stoppable: true},
}

func TestParseValide(t *testing.T) {
	s, err := Parse("bigbox.yaml", []byte(`apiVersion: bigbox.dev/v1
profile: wsl
features:
  k3s:
    autostart: false
  pg:
    state: stopped
  docker:
    state: absent
`), testCatalog)
	if err != nil {
		t.Fatal(err)
	}
	if s.Profile != ProfileWSL {
		t.Errorf("profil : %s", s.Profile)
	}
	// docker vient du profil wsl mais est explicitement retiré
	if s.Features["docker"].State != Absent || !s.Features["docker"].Explicit {
		t.Errorf("docker : %+v", s.Features["docker"])
	}
	if s.Features["pg"].State != Stopped || s.Features["k3s"].Options == nil {
		t.Errorf("pg/k3s : %+v %+v", s.Features["pg"], s.Features["k3s"])
	}
	if strings.Join(s.Enabled(), " ") != "k3s pg" {
		t.Errorf("Enabled = %v", s.Enabled())
	}
}

func TestProfilFiltréSurLesFeaturesDisponibles(t *testing.T) {
	s, err := Parse("b.yaml", []byte("apiVersion: bigbox.dev/v1\nprofile: desktop\n"), testCatalog)
	if err != nil {
		t.Fatal(err)
	}
	// shell, qol et desktop ne sont pas encore portées : ignorées sans erreur
	if strings.Join(s.Enabled(), " ") != "docker k3s" {
		t.Errorf("Enabled = %v", s.Enabled())
	}
	if s.Features["docker"].Explicit {
		t.Error("une feature du profil n'est pas explicite")
	}
}

func TestParseVideEtAbsent(t *testing.T) {
	s, err := Parse("b.yaml", nil, testCatalog)
	if err != nil || s.Profile != ProfileMinimal || len(s.Features) != 0 {
		t.Errorf("fichier vide : %+v %v", s, err)
	}
	s, err = Load(filepath.Join(t.TempDir(), "absent.yaml"), testCatalog)
	if err != nil || s.Exists || s.Profile != ProfileMinimal {
		t.Errorf("fichier absent : %+v %v", s, err)
	}
}

// Toutes les erreurs d'un coup, avec position, clé, valeur reçue et valeurs admises.
func TestParseErreurs(t *testing.T) {
	_, err := Parse("~/.config/bigbox/bigbox.yaml", []byte(`apiVersion: bigbox.dev/v2
profile: laptop
couleur: bleu
features:
  pg:
    state: on
  docker:
    state: stopped
  hoppscotch: {}
  nats: {}
  inconnue: {}
  k3s:
    autostart: oui
    replicas: 3
`), testCatalog)
	if errs.KindOf(err) != errs.Config || errs.ExitCode(err) != errs.ExitUsage {
		t.Fatalf("erreur Config (code 2) attendue : %v", err)
	}
	var b strings.Builder
	errs.Render(&b, err, errs.RenderOptions{})
	testutil.Golden(t, "erreurs", b.String())
}

func TestParseYAMLIllisible(t *testing.T) {
	_, err := Parse("b.yaml", []byte("features: [\n"), testCatalog)
	if errs.KindOf(err) != errs.Config {
		t.Errorf("Config attendue : %v", err)
	}
	_, err = Parse("b.yaml", []byte("- a\n- b\n"), testCatalog)
	if errs.KindOf(err) != errs.Config {
		t.Errorf("Config attendue pour une liste : %v", err)
	}
}

func TestSetStatePréserveLesCommentaires(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bigbox.yaml")
	orig := `# Mon poste
apiVersion: bigbox.dev/v1
profile: wsl # profil WSL
features:
  # base de données
  pg:
    state: running # à arrêter le soir
  k3s:
    autostart: false
`
	if err := os.WriteFile(path, []byte(orig), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := SetState(path, "pg", Stopped); err != nil {
		t.Fatal(err)
	}
	if err := SetState(path, "docker", Absent); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(path)
	testutil.Golden(t, "setstate", string(got))

	s, err := Load(path, testCatalog)
	if err != nil {
		t.Fatal(err)
	}
	if s.Features["pg"].State != Stopped || s.Features["docker"].State != Absent || s.Features["k3s"].Options == nil {
		t.Errorf("relecture : %+v", s.Features)
	}
}

func TestSetStateCréeLeFichier(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sous", "bigbox.yaml")
	if err := SetState(path, "docker", Running); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(path)
	testutil.Golden(t, "setstate_nouveau", string(got))
	if s, err := Load(path, testCatalog); err != nil || s.Features["docker"].State != Running {
		t.Errorf("relecture : %v", err)
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0o600 {
		t.Errorf("droits : %v", info.Mode().Perm())
	}
}
