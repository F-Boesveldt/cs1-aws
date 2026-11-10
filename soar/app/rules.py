"""Rule engine: load the playbook and find the rules that match an event."""
import yaml


def load_rules(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)["rules"]


def rule_matches(rule, event):
    for key, wanted in (rule.get("match") or {}).items():
        value = event.get(key)
        if isinstance(wanted, list):
            if value not in wanted:
                return False
        elif value != wanted:
            return False
    return True


def matching_rules(rules, event):
    """Return the matching rules. A catch-all rule (empty match) only
    applies when no specific rule matched."""
    specific = [r for r in rules if r.get("match") and rule_matches(r, event)]
    if specific:
        return specific
    return [r for r in rules if not r.get("match")]
