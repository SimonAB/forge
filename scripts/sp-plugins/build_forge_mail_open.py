#!/usr/bin/env python3
"""Build the Forge mail-open Super Productivity plugin zip."""

from __future__ import annotations

import json
import shutil
import zipfile
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parent / "forge-mail-open"
ZIP_PATH = Path(__file__).resolve().parent / "forge-mail-open.zip"
ICON_SRC = Path(__file__).resolve().parent / "forge-bulk-projects" / "icon.svg"

PLUGIN_JS = r"""// Forge Mail Open — permanent Links & Files row + header button.
//
// Links & Files: FILE attachment titled "Open in Mail" (mail icon) pointing at
// a static HTML trampoline under Forge `.forge/mail-open/` (same pattern as the
// NERC superspreader example). Synced on boot and when mail-linked tasks change.
//
// Header button: opens Apple Mail by Message-Id via AppleScript (Mail message
// object; no message:// Launch Services; no HTML). Prefer this for opening.
// Clicking the Links & Files row may flash the default browser (SP opens FILE).

const URI_COMMENT = /<!--\s*forge:uri:([^\s*]+?)\s*-->/i;
const URI_BRACKET = /\[forge:uri:([^\]]+)\]/i;
const BARE_MESSAGE = /(?:^|\n)\s*(message:[^\s]+)/i;
const MAIL_HTML_COMMENT = /<!--\s*forge:mail-html:([^\s*]+?)\s*-->/i;
const ATTACH_TITLE = 'Open in Mail';

function forgeHomePath() {
  // Prefer env; else the standard Forge dogfood home.
  try {
    if (typeof process !== 'undefined' && process.env && process.env.FORGE_HOME) {
      return String(process.env.FORGE_HOME);
    }
  } catch (err) {
    /* ignore */
  }
  return null;
}

function normalizeMailUri(uri) {
  const text = (uri || '').trim();
  const lower = text.toLowerCase();
  if (lower.startsWith('message://')) return text;
  if (lower.startsWith('message:')) {
    return 'message://' + text.slice('message:'.length).replace(/^\/+/, '');
  }
  return text;
}

function messageIdFromUri(uri) {
  let text = normalizeMailUri(uri).replace(/^message:\/*/i, '');
  try {
    text = decodeURIComponent(text);
  } catch (err) {
    /* keep raw */
  }
  return text.replace(/^</, '').replace(/>$/, '').trim();
}

function parseMailUri(notes) {
  const text = notes || '';
  const uriComment = text.match(URI_COMMENT);
  if (uriComment) return normalizeMailUri(uriComment[1].trim());
  const uriBracket = text.match(URI_BRACKET);
  if (uriBracket) return normalizeMailUri(uriBracket[1].trim());
  const bare = text.match(BARE_MESSAGE);
  if (bare) return normalizeMailUri(bare[1].trim());
  return null;
}

function parseMailHtmlPath(notes) {
  const match = (notes || '').match(MAIL_HTML_COMMENT);
  return match ? match[1].trim() : null;
}

function errorMessage(result) {
  if (!result) return 'no result';
  const err = result.error;
  if (!err) return 'nodeExecution failed';
  if (typeof err === 'string') return err;
  if (err.code === 'NO_CONSENT' || err.code === 'PERMISSION_DENIED') {
    return 'Allow Node execution for Forge Mail Open (Settings → Plugins), then try again.';
  }
  return err.message || String(err);
}

async function ensureTrampolineFile(mailUri, existingHtmlPath) {
  if (typeof PluginAPI.executeNodeScript !== 'function') {
    return { ok: false, reason: 'executeNodeScript unavailable' };
  }
  const result = await PluginAPI.executeNodeScript({
    script: `
      const fs = require('fs');
      const path = require('path');
      const os = require('os');
      const crypto = require('crypto');
      const mailUri = args[0];
      const existing = args[1];
      const envHome = args[2];
      if (typeof mailUri !== 'string' || !mailUri.toLowerCase().startsWith('message:')) {
        throw new Error('refusing non-mail URI');
      }
      let forgeHome = envHome || path.join(os.homedir(), 'Documents', 'Software', 'Forge');
      if (existing && typeof existing === 'string' && existing.includes('.forge')) {
        const marker = path.sep + '.forge' + path.sep;
        const idx = existing.indexOf(marker);
        if (idx > 0) forgeHome = existing.slice(0, idx);
      }
      const digest = crypto.createHash('sha256').update(mailUri).digest('hex').slice(0, 16);
      const dir = path.join(forgeHome, '.forge', 'mail-open');
      fs.mkdirSync(dir, { recursive: true });
      const htmlPath = path.join(dir, digest + '.html');
      const sidecar = path.join(dir, digest + '.json');
      fs.writeFileSync(sidecar, JSON.stringify({ uri: mailUri, digest }, null, 2) + '\\n');
      const safe = mailUri
        .replace(/&/g, '&amp;')
        .replace(/"/g, '&quot;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
      const jsSafe = mailUri.replace(/\\\\/g, '\\\\\\\\').replace(/'/g, "\\\\'").replace(/\\n/g, '');
      const body = [
        '<!DOCTYPE html>',
        '<html lang="en"><head>',
        '<meta charset="utf-8">',
        '<meta http-equiv="refresh" content="0;url=' + safe + '">',
        '<title>Open in Mail</title>',
        "<script>location.replace('" + jsSafe + "');</script>",
        '</head><body>',
        '<p><a href="' + safe + '">Open in Mail</a></p>',
        '</body></html>',
        '',
      ].join('\\n');
      if (!fs.existsSync(htmlPath) || fs.readFileSync(htmlPath, 'utf8') !== body) {
        fs.writeFileSync(htmlPath, body);
      }
      return { path: htmlPath, digest };
    `,
    args: [normalizeMailUri(mailUri), existingHtmlPath || null, forgeHomePath()],
    timeout: 15000,
  });
  if (result && result.success && result.result && result.result.path) {
    return { ok: true, path: result.result.path, digest: result.result.digest };
  }
  // Some SP builds nest return under data
  if (result && result.success && result.data && result.data.path) {
    return { ok: true, path: result.data.path, digest: result.data.digest };
  }
  return { ok: false, reason: errorMessage(result) };
}

function attachmentId(digest) {
  const slug = String(digest || 'mail').slice(0, 8);
  return 'forgeMail' + slug;
}

function findOpenInMailAttachment(attachments) {
  const atts = Array.isArray(attachments) ? attachments : [];
  return atts.find((a) => a && a.title === ATTACH_TITLE) || null;
}

async function ensureMailAttachment(task) {
  if (!task || !task.id || typeof PluginAPI.updateTask !== 'function') {
    return { ok: false, reason: 'no task' };
  }
  const mailUri = parseMailUri(task.notes || '');
  if (!mailUri) {
    return { ok: false, reason: 'no mail uri' };
  }
  const existingHtml = parseMailHtmlPath(task.notes || '');
  const trampoline = await ensureTrampolineFile(mailUri, existingHtml);
  if (!trampoline.ok) {
    return trampoline;
  }
  const htmlPath = trampoline.path;
  const digest = trampoline.digest || 'mail';
  const atts = Array.isArray(task.attachments) ? task.attachments.slice() : [];
  const current = findOpenInMailAttachment(atts);
  if (current && String(current.path || '') === htmlPath) {
    return { ok: true, skipped: true, path: htmlPath };
  }
  const nextAtt = {
    id: (current && current.id) || attachmentId(digest),
    type: 'FILE',
    title: ATTACH_TITLE,
    path: htmlPath,
    icon: 'mail_outline',
  };
  const without = atts.filter((a) => !(a && a.title === ATTACH_TITLE));
  without.push(nextAtt);
  try {
    await PluginAPI.updateTask(task.id, { attachments: without });
    return { ok: true, updated: true, path: htmlPath };
  } catch (err) {
    return {
      ok: false,
      reason: err && err.message ? err.message : String(err),
    };
  }
}

async function openMailByMessageId(mailUri) {
  const uri = normalizeMailUri(mailUri);
  if (!uri.toLowerCase().startsWith('message:')) {
    return { ok: false, reason: 'refusing non-mail URI' };
  }
  const mid = messageIdFromUri(uri);
  if (!mid) {
    return { ok: false, reason: 'could not decode Message-Id' };
  }
  if (typeof PluginAPI.executeNodeScript !== 'function') {
    return {
      ok: false,
      reason: 'executeNodeScript unavailable — re-upload plugin with Node permission.',
    };
  }
  const result = await PluginAPI.executeNodeScript({
    script: `
      const { execFileSync } = require('child_process');
      const mid = args[0];
      if (typeof mid !== 'string' || !mid.includes('@')) {
        throw new Error('refusing invalid Message-Id');
      }
      const script = [
        'on run argv',
        '  set mid to item 1 of argv',
        '  tell application "Mail"',
        '    set found to missing value',
        '    set boxNames to {"Inbox", "INBOX", "Sent Messages", "Sent", "Archive"}',
        '    repeat with acct in every account',
        '      repeat with boxName in boxNames',
        '        try',
        '          set mb to mailbox boxName of acct',
        '          set hits to (messages of mb whose message id is mid)',
        '          if (count of hits) > 0 then',
        '            set found to item 1 of hits',
        '            exit repeat',
        '          end if',
        '        end try',
        '      end repeat',
        '      if found is not missing value then exit repeat',
        '      try',
        '        set mb to inbox of acct',
        '        set hits to (messages of mb whose message id is mid)',
        '        if (count of hits) > 0 then set found to item 1 of hits',
        '      end try',
        '      if found is not missing value then exit repeat',
        '    end repeat',
        '    if found is missing value then error "Mail message not found for Message-Id"',
        '    open found',
        '    activate',
        '  end tell',
        'end run',
      ].join('\\n');
      const out = execFileSync('/usr/bin/osascript', ['-e', script, '--', mid], {
        timeout: 25000,
        encoding: 'utf8',
      });
      return { opened: true, out: String(out || '').trim() };
    `,
    args: [mid],
    timeout: 30000,
  });
  if (result && result.success) {
    return { ok: true };
  }
  return { ok: false, reason: errorMessage(result) };
}

async function openSelectedMail() {
  let task = null;
  try {
    task = await PluginAPI.getSelectedTask();
  } catch (err) {
    console.warn('getSelectedTask failed', err);
  }
  if (!task) {
    PluginAPI.showSnack({
      msg: 'Select a task with a Mail link first.',
      type: 'ERROR',
    });
    return;
  }
  const mailUri = parseMailUri(task.notes || '');
  if (!mailUri) {
    PluginAPI.showSnack({
      msg: 'No <!-- forge:uri:message://… --> on this task. Re-capture with Forge.',
      type: 'ERROR',
    });
    return;
  }

  // Keep / refresh the Links & Files row, then open Mail without using it.
  await ensureMailAttachment(task);

  const direct = await openMailByMessageId(mailUri);
  if (direct.ok) {
    PluginAPI.showSnack({ msg: 'Opened in Mail', type: 'SUCCESS' });
    return;
  }
  console.warn('forge-mail-open: open failed', direct.reason);
  PluginAPI.showSnack({
    msg: String(direct.reason || 'Could not open Mail'),
    type: 'ERROR',
  });
}

async function syncTaskIfMail(taskOrId) {
  let task = taskOrId;
  if (typeof taskOrId === 'string') {
    try {
      const tasks = await PluginAPI.getTasks();
      task = (tasks || []).find((t) => t && t.id === taskOrId) || null;
    } catch (err) {
      console.warn('forge-mail-open: getTasks failed', err);
      return;
    }
  }
  if (!task || !parseMailUri(task.notes || '')) return;
  const result = await ensureMailAttachment(task);
  if (!result.ok && result.reason && result.reason !== 'no mail uri') {
    console.warn('forge-mail-open: ensure attachment', result.reason);
  }
}

async function syncAllMailTasks() {
  if (typeof PluginAPI.getTasks !== 'function') return;
  let tasks = [];
  try {
    tasks = (await PluginAPI.getTasks()) || [];
  } catch (err) {
    console.warn('forge-mail-open: getTasks failed', err);
    return;
  }
  let updated = 0;
  for (const task of tasks) {
    if (!parseMailUri(task.notes || '')) continue;
    const result = await ensureMailAttachment(task);
    if (result.ok && result.updated) updated += 1;
  }
  if (updated > 0) {
    console.log('forge-mail-open: synced Links & Files on', updated, 'mail task(s)');
  }
}

function registerHeader() {
  if (window.__FORGE_MAIL_OPEN_BTN__) {
    console.log('forge-mail-open: header button already registered; skip');
    return;
  }
  window.__FORGE_MAIL_OPEN_BTN__ = true;
  PluginAPI.registerHeaderButton({
    label: 'Open in Mail',
    icon: 'mail_outline',
    onClick: () => {
      openSelectedMail().catch((err) => {
        console.error('forge-mail-open failed', err);
        PluginAPI.showSnack({
          msg:
            'Open in Mail failed: ' +
            (err && err.message ? err.message : String(err)),
          type: 'ERROR',
        });
      });
    },
  });
}

function registerHooks() {
  const hooks = PluginAPI.Hooks || {};
  const taskUpdate = hooks.TASK_UPDATE || 'taskUpdate';
  const currentChange = hooks.CURRENT_TASK_CHANGE || 'currentTaskChange';
  if (typeof PluginAPI.registerHook !== 'function') return;
  try {
    PluginAPI.registerHook(taskUpdate, (payload) => {
      const task = payload && (payload.task || payload);
      syncTaskIfMail(task).catch((err) =>
        console.warn('forge-mail-open: taskUpdate sync', err),
      );
    });
  } catch (err) {
    console.warn('forge-mail-open: registerHook taskUpdate', err);
  }
  try {
    PluginAPI.registerHook(currentChange, () => {
      PluginAPI.getSelectedTask()
        .then((task) => syncTaskIfMail(task))
        .catch((err) => console.warn('forge-mail-open: currentTaskChange', err));
    });
  } catch (err) {
    console.warn('forge-mail-open: registerHook currentTaskChange', err);
  }
}

function boot() {
  registerHeader();
  registerHooks();
  syncAllMailTasks().catch((err) =>
    console.warn('forge-mail-open: initial sync', err),
  );
  console.log(
    'forge-mail-open: Links & Files sync + header button (Message-Id open)',
  );
}

if (typeof PluginAPI.onReady === 'function') {
  PluginAPI.onReady(() => boot());
} else {
  boot();
}
"""


