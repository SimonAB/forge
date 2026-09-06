// Forge: open Apple Mail for the selected task without a browser flash.
// Never open message:// via Launch Services / open location (can flash the
// default browser). Never open .html trampolines (default app = browser).
// Instead: decode Message-Id and tell Mail to open the message object.

const URI_COMMENT = /<!--\s*forge:uri:([^\s*]+?)\s*-->/i;
const URI_BRACKET = /\[forge:uri:([^\]]+)\]/i;
const BARE_MESSAGE = /(?:^|\n)\s*(message:[^\s]+)/i;

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
  // AppleScript opens the Mail message *object* (no message://, no .html).
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

async function stripHtmlMailAttachments(task) {
  if (!task || typeof PluginAPI.updateTask !== 'function') return;
  const atts = Array.isArray(task.attachments) ? task.attachments : [];
  const next = atts.filter((a) => {
    if (!a || a.title !== 'Open in Mail') return true;
    const path = String(a.path || '');
    return !(path.endsWith('.html') || path.indexOf('mail-open') !== -1);
  });
  if (next.length === atts.length) return;
  try {
    await PluginAPI.updateTask(task.id, { attachments: next });
  } catch (err) {
    console.warn('forge-mail-open: could not strip HTML attachments', err);
  }
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

  await stripHtmlMailAttachments(task);

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

function register() {
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
  console.log('forge-mail-open: header button registered (Message-Id object open)');
}

function boot() {
  register();
}

if (typeof PluginAPI.onReady === 'function') {
  PluginAPI.onReady(() => boot());
} else {
  boot();
}
