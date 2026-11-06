package errs

import (
	"regexp"
	"strings"
)

// hintRule reconnaît un symptôme dans une sortie (stderr, message d'erreur) et propose un remède.
// Les groupes nommés de la regex sont substitués dans le remède : {{name}}.
type hintRule struct {
	kind Kind // type attribué à l'erreur quand la règle s'applique (Environment si zéro)
	re   *regexp.Regexp
	hint string
}

// Catalogue des remèdes, testé sur des sorties réelles (hints_test.go).
// L'ordre compte : la première règle qui correspond l'emporte.
var hintRules = []hintRule{
	{
		kind: Conflict,
		re:   regexp.MustCompile(`Could not get lock /var/lib/dpkg/lock(?:-frontend)?\. It is held by process (?P<pid>\d+) \((?P<proc>[^)]+)\)`),
		hint: "apt est utilisé par le processus {{proc}} (PID {{pid}}) ; attendez la fin des mises à jour automatiques puis relancez",
	},
	{
		kind: Conflict,
		re:   regexp.MustCompile(`Could not get lock /var/lib/(?:dpkg|apt/lists)/lock`),
		hint: "apt est utilisé par un autre processus ; attendez la fin des mises à jour automatiques puis relancez",
	},
	{
		kind: Precondition,
		re:   regexp.MustCompile(`sudo: (?:a terminal is required|a password is required|no tty present|il est nécessaire d'avoir un terminal)`),
		hint: "des étapes nécessitent root ; relancez dans un terminal interactif",
	},
	{
		kind: Precondition,
		re:   regexp.MustCompile(`(?:is not in the sudoers file|n'apparaît pas dans le fichier sudoers|incorrect password attempts?)`),
		hint: "sudo a été refusé ; vérifiez que votre compte a les droits sudo",
	},
	{
		re:   regexp.MustCompile(`webhook "[^"]*cnpg\.io"`),
		hint: "l'opérateur cnpg démarre encore ; relancez `bigbox apply`",
	},
	{
		re:   regexp.MustCompile(`(?:The connection to the server (?:127\.0\.0\.1|localhost):6443 was refused|dial tcp (?:127\.0\.0\.1|\[::1\]):6443: connect: connection refused)`),
		hint: "k3s ne répond pas ; `sudo systemctl status k3s` puis `journalctl -u k3s -n 50`",
	},
	{
		kind: Precondition,
		re:   regexp.MustCompile(`:(?P<port>\d+)(?:: bind: address already in use| failed: port is already allocated)`),
		hint: "le port {{port}} est déjà utilisé sur le poste ; libérez-le ou changez le port exposé dans bigbox.yaml",
	},
	{
		re:   regexp.MustCompile(`(?:Could not resolve host:? (?P<host>[^\s']+)|Temporary failure resolving '(?P<host2>[^']+)'|dial tcp: lookup (?P<host3>[^\s:]+))`),
		hint: "{{host}}{{host2}}{{host3}} injoignable ; vérifiez la connexion ou le proxy (`HTTPS_PROXY`)",
	},
	{
		re:   regexp.MustCompile(`sha256 (?:mismatch|différent)`),
		hint: "le fichier téléchargé ne correspond pas à la version épinglée ; ne pas forcer, signaler",
	},
	{
		kind: Precondition,
		re:   regexp.MustCompile(`No space left on device`),
		hint: "disque plein ; libérez de l'espace (`df -h`) puis relancez",
	},
}

// FindHint cherche un remède dans une sortie. Renvoie le remède et le type d'erreur associé.
func FindHint(output string) (hint string, kind Kind, ok bool) {
	for _, r := range hintRules {
		m := r.re.FindStringSubmatch(output)
		if m == nil {
			continue
		}
		h := r.hint
		for i, name := range r.re.SubexpNames() {
			if name != "" {
				h = strings.ReplaceAll(h, "{{"+name+"}}", m[i])
			}
		}
		k := r.kind
		if k == Internal {
			k = Environment
		}
		return h, k, true
	}
	return "", Internal, false
}
