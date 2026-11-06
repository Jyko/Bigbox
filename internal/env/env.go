// Package env détecte le contexte d'exécution (distribution, WSL2, conteneur, bureau) et
// calcule les chemins XDG de la Bigbox. Il est passé explicitement à chaque feature : aucune
// variable globale partagée.
package env

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/Jyko/Bigbox/internal/errs"
)

// MinUbuntu est la plus ancienne version d'Ubuntu supportée.
const MinUbuntu = "24.04"

// Env décrit la machine et les chemins de la Bigbox.
type Env struct {
	OSID        string // « ubuntu »
	OSVersion   string // « 24.04 »
	OSCodename  string // « noble »
	Arch        string // runtime.GOARCH
	IsWSL       bool
	IsContainer bool
	IsDesktop   bool // session graphique ou paquet ubuntu-desktop
	Home        string
	User        string
	Paths       Paths
}

// Paths regroupe les chemins de la Bigbox (XDG).
type Paths struct {
	ConfigDir string // ~/.config/bigbox
	Config    string // ~/.config/bigbox/bigbox.yaml
	StateDir  string // ~/.config/bigbox/state (registre de propriété, au même endroit que le Bash)
	Registry  string // ~/.config/bigbox/state/owned.json
	BashState string // ~/.config/bigbox/state/owned (format Bash)
	Lock      string // ~/.config/bigbox/state/lock
	LogDir    string // ~/.local/state/bigbox/logs
}

// Source abstrait le système de fichiers et l'environnement (tests sur une arborescence factice).
type Source struct {
	Root   string // préfixe des fichiers système lus ("" : /)
	Getenv func(string) string
	Arch   string
}

// Detect détecte le contexte réel.
func Detect(arch string) (*Env, error) {
	return Source{Getenv: os.Getenv, Arch: arch}.Detect()
}

// Detect détecte le contexte depuis la source.
func (s Source) Detect() (*Env, error) {
	getenv := s.Getenv
	if getenv == nil {
		getenv = func(string) string { return "" }
	}
	e := &Env{Arch: s.Arch, Home: getenv("HOME"), User: getenv("USER")}
	if e.Home == "" {
		return nil, &errs.Error{Kind: errs.Precondition, Op: "la variable HOME n'est pas définie"}
	}

	osr := readOSRelease(s.path("/etc/os-release"))
	e.OSID, e.OSVersion, e.OSCodename = osr["ID"], osr["VERSION_ID"], osr["VERSION_CODENAME"]

	proc, _ := os.ReadFile(s.path("/proc/sys/kernel/osrelease"))
	low := strings.ToLower(string(proc))
	e.IsWSL = getenv("WSL_DISTRO_NAME") != "" || strings.Contains(low, "microsoft") || strings.Contains(low, "wsl")

	e.IsContainer = exists(s.path("/.dockerenv")) || exists(s.path("/run/.containerenv")) ||
		getenv("container") != ""

	e.IsDesktop = !e.IsWSL && !e.IsContainer &&
		(getenv("XDG_CURRENT_DESKTOP") != "" || exists(s.path("/usr/share/doc/ubuntu-desktop")))

	cfg := getenv("XDG_CONFIG_HOME")
	if cfg == "" {
		cfg = filepath.Join(e.Home, ".config")
	}
	st := getenv("XDG_STATE_HOME")
	if st == "" {
		st = filepath.Join(e.Home, ".local", "state")
	}
	cd := filepath.Join(cfg, "bigbox")
	e.Paths = Paths{
		ConfigDir: cd,
		Config:    filepath.Join(cd, "bigbox.yaml"),
		StateDir:  filepath.Join(cd, "state"),
		Registry:  filepath.Join(cd, "state", "owned.json"),
		BashState: filepath.Join(cd, "state", "owned"),
		Lock:      filepath.Join(cd, "state", "lock"),
		LogDir:    filepath.Join(st, "bigbox", "logs"),
	}
	return e, nil
}

func (s Source) path(p string) string { return filepath.Join(s.Root, p) }

// CheckSupported vérifie que la machine est une Ubuntu supportée (précondition d'apply).
func (e *Env) CheckSupported() error {
	if e.OSID != "ubuntu" {
		return &errs.Error{Kind: errs.Precondition,
			Op:   fmt.Sprintf("système non supporté (%s %s)", orUnknown(e.OSID), e.OSVersion),
			Hint: "la Bigbox fonctionne sur Ubuntu " + MinUbuntu + " ou plus récent (poste, WSL2 ou conteneur)"}
	}
	if !versionAtLeast(e.OSVersion, MinUbuntu) {
		return &errs.Error{Kind: errs.Precondition,
			Op:   "Ubuntu " + e.OSVersion + " n'est pas supportée",
			Hint: "mettez à jour vers Ubuntu " + MinUbuntu + " ou plus récent"}
	}
	return nil
}

// Context résume le contexte pour l'affichage (« Ubuntu 24.04, WSL2 »).
func (e *Env) Context() string {
	s := fmt.Sprintf("%s %s", orUnknown(e.OSID), e.OSVersion)
	if e.OSID == "ubuntu" {
		s = "Ubuntu " + e.OSVersion
	}
	switch {
	case e.IsWSL:
		s += ", WSL2"
	case e.IsContainer:
		s += ", conteneur"
	case e.IsDesktop:
		s += ", bureau"
	}
	return s
}

func orUnknown(s string) string {
	if s == "" {
		return "inconnu"
	}
	return s
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func readOSRelease(path string) map[string]string {
	m := map[string]string{}
	f, err := os.Open(path)
	if err != nil {
		return m
	}
	defer func() { _ = f.Close() }()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		k, v, ok := strings.Cut(sc.Text(), "=")
		if !ok {
			continue
		}
		if u, err := strconv.Unquote(v); err == nil {
			v = u
		}
		m[k] = strings.Trim(v, `'`)
	}
	return m
}

// versionAtLeast compare deux versions « AA.MM ».
func versionAtLeast(v, min string) bool {
	parse := func(s string) (int, int) {
		a, b, _ := strings.Cut(s, ".")
		x, _ := strconv.Atoi(a)
		y, _ := strconv.Atoi(b)
		return x, y
	}
	va, vb := parse(v)
	ma, mb := parse(min)
	return va > ma || (va == ma && vb >= mb)
}
