// title-hook.mjs — set the Claude Code session title to the active ticket.
//
// Wired (in settings) as BOTH a SessionStart and a UserPromptSubmit hook. It reads the
// hook payload from stdin and, when this is a ticket session, prints a single
// `hookSpecificOutput.sessionTitle` JSON object. Setting the title from a hook is the
// supported mechanism (same effect as /rename) and survives Claude Code's automatic
// title generation — unlike poking session files, which races it and loses.
//
// How it learns the ticket:
//   • UserPromptSubmit — if the submitted prompt is a `*-ticket` slash command or a bare
//     "PROJ-123", the ticket id is taken straight from the prompt and remembered for THIS
//     session (keyed by session_id). So `/complete-ticket PROJ-123` sets the title on the
//     very submission, before the skill runs and long before any branch exists.
//   • Any later prompt, and SessionStart on `claude -r` resume — the remembered ticket id
//     for this session is read back from .claude/title-state/<session_id>.
//
// Title text: the ticket id, upgraded to "PROJ-123 — <tracker title>" once understand-ticket
// has cached the title in .claude/tickets/<ticket>.json.
//
// It prints NOTHING (and never throws) when this is not a ticket session or on any error,
// so a non-ticket chat keeps Claude's auto-generated title and a prompt is never blocked.

import fs from 'fs';
import path from 'path';

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

try {
  const raw = readStdin();
  if (!raw.trim()) {
    process.exit(0);
  }
  const input = JSON.parse(raw);

  const cwd = input.cwd;
  const sessionId = input.session_id;
  const event = input.hook_event_name || 'UserPromptSubmit';
  if (!cwd || !sessionId) {
    process.exit(0);
  }

  const stateDir = path.join(cwd, '.claude', 'title-state');
  const stateFile = path.join(stateDir, `${sessionId}.txt`);

  let ticket = null;

  // 1) On a prompt submission, learn the ticket from the prompt itself — only when it is a
  //    slash command that carries a ticket (e.g. /complete-ticket PROJ-1, /address-review PROJ-1,
  //    /new-branch "PROJ-1 …") or a bare ticket id / tracker browse URL on its own — so a casual
  //    "PROJ-123" mentioned in normal chat never hijacks the title.
  if (typeof input.prompt === 'string') {
    const p = input.prompt;
    const slashWithTicket = /^\s*\/[a-z][\w-]*\b[^\n]*\bPROJ-\d+\b/i;
    const bareTicket = /^\s*(?:https?:\/\/\S*\/browse\/)?PROJ-\d+\s*$/i;
    const m = p.match(/PROJ-\d+/i);
    if (m && (slashWithTicket.test(p) || bareTicket.test(p))) {
      ticket = m[0].toUpperCase();
      try {
        fs.mkdirSync(stateDir, { recursive: true });
        fs.writeFileSync(stateFile, ticket);
      } catch {
        // remembering is best-effort; the title still applies to this turn
      }
    }
  }

  // 2) Otherwise recall the ticket remembered for this session (later prompts + resume).
  if (!ticket) {
    try {
      ticket = fs.readFileSync(stateFile, 'utf8').trim() || null;
    } catch {
      ticket = null;
    }
  }

  if (!ticket) {
    process.exit(0); // not a ticket session — leave the auto-generated title alone
  }

  // 3) Compose the title: "PROJ-123 — <tracker title>" once cached, else just "PROJ-123".
  let title = ticket;
  try {
    const ticketFile = path.join(cwd, '.claude', 'tickets', `${ticket}.json`);
    const data = JSON.parse(fs.readFileSync(ticketFile, 'utf8'));
    if (data && typeof data.title === 'string' && data.title.trim()) {
      title = `${ticket} — ${data.title.trim()}`;
    }
  } catch {
    // no cached tracker title yet — the bare ticket id is fine until understand-ticket runs
  }

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: event, sessionTitle: title },
  }));
} catch {
  // Never block a prompt or a session start, whatever happens.
}
process.exit(0);
