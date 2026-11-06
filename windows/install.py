"""Configure Prisma's agent connections for the agents found on this PC."""
import sys

import agents


def detected(kind):
    if agents.cli_available(kind):
        return True
    folder = {
        'claude': agents.CLAUDE,
        'opencode': agents.OPENCODE,
        'muse': agents.MUSE,
        'antigravity': agents.ANTIGRAVITY,
    }.get(kind, agents.CODEX)
    return folder.exists()


def report(name, warnings):
    print(f'{name}: configuración incompleta.' if warnings else f'{name}: conexión configurada.')
    for warning in warnings:
        print(f'Aviso: {warning}')


def main():
    agents.ensure_support()
    report('Codex', agents.connect('codex'))
    for kind, name in (('claude', 'Claude Code'), ('opencode', 'OpenCode'),
                       ('muse', 'Muse Code'), ('antigravity', 'Antigravity')):
        if detected(kind):
            report(name, agents.connect(kind))
        else:
            print(f'{name} no detectado; ábrelo y conéctalo desde Ajustes → Agentes.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'No se pudieron configurar las integraciones: {error}', file=sys.stderr)
        raise SystemExit(1)
