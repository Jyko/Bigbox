package module

import (
	"context"
	"fmt"
)

type Check struct {
	Name string
	Fn   func(ctx context.Context) (bool, error)
}

type CheckResult struct {
	Name    string
	Checked bool
}

func RunChecks(ctx context.Context, checks []Check) (results []CheckResult, err error) {

	results = make([]CheckResult, len(checks))

	for _, check := range checks {
		checked, err := check.Fn(ctx)
		if err != nil {
			return results, fmt.Errorf("check %s failed: %w", check.Name, err)
		}
		results = append(results, CheckResult{Name: check.Name, Checked: checked})
	}

	return results, nil
}
