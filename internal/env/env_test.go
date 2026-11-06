package env

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/Jyko/Bigbox/internal/errs"
)

func fakeRoot(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for p, content := range files {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func getenv(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

const noble = "PRETTY_NAME=\"Ubuntu 24.04.3 LTS\"\nID=ubuntu\nVERSION_ID=\"24.04\"\nVERSION_CODENAME=noble\n"

func TestDetect(t *testing.T) {
	cases := []struct {
		name              string
		files             map[string]string
		vars              map[string]string
		wsl, ctr, desktop bool
		context           string
	}{
		{"serveur", map[string]string{"/etc/os-release": noble, "/proc/sys/kernel/osrelease": "6.8.0-45-generic"},
			map[string]string{"HOME": "/home/u"}, false, false, false, "Ubuntu 24.04"},
		{"wsl", map[string]string{"/etc/os-release": noble, "/proc/sys/kernel/osrelease": "5.15.167.4-microsoft-standard-WSL2"},
			map[string]string{"HOME": "/home/u", "XDG_CURRENT_DESKTOP": "x"}, true, false, false, "Ubuntu 24.04, WSL2"},
		{"conteneur", map[string]string{"/etc/os-release": noble, "/.dockerenv": ""},
			map[string]string{"HOME": "/root"}, false, true, false, "Ubuntu 24.04, conteneur"},
		{"bureau", map[string]string{"/etc/os-release": noble, "/usr/share/doc/ubuntu-desktop/copyright": ""},
			map[string]string{"HOME": "/home/u"}, false, false, true, "Ubuntu 24.04, bureau"},
	}
	for _, c := range cases {
		e, err := Source{Root: fakeRoot(t, c.files), Getenv: getenv(c.vars), Arch: "amd64"}.Detect()
		if err != nil {
			t.Fatalf("%s : %v", c.name, err)
		}
		if e.IsWSL != c.wsl || e.IsContainer != c.ctr || e.IsDesktop != c.desktop || e.Context() != c.context {
			t.Errorf("%s : %+v (%s)", c.name, e, e.Context())
		}
		if e.OSCodename != "noble" || e.CheckSupported() != nil {
			t.Errorf("%s : Ubuntu 24.04 doit être supportée", c.name)
		}
	}
}

func TestChemins(t *testing.T) {
	e, _ := Source{Root: t.TempDir(), Getenv: getenv(map[string]string{"HOME": "/home/u"})}.Detect()
	if e.Paths.Config != "/home/u/.config/bigbox/bigbox.yaml" ||
		e.Paths.Registry != "/home/u/.config/bigbox/state/owned.json" ||
		e.Paths.BashState != "/home/u/.config/bigbox/state/owned" ||
		e.Paths.LogDir != "/home/u/.local/state/bigbox/logs" {
		t.Errorf("chemins : %+v", e.Paths)
	}
	e, _ = Source{Root: t.TempDir(), Getenv: getenv(map[string]string{"HOME": "/h", "XDG_CONFIG_HOME": "/c", "XDG_STATE_HOME": "/s"})}.Detect()
	if e.Paths.Config != "/c/bigbox/bigbox.yaml" || e.Paths.LogDir != "/s/bigbox/logs" {
		t.Errorf("XDG non respecté : %+v", e.Paths)
	}
	if _, err := (Source{Root: t.TempDir(), Getenv: getenv(nil)}).Detect(); errs.KindOf(err) != errs.Precondition {
		t.Error("HOME absent : Precondition attendue")
	}
}

func TestSupport(t *testing.T) {
	for _, c := range []struct {
		id, version string
		ok          bool
	}{
		{"ubuntu", "24.04", true}, {"ubuntu", "26.04", true}, {"ubuntu", "24.10", true},
		{"ubuntu", "22.04", false}, {"debian", "13", false}, {"", "", false},
	} {
		err := (&Env{OSID: c.id, OSVersion: c.version}).CheckSupported()
		if (err == nil) != c.ok {
			t.Errorf("%s %s : %v", c.id, c.version, err)
		}
		if err != nil && errs.ExitCode(err) != errs.ExitPrecondition {
			t.Errorf("code 4 attendu : %v", err)
		}
	}
}
