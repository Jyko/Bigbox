// Package spec définit l'état désiré de la Bigbox : ~/.config/bigbox/bigbox.yaml.
//
// L'utilisateur décrit ce qu'il veut ; la réconciliation calcule et applique l'écart. Les erreurs
// de validation sont toutes rapportées d'un coup, avec fichier:ligne:colonne, la clé fautive, la
// valeur reçue et les valeurs admises.
package spec

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"

	"github.com/Jyko/Bigbox/internal/errs"
)

// APIVersion est la version du schéma de bigbox.yaml.
const APIVersion = "bigbox.dev/v1"

// State est l'état désiré d'une feature.
type State string

// États admis.
const (
	Running State = "running"
	Stopped State = "stopped"
	Absent  State = "absent"
)

// States liste les états admis, dans l'ordre d'affichage.
var States = []State{Running, Stopped, Absent}

// Profile préremplit les features.
type Profile string

// Profils admis.
const (
	ProfileMinimal Profile = "minimal"
	ProfileWSL     Profile = "wsl"
	ProfileDesktop Profile = "desktop"
)

// Profiles liste les profils admis.
var Profiles = []Profile{ProfileDesktop, ProfileWSL, ProfileMinimal}

// profileFeatures : features activées par défaut par chaque profil (filtrées sur les features
// disponibles dans ce binaire : pendant la migration, toutes ne sont pas encore portées).
var profileFeatures = map[Profile][]string{
	ProfileMinimal: nil,
	ProfileWSL:     {"docker", "k3s", "shell", "qol"},
	ProfileDesktop: {"docker", "k3s", "shell", "qol", "desktop"},
}

// Feature est la déclaration d'une feature dans bigbox.yaml.
type Feature struct {
	Name     string
	State    State
	Explicit bool       // déclarée dans le fichier (sinon apportée par le profil)
	Options  *yaml.Node // options propres à la feature (mapping sans la clé state), nil si aucune
	Line     int
	Column   int
}

// Spec est l'état désiré, profil appliqué.
type Spec struct {
	Path     string
	Exists   bool // le fichier existe (sinon : valeurs par défaut)
	Profile  Profile
	Features map[string]*Feature // features déclarées ou apportées par le profil
}

// Catalog décrit les features connues de ce binaire (implémenté par le registre des features).
type Catalog interface {
	// Info renvoie les caractéristiques d'une feature, ok=false si elle est inconnue.
	Info(name string) (Info, bool)
}

// Info décrit ce qu'une feature accepte dans bigbox.yaml.
type Info struct {
	Stoppable bool // accepte state: stopped
	// ValidateOptions valide les options propres à la feature (nil : aucune option admise).
	ValidateOptions func(node *yaml.Node) []Problem
}

// Features retirées ou remplacées : message dédié plutôt que « inconnue ».
var retired = map[string]string{
	"hoppscotch": "retirée, voir migration.md 12.1",
	"nui":        "remplacée par l'application de bureau NUI (profil desktop)",
	"k8s":        "renommée k3s",
	"core":       "intégrée à la Bigbox, rien à déclarer",
	"system":     "intégrée à la Bigbox, rien à déclarer",
	"starship":   "regroupée dans la feature shell",
	"catppucin":  "regroupée dans la feature shell",
}

// Features prévues par la migration mais pas encore portées dans ce binaire.
var planned = []string{"docker", "k3s", "cnpg", "pg", "nats", "wiremock", "sftp", "shell", "qol", "desktop"}

// Problem est une erreur de validation localisée.
type Problem struct {
	Line, Column int
	Key          string // ex. features.pg.state
	Msg          string
}

// Problems est l'ensemble des erreurs de validation d'un fichier.
type Problems struct {
	Path string
	List []Problem
}

func (p *Problems) Error() string {
	lines := make([]string, len(p.List))
	for i, pb := range p.List {
		lines[i] = p.format(pb)
	}
	return strings.Join(lines, "\n")
}

func (p *Problems) format(pb Problem) string {
	loc := p.Path
	if pb.Line > 0 {
		loc = fmt.Sprintf("%s:%d:%d", p.Path, pb.Line, pb.Column)
	}
	if pb.Key != "" {
		return fmt.Sprintf("%s : %s %s", loc, pb.Key, pb.Msg)
	}
	return fmt.Sprintf("%s : %s", loc, pb.Msg)
}

func (p *Problems) add(n *yaml.Node, key, format string, args ...any) {
	pb := Problem{Key: key, Msg: fmt.Sprintf(format, args...)}
	if n != nil {
		pb.Line, pb.Column = n.Line, n.Column
	}
	p.List = append(p.List, pb)
}

// Default renvoie la spec par défaut (fichier absent) : profil minimal, aucune feature.
func Default(path string) *Spec {
	return &Spec{Path: path, Profile: ProfileMinimal, Features: map[string]*Feature{}}
}

// Load lit et valide bigbox.yaml. Un fichier absent donne la spec par défaut.
func Load(path string, cat Catalog) (*Spec, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return Default(path), nil
	}
	if err != nil {
		return nil, errs.Wrap(err, errs.Environment, "lecture de "+path)
	}
	s, err := Parse(path, data, cat)
	if err != nil {
		return nil, err
	}
	s.Exists = true
	return s, nil
}

