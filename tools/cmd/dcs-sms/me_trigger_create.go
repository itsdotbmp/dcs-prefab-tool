package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"time"
)

func init() {
	registerMe("trigger", "create", meTriggerCreateCmd)
}

// meTriggerCreateCmd implements
// `dcs-sms me trigger create --type once|continuous|start|front [--name N]
//   [--condition "<predicate> k=v..."]... [--action "<predicate> k=v..."]...`.
//
// Inserts a trigger; optionally bundles initial conditions and actions in the
// same call. Each --condition / --action takes a single string of
// "<predicate> <k>=<v> <k>=<v>..." tokens — same vocabulary as the standalone
// add-condition / add-action verbs. Limitation: values containing literal
// spaces need shell-quoting (text='Hello World') or use the composable form.
func meTriggerCreateCmd(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("me trigger create", flag.ContinueOnError)
	fs.SetOutput(stderr)
	var (
		flagType       = fs.String("type", "", "trigger type: once|continuous|start|front")
		flagName       = fs.String("name", "", "trigger name (defaults to \"Trigger <epoch>\")")
		flagTimeout    = fs.Duration("timeout", 30*time.Second, "wall-clock timeout")
		flagPretty     = fs.Bool("pretty", false, "indent JSON output")
		flagSavedGames = fs.String("saved-games", "", "override Saved Games path")
		flagConditions stringSliceFlag
		flagActions    stringSliceFlag
	)
	fs.Var(&flagConditions, "condition", `bundled condition (repeatable): "<predicate> k=v..."`)
	fs.Var(&flagActions, "action", `bundled action (repeatable): "<predicate> k=v..."`)
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if *flagType == "" {
		fmt.Fprintln(stderr, "dcs-sms me trigger create: --type is required")
		return 2
	}

	// Pre-validate every bundled rule string so we fail BEFORE creating the
	// trigger if any rule is malformed.
	type parsedRule struct {
		pred   string
		fields map[string]string
	}
	cond := make([]parsedRule, 0, len(flagConditions))
	for _, s := range flagConditions {
		p, f, err := parseBundledRuleString(s)
		if err != nil {
			fmt.Fprintln(stderr, "dcs-sms me trigger create:", err)
			return 2
		}
		cond = append(cond, parsedRule{p, f})
	}
	act := make([]parsedRule, 0, len(flagActions))
	for _, s := range flagActions {
		p, f, err := parseBundledRuleString(s)
		if err != nil {
			fmt.Fprintln(stderr, "dcs-sms me trigger create:", err)
			return 2
		}
		act = append(act, parsedRule{p, f})
	}

	// 1) Create the empty trigger.
	luaArgs := fmt.Sprintf("{ [\"type\"] = %q, name = %q }", *flagType, *flagName)
	resp, exitCode := runMeVerb("trigger_create", luaArgs, *flagTimeout, *flagSavedGames, stderr)
	if exitCode != 0 {
		return exitCode
	}
	if !resp.OK {
		// Surface the verb error and stop — don't try to add rules.
		return emitMeResponse(resp, *flagPretty, stdout)
	}

	// Extract the resolved name from the response so the bundled add-*
	// calls target the right trigger (the user's --name might have been
	// auto-suffixed). resp.ReturnValue is json.RawMessage — decode it.
	resolvedName := *flagName
	if len(resp.ReturnValue) > 0 {
		var rv map[string]any
		if err := json.Unmarshal(resp.ReturnValue, &rv); err == nil {
			if n, ok := rv["name"].(string); ok && n != "" {
				resolvedName = n
			}
		}
	}

	// 2) Apply each bundled condition.
	for _, r := range cond {
		condArgs := fmt.Sprintf(
			"{ trigger = %q, predicate = %q, fields = %s }",
			resolvedName, r.pred, buildLuaFieldsExpr(r.fields))
		condResp, ec := runMeVerb("trigger_add_condition", condArgs, *flagTimeout, *flagSavedGames, stderr)
		if ec != 0 {
			return ec
		}
		if !condResp.OK {
			// Bundled rule failed mid-stream; surface the partial state.
			return emitMeResponse(condResp, *flagPretty, stdout)
		}
		// Outer OK only confirms the Lua snippet ran — the verb itself may
		// still have rejected the rule (unknown predicate, missing field,
		// etc.). Inspect the inner return_value.ok to surface those.
		if len(condResp.ReturnValue) > 0 {
			var rv map[string]any
			if err := json.Unmarshal(condResp.ReturnValue, &rv); err == nil {
				if ok, _ := rv["ok"].(bool); !ok {
					return emitMeResponse(condResp, *flagPretty, stdout)
				}
			}
		}
	}

	// 3) Apply each bundled action.
	for _, r := range act {
		actArgs := fmt.Sprintf(
			"{ trigger = %q, predicate = %q, fields = %s }",
			resolvedName, r.pred, buildLuaFieldsExpr(r.fields))
		actResp, ec := runMeVerb("trigger_add_action", actArgs, *flagTimeout, *flagSavedGames, stderr)
		if ec != 0 {
			return ec
		}
		if !actResp.OK {
			return emitMeResponse(actResp, *flagPretty, stdout)
		}
		// Same inner-ok guard as for conditions above.
		if len(actResp.ReturnValue) > 0 {
			var rv map[string]any
			if err := json.Unmarshal(actResp.ReturnValue, &rv); err == nil {
				if ok, _ := rv["ok"].(bool); !ok {
					return emitMeResponse(actResp, *flagPretty, stdout)
				}
			}
		}
	}

	// Success — return the original create response (which has the trigger
	// name + index). Bundled rules count is implicit.
	return emitMeResponse(resp, *flagPretty, stdout)
}
