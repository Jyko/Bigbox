package run

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/Jyko/Bigbox/internal/errs"
	"github.com/Jyko/Bigbox/internal/log"
)

// Les tests de Exec ne lancent que sh, echo et sleep : jamais apt, systemctl ni sudo.

func newExec(journal *strings.Builder, secrets ...string) *Exec {
	r := log.NewRedactor()
	r.Add(secrets...)
	return &Exec{Logger: log.New(log.Options{Journal: journal, Redactor: r}), Redactor: r}
}

func TestExecCapture(t *testing.T) {
	var j strings.Builder
	e := newExec(&j)
	res, err := e.Run(context.Background(), Cmd{Args: []string{"sh", "-c", "echo sortie; echo erreur >&2"}})
	if err != nil {
		t.Fatal(err)
	}
	if res.Stdout != "sortie\n" || res.Stderr != "erreur\n" || res.ExitCode != 0 {
		t.Errorf("résultat inattendu : %+v", res)
	}
	// Le journal contient la commande et ses sorties même en cas de succès
	for _, want := range []string{log.EvCmdExec, log.EvCmdExit, `"stdout":"sortie\n"`, `"stderr":"erreur\n"`} {
		if !strings.Contains(j.String(), want) {
			t.Errorf("journal sans %q :\n%s", want, j.String())
		}
	}
}

func TestExecEchecTypéAvecRemède(t *testing.T) {
	var j strings.Builder
	e := newExec(&j)
	_, err := e.Run(context.Background(), Cmd{Args: []string{"sh", "-c",
		"echo 'E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 42 (apt)' >&2; exit 100"}})
	var te *errs.Error
	if !errors.As(err, &te) {
		t.Fatalf("*errs.Error attendue, obtenu %v", err)
	}
	var ee *ExitError
	if !errors.As(err, &ee) || ee.Code != 100 {
		t.Errorf("code 100 attendu : %v", err)
	}
	if te.Kind != errs.Conflict || !strings.Contains(te.Hint, "PID 42") || len(te.Stderr) != 1 {
		t.Errorf("erreur mal qualifiée : %+v", te)
	}
	if te.Command[0] != "sh" {
		t.Errorf("argv attendu dans l'erreur : %v", te.Command)
	}
}

func TestExecDélaiEtGroupe(t *testing.T) {
	var j strings.Builder
	e := newExec(&j)
	start := time.Now()
	// Le sleep enfant appartient au groupe : il est tué avec le shell
	_, err := e.Run(context.Background(), Cmd{Args: []string{"sh", "-c", "sleep 30 & wait"}, Timeout: 200 * time.Millisecond})
	if time.Since(start) > 3*time.Second {
		t.Fatalf("le délai n'a pas interrompu la commande (%v)", time.Since(start))
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("DeadlineExceeded attendu : %v", err)
	}
	var te *errs.Error
	if !errors.As(err, &te) || !strings.Contains(te.Hint, "délai") {
		t.Errorf("remède sur le délai attendu : %v", err)
	}
}

func TestExecAnnulation(t *testing.T) {
	var j strings.Builder
	e := newExec(&j)
	ctx, cancel := context.WithCancel(context.Background())
	time.AfterFunc(100*time.Millisecond, cancel)
	_, err := e.Run(ctx, Cmd{Args: []string{"sleep", "30"}})
	if !errors.Is(err, context.Canceled) || errs.ExitCode(err) != errs.ExitInterrupted {
		t.Errorf("annulation attendue (code 130) : %v", err)
	}
}

func TestExecProbe(t *testing.T) {
	var j strings.Builder
	e := newExec(&j)
	ctx := context.Background()
	if ok, err := e.Probe(ctx, Cmd{Args: []string{"true"}}); !ok || err != nil {
		t.Errorf("true : %v %v", ok, err)
	}
	if ok, err := e.Probe(ctx, Cmd{Args: []string{"false"}}); ok || err != nil {
		t.Errorf("false : un échec de condition n'est pas une erreur (%v %v)", ok, err)
	}
	_, err := e.Probe(ctx, Cmd{Args: []string{"bigbox-programme-inexistant"}})
	if errs.KindOf(err) != errs.Precondition {
		t.Errorf("programme absent : Precondition attendue, obtenu %v", err)
	}
}

func TestExecMasquage(t *testing.T) {
	const secret = "MotDePasse-Tres-Long"
	var j strings.Builder
	e := newExec(&j, secret)
	_, err := e.Run(context.Background(), Cmd{Args: []string{"sh", "-c", "echo " + secret + "; echo " + secret + " >&2; exit 1", secret}})
	if strings.Contains(j.String(), secret) {
		t.Errorf("secret dans le journal :\n%s", j.String())
	}
	var b strings.Builder
	errs.Render(&b, err, errs.RenderOptions{})
	if strings.Contains(b.String(), secret) || strings.Contains(err.Error(), secret) {
		t.Errorf("secret dans l'erreur :\n%s", b.String())
	}
}

func TestLimitedBuffer(t *testing.T) {
	var b limitedBuffer
	big := strings.Repeat("x", maxCapture)
	_, _ = b.Write([]byte(big))
	_, _ = b.Write([]byte("FIN"))
	if !strings.HasSuffix(b.String(), "FIN") || !strings.HasPrefix(b.String(), "[…sortie tronquée…]") {
		t.Error("la fin de la sortie doit être conservée")
	}
}

func TestFakeRunner(t *testing.T) {
	f := &FakeRunner{}
	f.On("dpkg-query", "-W", "htop").Stdout("install ok installed")
	f.On("apt-get", "install").Times(1).Exit(100, "E: Could not get lock /var/lib/apt/lists/lock")
	f.On("apt-get", "install")
	ctx := context.Background()

	if res, err := f.Run(ctx, Cmd{Args: []string{"dpkg-query", "-W", "htop"}}); err != nil || res.Stdout == "" {
		t.Errorf("règle dpkg-query : %v", err)
	}
	if _, err := AsRoot(ctx, f, Cmd{Args: []string{"apt-get", "install", "-y", "jq"}}); errs.KindOf(err) != errs.Conflict {
		t.Errorf("premier apt-get : conflit attendu, obtenu %v", err)
	}
	if _, err := AsRoot(ctx, f, Cmd{Args: []string{"apt-get", "install", "-y", "jq"}}); err != nil {
		t.Errorf("second apt-get : %v", err)
	}
	if _, err := f.Run(ctx, Cmd{Args: []string{"systemctl", "start", "k3s"}}); err == nil || !strings.Contains(err.Error(), "inattendue") {
		t.Errorf("commande sans règle : erreur attendue, obtenu %v", err)
	}
	want := []string{"dpkg-query -W htop", "[root] apt-get install -y jq", "[root] apt-get install -y jq", "systemctl start k3s"}
	if strings.Join(f.Commands(), "|") != strings.Join(want, "|") {
		t.Errorf("appels : %q", f.Commands())
	}
}