// Parse valide le contenu de bigbox.yaml.
func Parse(path string, data []byte, cat Catalog) (*Spec, error) {
	s := Default(path)
	pbs := &Problems{Path: path}

	var doc yaml.Node
	dec := yaml.NewDecoder(bytes.NewReader(data))
	if err := dec.Decode(&doc); err != nil {
		if errors.Is(err, io.EOF) {
			return s, nil // fichier vide : valeurs par défaut
		}
		return nil, configError(path, fmt.Errorf("YAML illisible : %w", err))
	}
	root := &doc
	if root.Kind == yaml.DocumentNode && len(root.Content) == 1 {
		root = root.Content[0]
	}
	if root.Kind != yaml.MappingNode {
		pbs.add(root, "", "le document doit être un objet (apiVersion, profile, features)")
		return nil, configError(path, pbs)
	}

	var featuresNode *yaml.Node
	seenAPI := false
	for i := 0; i+1 < len(root.Content); i += 2 {
		k, v := root.Content[i], root.Content[i+1]
		switch k.Value {
		case "apiVersion":
			seenAPI = true
			if v.Value != APIVersion {
				pbs.add(v, "apiVersion", "= %q invalide (admis : %s)", v.Value, APIVersion)
			}
		case "profile":
			if !contains(Profiles, Profile(v.Value)) {
				pbs.add(v, "profile", "= %q invalide (admis : %s)", v.Value, join(Profiles))
			} else {
				s.Profile = Profile(v.Value)
			}
		case "features":
			featuresNode = v
		default:
			pbs.add(k, k.Value, ": clé inconnue (admises : apiVersion, profile, features)")
		}
	}
	if !seenAPI {
		pbs.add(root, "apiVersion", "manquant (attendu : %s)", APIVersion)
	}

	// Profil d'abord, puis déclarations du fichier (qui l'emportent)
	for _, name := range profileFeatures[s.Profile] {
		if _, ok := cat.Info(name); ok {
			s.Features[name] = &Feature{Name: name, State: Running}
		}
	}

	if featuresNode != nil {
		switch featuresNode.Kind {
		case yaml.MappingNode:
			for i := 0; i+1 < len(featuresNode.Content); i += 2 {
				parseFeature(s, pbs, cat, featuresNode.Content[i], featuresNode.Content[i+1])
			}
		case yaml.ScalarNode:
			if featuresNode.Tag != "!!null" {
				pbs.add(featuresNode, "features", "doit être un objet (nom de feature → options)")
			}
		default:
			pbs.add(featuresNode, "features", "doit être un objet (nom de feature → options)")
		}
	}

	if len(pbs.List) > 0 {
		sort.SliceStable(pbs.List, func(i, j int) bool {
			a, b := pbs.List[i], pbs.List[j]
			return a.Line < b.Line || (a.Line == b.Line && a.Column < b.Column)
		})
		return nil, configError(path, pbs)
	}
	return s, nil
}

func parseFeature(s *Spec, pbs *Problems, cat Catalog, k, v *yaml.Node) {
	name := k.Value
	key := "features." + name
	info, known := cat.Info(name)
	if !known {
		switch {
		case retired[name] != "":
			pbs.add(k, key, ": feature inconnue (%s)", retired[name])
		case contains(planned, name):
			pbs.add(k, key, ": pas encore disponible dans cette version de la Bigbox Go (migration en cours)")
		default:
			pbs.add(k, key, ": feature inconnue")
		}
		return
	}
	f := &Feature{Name: name, State: Running, Explicit: true, Line: k.Line, Column: k.Column}

	switch {
	case v.Kind == yaml.ScalarNode && v.Tag == "!!null":
		// « docker: » ou « docker: {} » : activée avec les valeurs par défaut
	case v.Kind == yaml.MappingNode:
		opts := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map", Line: v.Line, Column: v.Column}
		for i := 0; i+1 < len(v.Content); i += 2 {
			ok, ov := v.Content[i], v.Content[i+1]
			if ok.Value == "state" {
				st := State(ov.Value)
				switch {
				case !contains(States, st):
					pbs.add(ov, key+".state", "= %q invalide (admis : %s)", ov.Value, join(States))
				case st == Stopped && !info.Stoppable:
					pbs.add(ov, key+".state", "= %q invalide : %s ne s'arrête pas (admis : running, absent)", ov.Value, name)
				default:
					f.State = st
				}
				continue
			}
			opts.Content = append(opts.Content, ok, ov)
		}
		if len(opts.Content) > 0 {
			f.Options = opts
			if info.ValidateOptions == nil {
				for i := 0; i < len(opts.Content); i += 2 {
					pbs.add(opts.Content[i], key+"."+opts.Content[i].Value, ": option inconnue (seule state est admise)")
				}
			} else {
				for _, pb := range info.ValidateOptions(opts) {
					if !strings.HasPrefix(pb.Key, key) {
						pb.Key = key + "." + pb.Key
					}
					pbs.List = append(pbs.List, pb)
				}
			}
		}
	default:
		pbs.add(v, key, "doit être un objet (ex. %s: { state: running })", name)
	}
	s.Features[name] = f
}

func configError(path string, cause error) error {
	return &errs.Error{
		Kind:  errs.Config,
		Op:    path + " invalide",
		Cause: cause,
		Hint:  "corrigez le fichier puis relancez ; `bigbox plan` vérifie le fichier sans rien modifier",
	}
}

// Enabled renvoie les features dont l'état désiré n'est pas absent, triées.
func (s *Spec) Enabled() []string {
	var out []string
	for n, f := range s.Features {
		if f.State != Absent {
			out = append(out, n)
		}
	}
	sort.Strings(out)
	return out
}

func contains[T comparable](list []T, v T) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

func join[T ~string](list []T) string {
	s := make([]string, len(list))
	for i, v := range list {
		s[i] = string(v)
	}
	return strings.Join(s, ", ")
}