def write_plugin() -> Path:
    """Write plugin sources and zip; return the zip path."""
    PLUGIN_DIR.mkdir(parents=True, exist_ok=True)
    (PLUGIN_DIR / "plugin.js").write_text(PLUGIN_JS, encoding="utf-8")
    manifest = {
        "id": "forge-mail-open",
        "name": "Forge Mail Open",
        "version": "2.0.0",
        "manifestVersion": 1,
        "minSupVersion": "18.0.0",
        "description": (
            "Permanent Links & Files “Open in Mail” row on mail-linked tasks, "
            "plus header button that opens Apple Mail by Message-Id (Node)."
        ),
        "author": "Forge",
        "icon": "icon.svg",
        "permissions": [
            "getSelectedTask",
            "getTasks",
            "updateTask",
            "showSnack",
            "registerHeaderButton",
            "nodeExecution",
        ],
        "hooks": ["taskUpdate", "currentTaskChange"],
    }
    (PLUGIN_DIR / "manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    if ICON_SRC.is_file():
        shutil.copy2(ICON_SRC, PLUGIN_DIR / "icon.svg")
    with zipfile.ZipFile(ZIP_PATH, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(PLUGIN_DIR / "manifest.json", "manifest.json")
        archive.write(PLUGIN_DIR / "plugin.js", "plugin.js")
        icon = PLUGIN_DIR / "icon.svg"
        if icon.is_file():
            archive.write(icon, "icon.svg")
    return ZIP_PATH


def main() -> int:
    """Build the plugin zip and print its path."""
    path = write_plugin()
    print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
