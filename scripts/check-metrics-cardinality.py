#!/usr/bin/env python3
"""Valida a fronteira de labels do scrape Prometheus do Backend.

Não duplica a allowlist finita de valores do Backend: verifica apenas que toda
label observada pertence ao vocabulário conhecido e que nenhum valor carrega
URL de origem, e-mail ou UUID — a cardinalidade/privacidade de DOMÍNIO
(operation/outcome/error_code/...) é de responsabilidade do Backend.
"""

import re
import sys

ALLOWED_LABELS = {
    "dependency",
    "error_code",
    "failure_class",
    "level",
    "method",
    "name",
    "notification_code",
    "operation",
    "outcome",
    "phase",
    "pool",
    "provider",
    "route_template",
    "stage",
    "state",
    "status_class",
}
FORBIDDEN_VALUE = re.compile(
    r"(?:https?://|\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b|"
    r"\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b)",
    re.IGNORECASE,
)
# A coluna de labels é tudo entre a primeira '{' e a ÚLTIMA '}' da linha; um
# template de rota pode conter '{produtoId}', então rsplit("}", 1) é obrigatório.
LABEL = re.compile(r'([a-zA-Z_][a-zA-Z0-9_]*)="((?:\\.|[^"\\])*)"')


def main() -> int:
    failed = False
    for line_number, line in enumerate(sys.stdin, 1):
        if line.startswith("#") or "{" not in line:
            continue
        labels = line.split("{", 1)[1].rsplit("}", 1)[0]
        for key, value in LABEL.findall(labels):
            if key not in ALLOWED_LABELS:
                print(f"label não allowlisted na linha {line_number}: {key}", file=sys.stderr)
                failed = True
            elif FORBIDDEN_VALUE.search(value):
                print(f"valor sensível na label {key}, linha {line_number}", file=sys.stderr)
                failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
