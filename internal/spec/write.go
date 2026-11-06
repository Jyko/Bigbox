package spec

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"

	"gopkg.in/yaml.v3"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/state"
)

// Template est le contenu d'un bigbox.yaml créé par la Bigbox.
const Template = `# État désiré de la Bigbox : décrivez ce que vous voulez, puis lancez « bigbox apply ».
# « bigbox plan » affiche l'écart avec la machine sans rien modifier.
apiVersion: bigbox.dev/v1
profile: minimal            # desktop | wsl | minimal : préremplit les features
features: {}
`

// SetState modifie features.<name>.state dans le fichier (créé s'il n'existe pas) en préservant
// les commentaires et le reste du document. Écriture atomique.
func SetState(path, name string, st State) error {
	data, err := WithStates(path, map[string]State{name: st})
	if err != nil {
		return err
	}
	return Write(path, data)
}

// WithStates renvoie le contenu du fichier (ou du modèle s'il n'existe pas) avec les états
// donnés, sans l'écrire : l'appelant peut valider le résultat avant de l'enregistrer.
func WithStates(path string, states map[string]State) ([]byte, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		data = []byte(Template)
	} else if err != nil {
		return nil, errs.Wrap(err, errs.Environment, "lecture de "+path)
	}
	names := make([]string, 0, len(states))
	for n := range states {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		if data, err = setState(data, n, states[n]); err != nil {
			return nil, configError(path, err)
		}
	}
	return data, nil
}

// Write enregistre bigbox.yaml de façon atomique (droits 600).
func Write(path string, data []byte) error {
	if err := state.WriteFileAtomic(path, data, 0o600); err != nil {
		return errs.Wrap(err, errs.Environment, "écriture de "+path)
	}
	return nil
}

func setState(data []byte, name string, st State) ([]byte, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return nil, fmt.Errorf("YAML illisible : %w", err)
	}
	if doc.Kind == 0 { // fichier vide
		if err := yaml.Unmarshal([]byte(Template), &doc); err != nil {
			return nil, err
		}
	}
	root := doc.Content[0]
	if root.Kind != yaml.MappingNode {
		return nil, errors.New("le document doit être un objet")
	}

	features := mapGet(root, "features")
	if features == nil || features.Kind != yaml.MappingNode {
		n := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
		if features == nil {
			mapSet(root, "features", n)
		} else {
			*features = *n
		}
		features = mapGet(root, "features")
	}
	features.Style = 0 // « features: {} » devient un bloc

	f := mapGet(features, name)
	if f == nil || f.Kind != yaml.MappingNode {
		n := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
		if f == nil {
			mapSet(features, name, n)
		} else {
			*f = *n
		}
		f = mapGet(features, name)
	}
	f.Style = 0
	mapSet(f, "state", &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: string(st)})

	var b bytes.Buffer
	enc := yaml.NewEncoder(&b)
	enc.SetIndent(2)
	if err := enc.Encode(&doc); err != nil {
		return nil, err
	}
	if err := enc.Close(); err != nil && !errors.Is(err, io.EOF) {
		return nil, err
	}
	return b.Bytes(), nil
}

func mapGet(m *yaml.Node, key string) *yaml.Node {
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			return m.Content[i+1]
		}
	}
	return nil
}

func mapSet(m *yaml.Node, key string, v *yaml.Node) {
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			// Valeur remplacée, commentaires de la valeur d'origine conservés
			v.LineComment, v.HeadComment, v.FootComment = m.Content[i+1].LineComment, m.Content[i+1].HeadComment, m.Content[i+1].FootComment
			m.Content[i+1] = v
			return
		}
	}
	m.Content = append(m.Content, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: key}, v)
}
