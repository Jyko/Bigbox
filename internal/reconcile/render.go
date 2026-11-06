package reconcile

import (
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"github.com/Jyko/Bigbox/internal/feature"
	"github.com/Jyko/Bigbox/internal/spec"
)

// SchemaVersion est la version du schéma JSON de `plan --output json` et `status --output json`.
const SchemaVersion = 1

// RenderPlan écrit le plan façon `terraform plan` : + à créer, ~ à modifier, - à retirer,
// = conservé car préexistant.
func RenderPlan(w io.Writer, p *Plan) {
	counts := map[feature.Action]int{}
	for _, fp := range p.Features {
		for _, s := range fp.Steps {
			counts[s.Action]++
		}
	}
	if p.Changes() == 0 {
		fmt.Fprintln(w, "Aucun changement : la machine est conforme à bigbox.yaml.")
	} else {
		fmt.Fprintf(w, "Plan : %d à créer, %d à modifier, %d à retirer\n\n",
			counts[feature.Create], counts[feature.Update], counts[feature.Delete])
	}
	for _, fp := range p.Features {
		if len(fp.Steps) == 0 {
			continue
		}
		fmt.Fprintf(w, "%s %s%s\n", featureSymbol(fp), fp.Name, requiredBy(fp.Desired))
		for _, s := range fp.Steps {
			suffix := ""
			if s.Privileged && s.Action != feature.Keep {
				suffix = "  [root]"
			}
			fmt.Fprintf(w, "    %s %s%s\n", s.Action.Symbol(), s.Label, suffix)
			if s.Detail != "" {
				for _, l := range strings.Split(s.Detail, "\n") {
					fmt.Fprintf(w, "        %s\n", l)
				}
			}
		}
	}
	if priv := p.PrivilegedSteps(); len(priv) > 0 {
		fmt.Fprintf(w, "\n%d étape(s) nécessitent les droits administrateur (sudo sera demandé une seule fois).\n", len(priv))
	}
}

func featureSymbol(fp *FeaturePlan) string {
	if fp.Changes() == 0 {
		return "="
	}
	if fp.Phase == PhaseRemove {
		return "-"
	}
	for _, s := range fp.Steps {
		if s.Action == feature.Create {
			return "+"
		}
	}
	return "~"
}

func requiredBy(d feature.Desired) string {
	if len(d.RequiredBy) == 0 || d.Explicit {
		return ""
	}
	return "  (requise par " + strings.Join(d.RequiredBy, ", ") + ")"
}

// RenderStatus écrit l'état de chaque feature active ou à retirer, et la dérive.
func RenderStatus(w io.Writer, p *Plan, features *feature.Registry) {
	shown := 0
	for _, fp := range p.Features {
		if fp.Desired.State == spec.Absent && fp.Changes() == 0 {
			continue
		}
		shown++
		f, _ := features.Get(fp.Name)
		obs := ""
		if s, ok := fp.Observed.(fmt.Stringer); ok {
			obs = " : " + s.String()
		}
		mark, drift := "✓", "conforme"
		if n := fp.Changes(); n > 0 {
			mark, drift = "≠", fmt.Sprintf("%d écart(s)", n)
		}
		fmt.Fprintf(w, "%s %-10s %-8s %s%s  (%s)\n", mark, fp.Name, fp.Desired.State, drift, obs, f.Description())
	}
	if shown == 0 {
		fmt.Fprintln(w, "Aucune feature active.")
	}
	if p.Changes() > 0 {
		fmt.Fprintln(w, "\nDérive détectée : `bigbox plan` pour le détail, `bigbox apply` pour corriger.")
	}
}

// JSON du plan (schéma versionné, utilisé par les TU et d'éventuels scripts).
type jsonPlan struct {
	SchemaVersion int           `json:"schemaVersion"`
	Changes       int           `json:"changes"`
	Features      []jsonFeature `json:"features"`
}

type jsonFeature struct {
	Name       string     `json:"name"`
	Desired    string     `json:"desired"`
	Explicit   bool       `json:"explicit"`
	RequiredBy []string   `json:"requiredBy"`
	Phase      string     `json:"phase"`
	Changes    int        `json:"changes"`
	Observed   string     `json:"observed,omitempty"`
	Steps      []jsonStep `json:"steps"`
}

type jsonStep struct {
	ID         string `json:"id"`
	Label      string `json:"label"`
	Action     string `json:"action"`
	Privileged bool   `json:"privileged"`
	Detail     string `json:"detail,omitempty"`
}

// WriteJSON écrit le plan en JSON.
func WriteJSON(w io.Writer, p *Plan) error {
	out := jsonPlan{SchemaVersion: SchemaVersion, Changes: p.Changes(), Features: []jsonFeature{}}
	for _, fp := range p.Features {
		jf := jsonFeature{Name: fp.Name, Desired: string(fp.Desired.State), Explicit: fp.Desired.Explicit,
			RequiredBy: append([]string{}, fp.Desired.RequiredBy...), Phase: "converge", Changes: fp.Changes(), Steps: []jsonStep{}}
		if fp.Phase == PhaseRemove {
			jf.Phase = "remove"
		}
		if s, ok := fp.Observed.(fmt.Stringer); ok {
			jf.Observed = s.String()
		}
		for _, s := range fp.Steps {
			jf.Steps = append(jf.Steps, jsonStep{ID: s.ID, Label: s.Label, Action: s.Action.String(), Privileged: s.Privileged, Detail: s.Detail})
		}
		out.Features = append(out.Features, jf)
	}
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	return enc.Encode(out)
}
